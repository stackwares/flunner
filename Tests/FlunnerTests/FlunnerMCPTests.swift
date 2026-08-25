import XCTest
@testable import Flunner

@MainActor
final class FlunnerMCPTests: XCTestCase {
    func testGetStatusIncludesOpenedProjectAndDevices() async throws {
        let context = try await makeContext(named: "MCPStatus")
        defer { try? FileManager.default.removeItem(at: context.root) }

        let result = await context.host.call(name: "get_status", arguments: FlunnerMCPArguments())

        XCTAssertFalse(result.isError, result.text)
        XCTAssertTrue(result.text.contains(context.viewModel.projectName), result.text)
        XCTAssertTrue(result.text.contains(iosDevice.id), result.text)
        XCTAssertTrue(result.text.contains("canPubGet"), result.text)
    }

    func testRunThenGetLogsThenStop() async throws {
        let context = try await makeContext(named: "MCPRunLogs")
        defer { try? FileManager.default.removeItem(at: context.root) }

        context.viewModel.selectDevice(iosDevice.id)
        let run = await context.host.call(name: "run", arguments: FlunnerMCPArguments())
        XCTAssertFalse(run.isError)

        let logs = await context.host.call(
            name: "get_logs",
            arguments: FlunnerMCPArguments(strings: ["channel": "console"])
        )
        XCTAssertFalse(logs.isError)
        XCTAssertTrue(logs.text.contains("Mock app running"))

        let stop = await context.host.call(name: "stop", arguments: FlunnerMCPArguments())
        XCTAssertFalse(stop.isError)
        XCTAssertEqual(context.runners.runners[iosDevice.id]?.stopCount, 1)
        XCTAssertFalse(context.viewModel.hasRunningProjects)
    }

    func testPubGetAllowedWhileSessionBlocksClean() async throws {
        let context = try await makeContext(named: "MCPMaintenance")
        defer { try? FileManager.default.removeItem(at: context.root) }

        context.viewModel.selectDevice(iosDevice.id)
        _ = await context.host.call(name: "run", arguments: FlunnerMCPArguments())

        let pubGet = await context.host.call(name: "pub_get", arguments: FlunnerMCPArguments())
        XCTAssertFalse(pubGet.isError)
        XCTAssertEqual(context.maintenance.operations, [.pubGet])

        context.maintenance.finish(.succeeded)

        context.viewModel.selectDevice(iosDevice.id)
        _ = await context.host.call(name: "run", arguments: FlunnerMCPArguments())

        let clean = await context.host.call(name: "clean_and_pub_get", arguments: FlunnerMCPArguments())
        XCTAssertTrue(clean.isError)
        XCTAssertTrue(clean.text.contains("Stop all running sessions before cleaning."))
    }

    func testSelectSessionRestoresDeviceAndConfiguration() async throws {
        let context = try await makeContext(named: "MCPSelectSession", devices: [iosDevice, androidDevice])
        defer { try? FileManager.default.removeItem(at: context.root) }

        context.viewModel.selectDevice(iosDevice.id)
        context.viewModel.selectConfiguration("Debug")
        _ = await context.host.call(name: "run", arguments: FlunnerMCPArguments())

        context.viewModel.selectDevice(androidDevice.id)
        context.viewModel.selectConfiguration("Profile")
        _ = await context.host.call(name: "run", arguments: FlunnerMCPArguments())

        let iosRun = try XCTUnwrap(context.viewModel.liveRun(forDeviceId: iosDevice.id))
        let selected = await context.host.call(
            name: "select_session",
            arguments: FlunnerMCPArguments(strings: ["id": iosRun.id.uuidString])
        )

        XCTAssertFalse(selected.isError)
        XCTAssertEqual(context.viewModel.selectedDeviceId, iosDevice.id)
        XCTAssertEqual(context.viewModel.selectedLaunchConfigName, "Debug")
        XCTAssertTrue(context.viewModel.canStopSelectedRun)
        XCTAssertTrue(context.viewModel.canControlSelectedRun)
    }

    func testMissingBearerIsUnauthorized() {
        XCTAssertFalse(FlunnerMCPAuth.isAuthorized(headers: [:], token: "secret"))
        XCTAssertFalse(FlunnerMCPAuth.isAuthorized(headers: ["Authorization": "Token secret"], token: "secret"))
        XCTAssertFalse(FlunnerMCPAuth.isAuthorized(headers: ["Authorization": "Bearer other"], token: "secret"))
        XCTAssertTrue(FlunnerMCPAuth.isAuthorized(headers: ["Authorization": "Bearer secret"], token: "secret"))
        XCTAssertTrue(FlunnerMCPAuth.isAuthorized(headers: ["authorization": "Bearer secret"], token: "secret"))
    }

    private var iosDevice: Device {
        Device(
            id: "ios-device",
            name: "iPhone",
            platform: "ios",
            platformType: "iphoneos",
            category: "mobile",
            emulator: true,
            emulatorId: "iphone-sim",
            ephemeral: true
        )
    }

    private var androidDevice: Device {
        Device(
            id: "android-device",
            name: "Pixel",
            platform: "android",
            platformType: "android",
            category: "mobile",
            emulator: true,
            emulatorId: "pixel-emu",
            ephemeral: true
        )
    }

    private func makeContext(
        named name: String,
        devices: [Device]? = nil
    ) async throws -> (
        root: URL,
        project: URL,
        viewModel: WorkspaceViewModel,
        host: FlunnerMCPToolHost,
        runners: MCPRunnerMap,
        maintenance: MCPMockProjectMaintenance
    ) {
        let devices = devices ?? [iosDevice]
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Flunner\(name)-\(UUID().uuidString)", isDirectory: true)
        let project = try makeFlutterProject(named: name, under: root)
        let daemon = FlutterDaemon()
        let runners = MCPRunnerMap()
        let maintenance = MCPMockProjectMaintenance()
        let viewModel = WorkspaceViewModel(
            store: WorkspaceStore(directoryURL: root.appendingPathComponent("Data", isDirectory: true)),
            daemon: daemon,
            projectMaintenance: maintenance,
            startDaemon: false,
            restoreLastProject: false,
            runnerFactory: { projectPath, deviceID in
                let runner = MCPMockFlutterRunner(projectPath: projectPath, deviceId: deviceID)
                runners.runners[deviceID] = runner
                return runner
            }
        )
        daemon.devices = devices
        for _ in 0..<10 where viewModel.devices.count < devices.count {
            await Task.yield()
        }
        XCTAssertEqual(Set(viewModel.devices.map(\.id)), Set(devices.map(\.id)))

        try viewModel.openProject(at: project.path)
        let host = FlunnerMCPToolHost(viewModel: viewModel, sourceControl: SourceControlViewModel())
        return (root, project, viewModel, host, runners, maintenance)
    }

    private func makeFlutterProject(named name: String, under root: URL) throws -> URL {
        let project = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try "name: \(name.lowercased())\nflutter:\n".write(
            to: project.appendingPathComponent("pubspec.yaml"),
            atomically: true,
            encoding: .utf8
        )
        return project.resolvingSymlinksInPath()
    }
}

@MainActor
private final class MCPRunnerMap {
    var runners: [String: MCPMockFlutterRunner] = [:]
}

@MainActor
private final class MCPMockFlutterRunner: FlutterRunner {
    private(set) var stopCount = 0

    override func start(with launchConfig: LaunchConfig? = nil) {
        appState = .starting
        appState = .running
        status = "App running"
        onLogOutput?("Mock app running", .info)
    }

    override func stop() {
        stopCount += 1
        appState = .idle
        status = "App stopped"
        onCompletion?(.stoppedByUser)
    }
}

@MainActor
private final class MCPMockProjectMaintenance: FlutterProjectMaintaining {
    private(set) var operations: [FlutterProjectMaintenanceOperation] = []
    private var completion: ((FlutterProjectMaintenanceOutcome) -> Void)?

    func run(
        _ operation: FlutterProjectMaintenanceOperation,
        projectPath _: String,
        onOutput: @escaping (String, LogEntryType) -> Void,
        completion: @escaping (FlutterProjectMaintenanceOutcome) -> Void
    ) -> Bool {
        operations.append(operation)
        self.completion = completion
        onOutput(operation.displayName, .command)
        return true
    }

    func finish(_ outcome: FlutterProjectMaintenanceOutcome) {
        let completion = completion
        self.completion = nil
        completion?(outcome)
    }
}
