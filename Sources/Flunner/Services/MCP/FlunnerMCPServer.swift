import AppKit
import Combine
import Foundation
import MCP

@MainActor
final class FlunnerMCPServer: ObservableObject {
    static let preferredPort = FlunnerMCPAuth.preferredPort

    @Published private(set) var url: URL?
    @Published private(set) var token: String?
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var agentStates: [AgentMCPAgentState] = []
    @Published private(set) var lastSyncResults: [AgentMCPSyncResult] = []

    private let viewModel: WorkspaceViewModel
    private let sourceControl: SourceControlViewModel
    private let configWriter: AgentMCPConfigWriter
    private var listener: FlunnerMCPHTTPListener?
    private var mcpServer: Server?
    private var transport: StatelessHTTPServerTransport?
    private var runTask: Task<Void, Never>?
    private var defaultsObserver: NSObjectProtocol?

    init(
        viewModel: WorkspaceViewModel,
        sourceControl: SourceControlViewModel,
        configWriter: AgentMCPConfigWriter = AgentMCPConfigWriter()
    ) {
        self.viewModel = viewModel
        self.sourceControl = sourceControl
        self.configWriter = configWriter
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncWithPreference()
            }
        }
    }

    var connectionURLString: String {
        url?.absoluteString ?? "http://127.0.0.1:\(Self.preferredPort)/mcp"
    }

    var cursorConfigSnippet: String {
        let token = token ?? "<token>"
        return """
        {
          "mcpServers": {
            "flunner": {
              "url": "\(connectionURLString)",
              "headers": {
                "Authorization": "Bearer \(token)"
              }
            }
          }
        }
        """
    }

    func startIfEnabled() {
        syncWithPreference()
    }

    func start() {
        stop(removeDiscovery: false)
        lastError = nil
        let token = UUID().uuidString.lowercased()
        let host = FlunnerMCPToolHost(viewModel: viewModel, sourceControl: sourceControl)

        runTask = Task { [weak self] in
            do {
                let transport = StatelessHTTPServerTransport()
                let server = Server(
                    name: "Flunner",
                    version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
                    instructions: "Control the live Flunner Flutter workbench: projects, devices, runs, logs, git, and the integrated terminal. Call get_status first.",
                    capabilities: .init(tools: .init())
                )
                try await server.start(transport: transport)
                await FlunnerMCPToolCatalog.register(on: server, host: host)

                let listener = FlunnerMCPHTTPListener(token: token) { request in
                    await transport.handleRequest(request)
                }
                let port = try listener.start(preferredPort: Self.preferredPort)
                await MainActor.run {
                    guard let self, !Task.isCancelled else {
                        listener.stop()
                        return
                    }
                    self.listener = listener
                    self.transport = transport
                    self.mcpServer = server
                    self.token = token
                    self.url = URL(string: "http://127.0.0.1:\(port)/mcp")
                    self.isRunning = true
                    self.writeDiscoveryFile()
                    self.refreshAgentStates()
                    self.syncEnabledAgents()
                }
            } catch {
                await MainActor.run {
                    self?.lastError = error.localizedDescription
                    self?.isRunning = false
                    self?.removeDiscoveryFile()
                }
            }
        }
    }

    func stop() {
        stop(removeDiscovery: true)
    }

    private func stop(removeDiscovery: Bool) {
        runTask?.cancel()
        runTask = nil
        listener?.stop()
        listener = nil
        let server = mcpServer
        let existingTransport = transport
        mcpServer = nil
        self.transport = nil
        url = nil
        token = nil
        isRunning = false
        agentStates = []
        if removeDiscovery {
            removeDiscoveryFile()
        }
        Task {
            await server?.stop()
            await existingTransport?.disconnect()
        }
    }

    private func syncWithPreference() {
        let enabled = UserDefaults.standard.object(forKey: PreferenceKeys.mcpEnabled) as? Bool ?? true
        if enabled {
            if !isRunning, runTask == nil {
                start()
            }
        } else if isRunning || runTask != nil {
            stop()
        }
    }

    func refreshAgentStates() {
        guard let url, let token else {
            agentStates = configWriter.inspectAll(
                url: connectionURLString,
                token: token ?? ""
            )
            return
        }
        agentStates = configWriter.inspectAll(url: url.absoluteString, token: token)
    }

    func connectAgents(_ targets: [AgentMCPTarget]) {
        guard let url, let token else {
            lastError = "Start the MCP server before connecting agents."
            return
        }

        let results = configWriter.sync(
            targets: targets,
            url: url.absoluteString,
            token: token
        )
        lastSyncResults = results
        for target in targets where results.contains(where: { $0.target == target && $0.success }) {
            AgentMCPPreferences.enableAutoSync(for: target, using: configWriter)
        }
        refreshAgentStates()

        let failures = results.filter { !$0.success }
        if failures.isEmpty {
            lastError = nil
        } else {
            lastError = failures.map(\.message).joined(separator: " ")
        }
    }

    func syncEnabledAgents() {
        guard let url, let token, isRunning else { return }
        let enabled = AgentMCPPreferences.effectiveAutoSyncAgents(using: configWriter)
        guard !enabled.isEmpty else { return }

        let results = configWriter.sync(
            targets: Array(enabled),
            url: url.absoluteString,
            token: token
        )
        lastSyncResults = results
        refreshAgentStates()

        let failures = results.filter { !$0.success }
        if !failures.isEmpty {
            lastError = failures.map(\.message).joined(separator: " ")
        }
    }

    func setAutoSyncEnabled(_ enabled: Bool, for target: AgentMCPTarget) {
        AgentMCPPreferences.setAutoSyncEnabled(enabled, for: target, using: configWriter)
    }

    func isAutoSyncEnabled(for target: AgentMCPTarget) -> Bool {
        AgentMCPPreferences.isAutoSyncEnabled(for: target, using: configWriter)
    }

    func revealDiscoveryFile() {
        let url = discoveryFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func openConfigFile(for target: AgentMCPTarget) {
        let configURL = target.configURL(homeDirectory: configWriter.homeDirectory)
        if FileManager.default.fileExists(atPath: configURL.path) {
            NSWorkspace.shared.open(configURL)
        } else {
            NSWorkspace.shared.open(configURL.deletingLastPathComponent())
        }
    }

    private func writeDiscoveryFile() {
        guard let url, let token else { return }
        let file = discoveryFileURL()
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let payload = FlunnerMCPDiscoveryFile(
                url: url.absoluteString,
                token: token,
                pid: ProcessInfo.processInfo.processIdentifier
            )
            let data = try JSONEncoder().encode(payload)
            try data.write(to: file, options: .atomic)
        } catch {
            lastError = "Could not write MCP discovery file: \(error.localizedDescription)"
        }
    }

    private func removeDiscoveryFile() {
        try? FileManager.default.removeItem(at: discoveryFileURL())
    }

    private func discoveryFileURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flunner", isDirectory: true)
            .appendingPathComponent("mcp-server.json")
    }
}
