import Foundation

enum AgentMCPTarget: String, CaseIterable, Identifiable, Codable, Hashable {
    case cursor
    case claudeCode
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cursor: "Cursor"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    func configURL(homeDirectory: URL) -> URL {
        switch self {
        case .cursor:
            homeDirectory.appendingPathComponent(".cursor/mcp.json")
        case .claudeCode:
            homeDirectory.appendingPathComponent(".claude.json")
        case .codex:
            homeDirectory.appendingPathComponent(".codex/config.toml")
        }
    }

    func isInstalled(homeDirectory: URL) -> Bool {
        switch self {
        case .cursor:
            FileManager.default.fileExists(atPath: homeDirectory.appendingPathComponent(".cursor").path)
        case .claudeCode:
            FileManager.default.fileExists(atPath: configURL(homeDirectory: homeDirectory).path)
                || FileManager.default.fileExists(atPath: homeDirectory.appendingPathComponent(".claude").path)
        case .codex:
            FileManager.default.fileExists(atPath: homeDirectory.appendingPathComponent(".codex").path)
        }
    }
}

enum AgentMCPConnectionStatus: String, Equatable {
    case connected
    case outdated
    case notConfigured
    case notInstalled

    var label: String {
        switch self {
        case .connected: "Connected"
        case .outdated: "Outdated"
        case .notConfigured: "Not configured"
        case .notInstalled: "Not installed"
        }
    }
}

struct AgentMCPAgentState: Identifiable, Equatable {
    let target: AgentMCPTarget
    let status: AgentMCPConnectionStatus
    let configPath: String

    var id: String { target.id }
}

struct AgentMCPSyncResult: Equatable {
    let target: AgentMCPTarget
    let success: Bool
    let message: String
}

struct AgentMCPConfigWriter {
    static let serverKey = "flunner"

    var homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    func inspectAll(url: String, token: String) -> [AgentMCPAgentState] {
        AgentMCPTarget.allCases.map { target in
            inspect(target: target, url: url, token: token)
        }
    }

    func hasFlunnerEntry(for target: AgentMCPTarget) -> Bool {
        readExistingEntry(target: target) != nil
    }

    func inspect(target: AgentMCPTarget, url: String, token: String) -> AgentMCPAgentState {
        let path = target.configURL(homeDirectory: homeDirectory).path
        guard target.isInstalled(homeDirectory: homeDirectory) else {
            return AgentMCPAgentState(target: target, status: .notInstalled, configPath: path)
        }

        let existing = readExistingEntry(target: target)
        guard let existing else {
            return AgentMCPAgentState(target: target, status: .notConfigured, configPath: path)
        }

        if existing.url == url, existing.token == token {
            return AgentMCPAgentState(target: target, status: .connected, configPath: path)
        }
        return AgentMCPAgentState(target: target, status: .outdated, configPath: path)
    }

    func sync(targets: [AgentMCPTarget], url: String, token: String) -> [AgentMCPSyncResult] {
        targets.map { target in
            sync(target: target, url: url, token: token)
        }
    }

    func sync(target: AgentMCPTarget, url: String, token: String) -> AgentMCPSyncResult {
        guard target.isInstalled(homeDirectory: homeDirectory) else {
            return AgentMCPSyncResult(
                target: target,
                success: false,
                message: "\(target.displayName) was not detected on this Mac."
            )
        }

        do {
            switch target {
            case .cursor, .claudeCode:
                try writeJSONConfig(at: target.configURL(homeDirectory: homeDirectory), url: url, token: token)
            case .codex:
                try writeCodexConfig(at: target.configURL(homeDirectory: homeDirectory), url: url, token: token)
            }
            return AgentMCPSyncResult(
                target: target,
                success: true,
                message: "Updated \(target.displayName) config."
            )
        } catch {
            return AgentMCPSyncResult(
                target: target,
                success: false,
                message: error.localizedDescription
            )
        }
    }

    private struct ExistingEntry {
        let url: String
        let token: String
    }

    private func readExistingEntry(target: AgentMCPTarget) -> ExistingEntry? {
        let fileURL = target.configURL(homeDirectory: homeDirectory)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        switch target {
        case .cursor, .claudeCode:
            return readJSONEntry(at: fileURL)
        case .codex:
            return readCodexEntry(at: fileURL)
        }
    }

    private func readJSONEntry(at url: URL) -> ExistingEntry? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any],
              let flunner = servers[Self.serverKey] as? [String: Any],
              let serverURL = flunner["url"] as? String else {
            return nil
        }
        let headers = flunner["headers"] as? [String: Any]
        let authorization = headers?["Authorization"] as? String
        let token = authorization?.replacingOccurrences(of: "Bearer ", with: "") ?? ""
        return ExistingEntry(url: serverURL, token: token)
    }

    private func readCodexEntry(at url: URL) -> ExistingEntry? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let section = parseCodexFlunnerSection(from: contents)
        guard let serverURL = section["url"] else { return nil }
        let token = section["Authorization"]?
            .replacingOccurrences(of: "Bearer ", with: "") ?? ""
        return ExistingEntry(url: serverURL, token: token)
    }

    private func writeJSONConfig(at url: URL, url serverURL: String, token: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var root: [String: Any]
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        } else {
            root = [:]
        }

        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers[Self.serverKey] = [
            "url": serverURL,
            "headers": [
                "Authorization": "Bearer \(token)",
            ],
        ]
        root["mcpServers"] = servers

        try backupIfNeeded(url)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try writeAtomically(data: data, to: url)
    }

    private func writeCodexConfig(at url: URL, url serverURL: String, token: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let block = """
        [mcp_servers.\(Self.serverKey)]
        url = "\(serverURL)"
        http_headers = { Authorization = "Bearer \(token)" }
        enabled = true

        """
        let contents: String
        if FileManager.default.fileExists(atPath: url.path),
           let existing = try? String(contentsOf: url, encoding: .utf8) {
            try backupIfNeeded(url)
            contents = replaceCodexFlunnerSection(in: existing, with: block)
        } else {
            contents = block
        }

        try writeAtomically(data: Data(contents.utf8), to: url)
    }

    private func replaceCodexFlunnerSection(in contents: String, with block: String) -> String {
        let lines = contents.components(separatedBy: "\n")
        var output: [String] = []
        var index = 0
        let header = "[mcp_servers.\(Self.serverKey)]"

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces) == header {
                index += 1
                while index < lines.count {
                    let next = lines[index]
                    if next.hasPrefix("[") && next.hasSuffix("]") {
                        break
                    }
                    index += 1
                }
                continue
            }
            output.append(line)
            index += 1
        }

        var merged = output.joined(separator: "\n")
        if !merged.hasSuffix("\n") {
            merged.append("\n")
        }
        if !merged.isEmpty {
            merged.append("\n")
        }
        merged.append(block)
        return merged
    }

    private func parseCodexFlunnerSection(from contents: String) -> [String: String] {
        let lines = contents.components(separatedBy: "\n")
        var index = 0
        let header = "[mcp_servers.\(Self.serverKey)]"
        var values: [String: String] = [:]

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces) == header {
                index += 1
                while index < lines.count {
                    let line = lines[index].trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("[") && line.hasSuffix("]") {
                        return values
                    }
                    if line.hasPrefix("url = ") {
                        values["url"] = parseTOMLString(line.dropFirst("url = ".count))
                    }
                    if line.contains("Authorization = ") {
                        if let range = line.range(of: "Authorization = ") {
                            values["Authorization"] = parseTOMLString(line[range.upperBound...])
                        }
                    }
                    index += 1
                }
                return values
            }
            index += 1
        }
        return values
    }

    private func parseTOMLString<S: StringProtocol>(_ value: S) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            return String(trimmed.dropFirst().dropLast())
        }
        return String(trimmed)
    }

    private func backupIfNeeded(_ url: URL) throws {
        let backupURL = url.appendingPathExtension("bak")
        guard FileManager.default.fileExists(atPath: url.path),
              !FileManager.default.fileExists(atPath: backupURL.path) else {
            return
        }
        try FileManager.default.copyItem(at: url, to: backupURL)
    }

    private func writeAtomically(data: Data, to url: URL) throws {
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".flunner-mcp-\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: url)
    }
}

enum AgentMCPPreferences {
    static let autoSyncAgentsKey = "mcpAutoSyncAgents"

    static func hasStoredPreferences() -> Bool {
        UserDefaults.standard.object(forKey: autoSyncAgentsKey) != nil
    }

    static func storedAutoSyncAgents() -> Set<AgentMCPTarget> {
        guard let rawValues = UserDefaults.standard.stringArray(forKey: autoSyncAgentsKey) else {
            return []
        }
        return Set(rawValues.compactMap(AgentMCPTarget.init(rawValue:)))
    }

    /// Agents that should re-sync on launch when the user has not changed auto-sync settings.
    static func defaultAutoSyncAgents(using writer: AgentMCPConfigWriter) -> Set<AgentMCPTarget> {
        Set(AgentMCPTarget.allCases.filter { writer.hasFlunnerEntry(for: $0) })
    }

    static func effectiveAutoSyncAgents(using writer: AgentMCPConfigWriter) -> Set<AgentMCPTarget> {
        if hasStoredPreferences() {
            return storedAutoSyncAgents()
        }
        return defaultAutoSyncAgents(using: writer)
    }

    static func setAutoSyncAgents(_ agents: Set<AgentMCPTarget>) {
        UserDefaults.standard.set(agents.map(\.rawValue).sorted(), forKey: autoSyncAgentsKey)
    }

    static func enableAutoSync(for target: AgentMCPTarget, using writer: AgentMCPConfigWriter) {
        setAutoSyncEnabled(true, for: target, using: writer)
    }

    static func isAutoSyncEnabled(for target: AgentMCPTarget, using writer: AgentMCPConfigWriter) -> Bool {
        effectiveAutoSyncAgents(using: writer).contains(target)
    }

    static func setAutoSyncEnabled(_ enabled: Bool, for target: AgentMCPTarget, using writer: AgentMCPConfigWriter) {
        var agents = effectiveAutoSyncAgents(using: writer)
        if enabled {
            agents.insert(target)
        } else {
            agents.remove(target)
        }
        setAutoSyncAgents(agents)
    }
}
