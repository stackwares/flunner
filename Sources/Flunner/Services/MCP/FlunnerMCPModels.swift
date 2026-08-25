import Foundation
import MCP

struct FlunnerMCPToolResult: Sendable {
    let text: String
    let isError: Bool

    static func ok(_ text: String) -> FlunnerMCPToolResult {
        FlunnerMCPToolResult(text: text, isError: false)
    }

    static func ok<T: Encodable>(_ value: T) -> FlunnerMCPToolResult {
        do {
            return .ok(try FlunnerMCPJSON.encode(value))
        } catch {
            return .error(error.localizedDescription)
        }
    }

    static func error(_ message: String) -> FlunnerMCPToolResult {
        FlunnerMCPToolResult(text: message, isError: true)
    }

    static func blocked(_ reason: String?) -> FlunnerMCPToolResult {
        .error(reason ?? "This action is not available right now.")
    }
}

struct FlunnerMCPArguments: Sendable {
    private let values: [String: Value]

    init(_ values: [String: Value]? = nil) {
        self.values = values ?? [:]
    }

    init(
        strings: [String: String] = [:],
        bools: [String: Bool] = [:],
        ints: [String: Int] = [:],
        stringArrays: [String: [String]] = [:]
    ) {
        var values: [String: Value] = [:]
        for (key, value) in strings { values[key] = .string(value) }
        for (key, value) in bools { values[key] = .bool(value) }
        for (key, value) in ints { values[key] = .int(value) }
        for (key, value) in stringArrays {
            values[key] = .array(value.map { .string($0) })
        }
        self.values = values
    }

    func string(_ key: String) -> String? {
        values[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    func bool(_ key: String) -> Bool? {
        if let value = values[key]?.boolValue { return value }
        if let text = values[key]?.stringValue {
            if ["true", "1", "yes"].contains(text.lowercased()) { return true }
            if ["false", "0", "no"].contains(text.lowercased()) { return false }
        }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let value = values[key]?.intValue { return value }
        if let value = values[key]?.doubleValue { return Int(value) }
        if let text = values[key]?.stringValue { return Int(text) }
        return nil
    }

    func strings(_ key: String) -> [String] {
        if let array = values[key]?.arrayValue {
            return array.compactMap(\.stringValue)
        }
        if let single = string(key) {
            return [single]
        }
        return []
    }

    func requireString(_ key: String) throws -> String {
        guard let value = string(key) else {
            throw FlunnerMCPArgumentError.missing(key)
        }
        return value
    }

    func requireBool(_ key: String) throws -> Bool {
        guard let value = bool(key) else {
            throw FlunnerMCPArgumentError.missing(key)
        }
        return value
    }
}

enum FlunnerMCPArgumentError: LocalizedError {
    case missing(String)

    var errorDescription: String? {
        switch self {
        case let .missing(key): "Missing required argument: \(key)"
        }
    }
}

enum FlunnerMCPJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}

enum FlunnerMCPAuth {
    static let preferredPort: UInt16 = 47_321
    static let portAttempts = 20

    static func bearerToken(from headers: [String: String]) -> String? {
        guard let value = headers.first(where: { $0.key.lowercased() == "authorization" })?.value else {
            return nil
        }
        let prefix = "Bearer "
        guard value.count > prefix.count,
              value.prefix(prefix.count).caseInsensitiveCompare(prefix) == .orderedSame else {
            return nil
        }
        let token = value.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    static func isAuthorized(headers: [String: String], token: String) -> Bool {
        bearerToken(from: headers) == token
    }
}

struct FlunnerMCPDiscoveryFile: Codable {
    let url: String
    let token: String
    let pid: Int32
}

struct FlunnerMCPStatusPayload: Encodable {
    struct DevicePayload: Encodable {
        let id: String
        let name: String
        let displayName: String
        let platform: String
        let emulator: Bool
        let emulatorId: String?
        let isRunning: Bool?
    }

    struct ConfigPayload: Encodable {
        let name: String
        let displayName: String
        let flutterMode: String?
    }

    struct RunPayload: Encodable {
        let id: String
        let projectPath: String
        let projectName: String
        let deviceId: String
        let deviceName: String
        let configurationName: String
        let state: String
        let startedAt: String
    }

    struct SDKPayload: Encodable {
        let flutterPath: String
        let flutterVersion: String
        let channel: String
        let dartVersion: String
    }

    let projectPath: String?
    let projectName: String
    let status: String
    let daemon: String
    let selectedDeviceId: String?
    let selectedLaunchConfigName: String?
    let selectedLogChannel: String
    let selectedLiveRunID: String?
    let canRun: Bool
    let canStop: Bool
    let canHotReload: Bool
    let canPubGet: Bool
    let canCleanAndPubGet: Bool
    let isAppRunning: Bool
    let runBlockReason: String?
    let pubGetBlockReason: String?
    let cleanAndPubGetBlockReason: String?
    let devices: [DevicePayload]
    let emulators: [DevicePayload]
    let launchConfigs: [ConfigPayload]
    let liveRuns: [RunPayload]
    let sdk: SDKPayload?
}

enum FlunnerMCPSchema {
    static func object(_ properties: [String: Value], required: [String] = []) -> Value {
        var schema: [String: Value] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        return .object(schema)
    }

    static func string(_ description: String) -> Value {
        .object([
            "type": .string("string"),
            "description": .string(description),
        ])
    }

    static func bool(_ description: String) -> Value {
        .object([
            "type": .string("boolean"),
            "description": .string(description),
        ])
    }

    static func integer(_ description: String) -> Value {
        .object([
            "type": .string("integer"),
            "description": .string(description),
        ])
    }

    static func strings(_ description: String) -> Value {
        .object([
            "type": .string("array"),
            "description": .string(description),
            "items": .object(["type": .string("string")]),
        ])
    }

    static func tool(
        _ name: String,
        description: String,
        properties: [String: Value] = [:],
        required: [String] = [],
        readOnly: Bool = false,
        destructive: Bool = false
    ) -> Tool {
        Tool(
            name: name,
            description: description,
            inputSchema: object(properties, required: required),
            annotations: .init(
                title: name,
                readOnlyHint: readOnly,
                destructiveHint: destructive
            )
        )
    }
}

extension AppState {
    var mcpName: String {
        switch self {
        case .idle: "idle"
        case .starting: "starting"
        case .running: "running"
        case .stopping: "stopping"
        case .error: "error"
        }
    }
}

extension DaemonState {
    var mcpName: String {
        switch self {
        case .idle: "idle"
        case .starting: "starting"
        case .connected: "connected"
        case let .failed(message): "failed: \(message)"
        case .stopped: "stopped"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
