import Foundation
import Combine

enum DaemonState: Equatable {
    case idle
    case starting
    case connected
    case failed(String)
    case stopped
}

@MainActor
class FlutterDaemon: ObservableObject {
    @Published var devices: [Device] = []
    @Published var emulators: [Device] = []
    @Published var isRunning = false
    @Published var state: DaemonState = .idle
    @Published var status: String = ""
    var onLogOutput: ((String, LogEntryType) -> Void)?
    
    var runningEmulatorIds: Set<String> {
        let connectedIds = Set(devices.map(\.id))
        return Set(emulators.filter { connectedIds.contains($0.id) }.map(\.id))
    }

    private var process: Process?
    private var stdoutPipe = Pipe()
    private var stdinPipe = Pipe()
    private var stderrPipe = Pipe()
    private var requestId = 0
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    
    deinit {
        process?.terminate()
    }

    func start() {
        guard state != .starting, !isRunning else { return }

        stdoutPipe = Pipe()
        stdinPipe = Pipe()
        stderrPipe = Pipe()
        stdoutBuffer = ""
        stderrBuffer = ""
        
        state = .starting
        status = "Starting Flutter daemon…"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-ic", "flutter daemon"]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                let exitCode = process.terminationStatus
                self?.isRunning = false
                self?.devices.removeAll()
                self?.emulators.removeAll()
                if exitCode == 0 {
                    self?.state = .stopped
                    self?.status = "Daemon stopped"
                } else {
                    self?.state = .failed("Exited with code \(exitCode)")
                    self?.status = "Daemon stopped unexpectedly (code \(exitCode))"
                }
                self?.onLogOutput?(self?.status ?? "Daemon stopped", .error)
            }
        }
        
        let stdoutHandle = stdoutPipe.fileHandleForReading
        stdoutHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.processBuffer(data: data, isStderr: false)
            }
        }
        
        let stderrHandle = stderrPipe.fileHandleForReading
        stderrHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.processBuffer(data: data, isStderr: true)
            }
        }
        
        do {
            onLogOutput?("flutter daemon", .command)
            try process.run()
            self.process = process
            self.isRunning = true
            self.status = "Daemon running, waiting for connection…"
            sendRequest(method: "device.enable", params: [:])
        } catch {
            self.state = .failed(error.localizedDescription)
            self.status = "Failed to start daemon: \(error.localizedDescription)"
            onLogOutput?("Error: \(error.localizedDescription)", .error)
        }
    }
    
    func stop() {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        process = nil
        isRunning = false
        state = .stopped
        status = "Daemon stopped"
        devices.removeAll()
        emulators.removeAll()
    }
    
    func refreshDevices() {
        guard isRunning else { return }
        sendRequest(method: "device.getDevices", params: [:])
    }

    func restart() {
        stop()
        start()
    }
    
    func launchEmulator(_ emulatorId: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-ic", "flutter emulators --launch \(emulatorId)"]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        process.terminationHandler = { [weak self] process in
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            Task { @MainActor in
                if process.terminationStatus != 0 {
                    let msg = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown"
                    self?.onLogOutput?("Failed to launch emulator: \(msg)", .error)
                }
            }
        }

        do { try process.run() }
        catch { onLogOutput?("Failed to launch emulator: \(error.localizedDescription)", .error) }
    }

    func getEmulators() {
        Task.detached { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-ic", "flutter emulators"]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                await MainActor.run {
                    self?.onLogOutput?("getEmulators: failed to run: \(error.localizedDescription)", .error)
                }
                return
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            await MainActor.run {
                if process.terminationStatus != 0 {
                    let msg = String(data: errorData, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit code \(process.terminationStatus)"
                    self?.onLogOutput?("getEmulators: \(msg)", .error)
                    return
                }
                guard let output = String(data: data, encoding: .utf8) else {
                    self?.onLogOutput?("getEmulators: could not decode output", .error)
                    return
                }

                let result = Self.parseEmulatorTable(output)
                self?.emulators = result
            }
        }
    }

    private nonisolated static func parseEmulatorTable(_ output: String) -> [Device] {
        let lines = output.components(separatedBy: "\n")
        guard let headerIndex = lines.firstIndex(where: { $0.contains("•") }) else { return [] }

        var emulators: [Device] = []
        for line in lines[(headerIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("To run"), !trimmed.hasPrefix("To create"),
                  !trimmed.hasPrefix("You can find") else { if trimmed.isEmpty { continue } else { break } }

            let columns = trimmed.components(separatedBy: "•").map { $0.trimmingCharacters(in: .whitespaces) }
            guard columns.count >= 2 else { continue }

            let id = columns[0]
            let name = columns[1]
            let platform = columns.count >= 4 ? columns[3].lowercased() : ""

            emulators.append(Device(
                id: id,
                name: name,
                platform: platform,
                platformType: nil,
                category: nil,
                emulator: true,
                emulatorId: id,
                ephemeral: nil
            ))
        }
        return emulators
    }

    func killEmulator(_ device: Device) {
        let platform = device.platform.lowercased()
        let deviceId = device.id

        let executable: String
        let arguments: [String]

        if platform.contains("ios") {
            executable = "/usr/bin/xcrun"
            arguments = ["simctl", "shutdown", deviceId]
        } else if platform.contains("android") {
            executable = "/usr/bin/env"
            arguments = ["adb", "-s", deviceId, "emu", "kill"]
        } else {
            onLogOutput?("Cannot kill device on platform \(device.platform)", .error)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.terminationHandler = { [weak self] process in
            let exitCode = process.terminationStatus
            Task { @MainActor in
                if exitCode == 0 {
                    self?.onLogOutput?("Killed \(device.displayName)", .info)
                } else {
                    self?.onLogOutput?("Failed to kill \(device.displayName) (exit code \(exitCode))", .error)
                }
            }
        }

        do {
            try process.run()
            onLogOutput?("Killing \(device.displayName)...", .info)
        } catch {
            onLogOutput?("Failed to kill \(device.displayName): \(error.localizedDescription)", .error)
        }
    }
    
    private func sendRequest(method: String, params: [String: Any]) {
        requestId += 1
        let id = requestId
        let request: [[String: Any]] = [[
            "id": id,
            "method": method,
            "params": params
        ]]
        
        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let string = String(data: data, encoding: .utf8) else { return }
        
        if let inputData = "\(string)\n".data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(inputData)
        }
    }
    
    private func processBuffer(data: Data, isStderr: Bool) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        
        if isStderr {
            stderrBuffer += normalized
        } else {
            stdoutBuffer += normalized
        }
        
        let buffer = isStderr ? stderrBuffer : stdoutBuffer
        
        if buffer.contains("\n") {
            let lines = buffer.components(separatedBy: "\n")
            let completeLines = lines.dropLast()
            let remaining = lines.last ?? ""
            
            if isStderr {
                stderrBuffer = remaining
            } else {
                stdoutBuffer = remaining
            }
            
            for line in completeLines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                
                if !isStderr && trimmed.hasPrefix("[{") && trimmed.hasSuffix("}]") {
                    if let lineData = trimmed.data(using: .utf8) {
                        let messages = DaemonMessage.parse(data: lineData)
                        for message in messages {
                            handleMessage(message)
                        }
                    }
                } else {
                    let type: LogEntryType = isStderr ? .error : classifyOutput(trimmed)
                    onLogOutput?(trimmed, type)
                }
            }
        }
    }
    
    private func classifyOutput(_ text: String) -> LogEntryType {
        let lower = text.lowercased()
        if lower.hasPrefix("error") || lower.contains("error:") || lower.contains("exception") || lower.contains("failed") || lower.contains("failure") {
            return .error
        }
        if lower.hasPrefix("flutter") || lower.hasPrefix("building") || lower.hasPrefix("downloading") || lower.hasPrefix("starting") {
            return .command
        }
        return .info
    }
    
    private func handleMessage(_ message: DaemonMessage) {
        if let error = message.error {
            status = "Daemon error: \(error)"
            onLogOutput?("Daemon error: \(error)", .error)
            return
        }

        if let event = message.event {
            switch event {
            case "device.added":
                if let device = message.device,
                   !devices.contains(where: { $0.id == device.id }) {
                    devices.append(device)
                    status = "Device added: \(device.name)"
                    onLogOutput?("Device: \(device.displayName)", .info)
                }
            case "device.removed":
                if let device = message.device {
                    devices.removeAll { $0.id == device.id }
                    status = "Device removed: \(device.name)"
                    onLogOutput?("Device removed: \(device.name)", .info)
                }
            case "daemon.connected":
                state = .connected
                status = "Daemon connected"
                onLogOutput?("Daemon connected", .info)
                getEmulators()
            case "daemon.logMessage":
                break
            default:
                break
            }
        }
    }
}
