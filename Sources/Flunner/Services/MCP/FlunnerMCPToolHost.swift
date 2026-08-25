import Foundation
import MCP

final class FlunnerMCPToolHost: @unchecked Sendable {
    private let viewModel: WorkspaceViewModel
    private let sourceControl: SourceControlViewModel

    init(viewModel: WorkspaceViewModel, sourceControl: SourceControlViewModel) {
        self.viewModel = viewModel
        self.sourceControl = sourceControl
    }

    func call(name: String, arguments: FlunnerMCPArguments) async -> FlunnerMCPToolResult {
        await Task { @MainActor in
            await self.dispatch(name: name, arguments: arguments)
        }.value
    }

    @MainActor
    private func dispatch(name: String, arguments: FlunnerMCPArguments) async -> FlunnerMCPToolResult {
        do {
            switch name {
            case "get_status": return getStatus()
            case "list_projects": return listProjects()
            case "open_project": return try openProject(arguments)
            case "select_project": return try selectProject(arguments)
            case "remove_recent_project": return try removeRecentProject(arguments)
            case "list_devices": return listDevices()
            case "select_device": return try selectDevice(arguments)
            case "select_configuration": return try selectConfiguration(arguments)
            case "refresh_devices": return refreshDevices()
            case "list_emulators": return listEmulators()
            case "launch_emulator": return try launchEmulator(arguments)
            case "kill_emulator": return try killEmulator(arguments)
            case "kill_all_emulators": return killAllEmulators()
            case "open_ios_simulator": return openiOSSimulator()
            case "list_sessions": return listSessions()
            case "select_session": return try selectSession(arguments)
            case "run": return runApp()
            case "stop": return stopApp()
            case "hot_reload": return hotReload()
            case "hot_restart": return hotRestart()
            case "get_logs": return getLogs(arguments)
            case "clear_logs": return clearLogs()
            case "select_log_channel": return try selectLogChannel(arguments)
            case "pub_get": return pubGet()
            case "clean_and_pub_get": return cleanAndPubGet()
            case "get_sdk_info": return getSDKInfo()
            case "open_devtools": return try openDevTools(arguments)
            case "open_widget_previewer": return openWidgetPreviewer()
            case "run_flutter_command": return try runFlutterCommand(arguments)
            case "restart_daemon": return restartDaemon()
            case "get_terminal": return getTerminal()
            case "toggle_terminal": return toggleTerminal()
            case "send_terminal_text": return try sendTerminalText(arguments)
            case "add_terminal_tab": return addTerminalTab()
            case "git_status": return gitStatus()
            case "git_diff": return try await gitDiff(arguments)
            case "git_stage": return try await gitStage(arguments)
            case "git_unstage": return try await gitUnstage(arguments)
            case "git_stage_all": return try await gitStageAll()
            case "git_commit": return try await gitCommit(arguments)
            case "git_fetch": return try await gitFetch()
            case "git_pull": return try await gitPull()
            case "git_push": return try await gitPush()
            case "git_branches": return gitBranches()
            case "git_switch_branch": return try await gitSwitchBranch(arguments)
            case "git_create_branch": return try await gitCreateBranch(arguments)
            case "git_discard": return try await gitDiscard(arguments)
            case "git_delete_branch": return try await gitDeleteBranch(arguments)
            case "git_merge": return try await gitMerge(arguments)
            case "git_rebase": return try await gitRebase(arguments)
            default:
                return .error("Unknown tool: \(name)")
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    @MainActor
    private func getStatus() -> FlunnerMCPToolResult {
        let sdk = viewModel.sdkInfoService.sdkInfo.map {
            FlunnerMCPStatusPayload.SDKPayload(
                flutterPath: $0.flutterPath,
                flutterVersion: $0.flutterVersion,
                channel: $0.channel,
                dartVersion: $0.dartVersion
            )
        }
        let payload = FlunnerMCPStatusPayload(
            projectPath: viewModel.projectPath,
            projectName: viewModel.projectName,
            status: viewModel.status,
            daemon: viewModel.daemonState.mcpName,
            selectedDeviceId: viewModel.selectedDeviceId,
            selectedLaunchConfigName: viewModel.selectedLaunchConfigName,
            selectedLogChannel: viewModel.selectedLogChannel.rawValue,
            selectedLiveRunID: viewModel.selectedLiveRunID?.uuidString,
            canRun: viewModel.canRun,
            canStop: viewModel.canStopSelectedRun,
            canHotReload: viewModel.canControlSelectedRun,
            canPubGet: viewModel.canPubGet,
            canCleanAndPubGet: viewModel.canCleanAndPubGet,
            isAppRunning: viewModel.isAppRunning,
            runBlockReason: viewModel.runBlockReason,
            pubGetBlockReason: viewModel.pubGetBlockReason,
            cleanAndPubGetBlockReason: viewModel.cleanAndPubGetBlockReason,
            devices: viewModel.devices.map { devicePayload($0) },
            emulators: viewModel.emulators.map {
                devicePayload($0, isRunning: viewModel.isEmulatorRunning($0))
            },
            launchConfigs: viewModel.launchConfigs.map {
                .init(name: $0.name, displayName: $0.displayName, flutterMode: $0.flutterMode)
            },
            liveRuns: viewModel.liveRuns.map(runPayload),
            sdk: sdk
        )
        return .ok(payload)
    }

    @MainActor
    private func listProjects() -> FlunnerMCPToolResult {
        .ok(viewModel.recentProjects.map {
            [
                "path": $0.path,
                "displayName": $0.displayName,
                "lastDeviceId": $0.lastDeviceId ?? "",
                "lastConfigurationName": $0.lastConfigurationName ?? "",
            ]
        })
    }

    @MainActor
    private func openProject(_ arguments: FlunnerMCPArguments) throws -> FlunnerMCPToolResult {
        let path = try arguments.requireString("path")
        try viewModel.openProject(at: path)
        sourceControl.setProjectPath(viewModel.projectPath)
        return .ok(["opened": viewModel.projectPath ?? path])
    }

    @MainActor
    private func selectProject(_ arguments: FlunnerMCPArguments) throws -> FlunnerMCPToolResult {
        let path = try arguments.requireString("path")
        viewModel.selectWorkspace(.project(path))
        sourceControl.setProjectPath(viewModel.projectPath)
        return .ok(["selected": viewModel.projectPath ?? path])
    }

    @MainActor
    private func removeRecentProject(_ arguments: FlunnerMCPArguments) throws -> FlunnerMCPToolResult {
        let path = try arguments.requireString("path")
        guard let project = viewModel.recentProjects.first(where: {
            $0.path == path || $0.path.hasSuffix("/\(path)")
        }) else {
            return .error("Project not found in recents: \(path)")
        }
        if viewModel.isProjectRunning(project.path) {
            return .error("Stop \(project.displayName) before removing it from recents.")
        }
        viewModel.removeRecentProject(project)
        return .ok(["removed": project.path])
    }

    @MainActor
    private func listDevices() -> FlunnerMCPToolResult {
        .ok(viewModel.devices.map { devicePayload($0) })
    }

    @MainActor
    private func selectDevice(_ arguments: FlunnerMCPArguments) throws -> FlunnerMCPToolResult {
        let id = try arguments.requireString("id")
        guard viewModel.devices.contains(where: { $0.id == id }) else {
            return .error("Unknown device: \(id)")
        }
        viewModel.selectDevice(id)
        return .ok(["selectedDeviceId": id])
    }

    @MainActor
    private func selectConfiguration(_ arguments: FlunnerMCPArguments) throws -> FlunnerMCPToolResult {
        let name = try arguments.requireString("name")
        guard viewModel.launchConfigs.contains(where: { $0.name == name || $0.displayName == name }) else {
            return .error("Unknown configuration: \(name)")
        }
        let resolved = viewModel.launchConfigs.first { $0.name == name || $0.displayName == name }?.name
        viewModel.selectConfiguration(resolved)
        return .ok(["selectedLaunchConfigName": resolved ?? name])
    }

    @MainActor
    private func refreshDevices() -> FlunnerMCPToolResult {
        viewModel.refreshDevices()
        viewModel.refreshEmulators()
        return .ok("Refreshing devices and emulators.")
    }

    @MainActor
    private func listEmulators() -> FlunnerMCPToolResult {
        .ok(viewModel.emulators.map {
            devicePayload($0, isRunning: viewModel.isEmulatorRunning($0))
        })
    }

    @MainActor
    private func launchEmulator(_ arguments: FlunnerMCPArguments) throws -> FlunnerMCPToolResult {
        let id = try arguments.requireString("id")
        guard let device = emulator(matching: id) else {
            return .error("Unknown emulator: \(id)")
        }
        viewModel.launchEmulator(device)
        return .ok(["launched": device.displayName])
    }

    @MainActor
    private func killEmulator(_ arguments: FlunnerMCPArguments) throws -> FlunnerMCPToolResult {
        let id = try arguments.requireString("id")
        guard let device = emulator(matching: id) else {
            return .error("Unknown emulator: \(id)")
        }
        viewModel.killEmulator(device)
        return .ok(["killed": device.displayName])
    }

    @MainActor
    private func killAllEmulators() -> FlunnerMCPToolResult {
        viewModel.killAllEmulators()
        return .ok("Killing all simulators and emulators.")
    }

    @MainActor
    private func openiOSSimulator() -> FlunnerMCPToolResult {
        viewModel.openiOSSimulator()
        return .ok("Opening the iOS Simulator.")
    }

    @MainActor
    private func listSessions() -> FlunnerMCPToolResult {
        .ok(viewModel.liveRuns.map(runPayload))
    }

    @MainActor
    private func selectSession(_ arguments: FlunnerMCPArguments) throws -> FlunnerMCPToolResult {
        let id = try arguments.requireString("id")
        guard let uuid = UUID(uuidString: id),
              viewModel.liveRuns.contains(where: { $0.id == uuid }) else {
            return .error("Unknown session: \(id)")
        }
        viewModel.selectLiveRun(uuid)
        sourceControl.setProjectPath(viewModel.projectPath)
        return .ok([
            "selectedLiveRunID": viewModel.selectedLiveRunID?.uuidString ?? id,
            "selectedDeviceId": viewModel.selectedDeviceId ?? "",
            "selectedLaunchConfigName": viewModel.selectedLaunchConfigName ?? "",
        ])
    }

    @MainActor
    private func runApp() -> FlunnerMCPToolResult {
        guard viewModel.canRun else { return .blocked(viewModel.runBlockReason) }
        viewModel.runApp()
        return .ok("Started a run on \(viewModel.selectedDevice?.displayName ?? "the selected device").")
    }

    @MainActor
    private func stopApp() -> FlunnerMCPToolResult {
        guard viewModel.canStopSelectedRun else {
            return .error("No running session is selected.")
        }
        viewModel.stopApp()
        return .ok("Stopping the selected session.")
    }

    @MainActor
    private func hotReload() -> FlunnerMCPToolResult {
        guard viewModel.canControlSelectedRun else {
            return .error("Hot reload is not available for the selected session.")
        }
        viewModel.hotReload()
        return .ok("Hot reload sent.")
    }

    @MainActor
    private func hotRestart() -> FlunnerMCPToolResult {
        guard viewModel.canControlSelectedRun else {
            return .error("Hot restart is not available for the selected session.")
        }
        viewModel.hotRestart()
        return .ok("Hot restart sent.")
    }

    @MainActor
    private func getLogs(_ arguments: FlunnerMCPArguments) -> FlunnerMCPToolResult {
        if let channelName = arguments.string("channel") {
            guard let channel = LogChannel(rawValue: channelName) else {
                return .error("Unknown log channel: \(channelName). Use console or output.")
            }
            viewModel.selectLogChannel(channel)
        }
        let query = arguments.string("query") ?? viewModel.searchText
        let typeNames = arguments.strings("types")
        let types: Set<LogEntryType> = typeNames.isEmpty
            ? viewModel.enabledLogTypes
            : Set(typeNames.compactMap(LogEntryType.init(rawValue:)))
        let entries = ConsoleLogTools.filter(
            viewModel.logLines,
            query: query,
            enabledTypes: types,
            requiresFlutterTag: viewModel.selectedLogChannel == .console && viewModel.isFlutterConsoleFilterEnabled
        )
        let limit = max(1, arguments.int("limit") ?? 200)
        let sliced = Array(entries.suffix(limit))
        return .ok([
            "channel": viewModel.selectedLogChannel.rawValue,
            "count": "\(sliced.count)",
            "text": ConsoleLogTools.exportText(sliced),
        ])
    }

    @MainActor
    private func clearLogs() -> FlunnerMCPToolResult {
        viewModel.clearLogs()
        return .ok("Cleared \(viewModel.selectedLogChannel.label) logs for the selected device.")
    }

    @MainActor
    private func selectLogChannel(_ arguments: FlunnerMCPArguments) throws -> FlunnerMCPToolResult {
        let name = try arguments.requireString("channel")
        guard let channel = LogChannel(rawValue: name) else {
            return .error("Unknown log channel: \(name). Use console or output.")
        }
        viewModel.selectLogChannel(channel)
        return .ok(["selectedLogChannel": channel.rawValue])
    }

    @MainActor
    private func pubGet() -> FlunnerMCPToolResult {
        guard viewModel.canPubGet else { return .blocked(viewModel.pubGetBlockReason) }
        viewModel.pubGet()
        return .ok("Pub Get started.")
    }

    @MainActor
    private func cleanAndPubGet() -> FlunnerMCPToolResult {
        guard viewModel.canCleanAndPubGet else { return .blocked(viewModel.cleanAndPubGetBlockReason) }
        viewModel.cleanAndPubGet()
        return .ok("Clean + Pub Get started.")
    }

    @MainActor
    private func getSDKInfo() -> FlunnerMCPToolResult {
        guard let info = viewModel.sdkInfoService.sdkInfo else {
            if let error = viewModel.sdkInfoService.errorMessage {
                return .error(error)
            }
            return .ok("SDK info is still loading.")
        }
        return .ok([
            "flutterPath": info.flutterPath,
            "flutterVersion": info.flutterVersion,
            "channel": info.channel,
            "dartVersion": info.dartVersion,
            "engineRevision": info.engineRevision ?? "",
            "frameworkRevision": info.frameworkRevision ?? "",
        ])
    }

    @MainActor
    private func openDevTools(_ arguments: FlunnerMCPArguments) throws -> FlunnerMCPToolResult {
        guard viewModel.isDevToolsAvailable else {
            return .error("DevTools is unavailable until a session exposes a VM service URI.")
        }
        if let pageName = arguments.string("page") {
            guard let page = DevToolsPage(rawValue: pageName) else {
                return .error("Unknown DevTools page: \(pageName).")
            }
            viewModel.openDevTools(page: page)
            return .ok(["opened": page.label])
        }
        viewModel.openDevTools()
        return .ok("Opened DevTools.")
    }

    @MainActor
    private func openWidgetPreviewer() -> FlunnerMCPToolResult {
        guard viewModel.isWidgetPreviewerAvailable else {
            return .error("Open a Flutter project first.")
        }
        viewModel.openWidgetPreviewer()
        return .ok("Opened the widget previewer.")
    }

    @MainActor
    private func runFlutterCommand(_ arguments: FlunnerMCPArguments) throws -> FlunnerMCPToolResult {
        let name = try arguments.requireString("name")
        let commands = FlutterCLICommand.groups.flatMap(\.commands)
        guard let command = commands.first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            return .error("Unknown Flutter command: \(name).")
        }
        viewModel.runFlutterCommand(command)
        return .ok(["sent": command.name])
    }

    @MainActor
    private func restartDaemon() -> FlunnerMCPToolResult {
        viewModel.restartDaemon()
        return .ok("Restarting the Flutter daemon.")
    }

    @MainActor
    private func getTerminal() -> FlunnerMCPToolResult {
        guard let path = viewModel.projectPath else {
            return .error("Open a Flutter project first.")
        }
        let snapshot = viewModel.terminalWorkspaces.snapshot(for: path)
        return .ok([
            "visible": snapshot.isVisible ? "true" : "false",
            "selectedTabID": snapshot.selectedTabID?.uuidString ?? "",
            "tabs": snapshot.tabs.map { "\($0.id.uuidString):\($0.title)" }.joined(separator: ", "),
        ])
    }

    @MainActor
    private func toggleTerminal() -> FlunnerMCPToolResult {
        guard viewModel.isTerminalAvailable else {
            return .error("Open a Flutter project first.")
        }
        viewModel.toggleTerminal()
        let visible = viewModel.terminalWorkspaces.isVisible(for: viewModel.projectPath)
        return .ok(["visible": visible ? "true" : "false"])
    }

    @MainActor
    private func sendTerminalText(_ arguments: FlunnerMCPArguments) throws -> FlunnerMCPToolResult {
        guard let path = viewModel.projectPath else {
            return .error("Open a Flutter project first.")
        }
        let text = try arguments.requireString("text")
        viewModel.terminalWorkspaces.sendText(text, in: path)
        return .ok("Sent text to the active terminal tab.")
    }

    @MainActor
    private func addTerminalTab() -> FlunnerMCPToolResult {
        guard let path = viewModel.projectPath else {
            return .error("Open a Flutter project first.")
        }
        viewModel.terminalWorkspaces.addTab(to: path)
        return .ok("Added a terminal tab.")
    }

    @MainActor
    private func gitStatus() -> FlunnerMCPToolResult {
        guard let snapshot = sourceControl.snapshot else {
            return .error(sourceControl.isRepositoryMissing
                ? "This project is not a Git repository."
                : "Source control has not loaded a repository yet.")
        }
        return .ok([
            "branch": snapshot.branch,
            "upstream": snapshot.upstream ?? "",
            "ahead": "\(snapshot.ahead)",
            "behind": "\(snapshot.behind)",
            "operation": snapshot.operation?.rawValue ?? "",
            "files": snapshot.files.map {
                "\($0.kind.abbreviation) \($0.path)"
            }.joined(separator: "\n"),
        ])
    }

    @MainActor
    private func gitDiff(_ arguments: FlunnerMCPArguments) async throws -> FlunnerMCPToolResult {
        let path = try arguments.requireString("path")
        let staged = arguments.bool("staged") ?? false
        let diff = try await sourceControl.diffForMCP(path: path, staged: staged)
        return .ok([
            "title": diff.title,
            "isBinary": diff.isBinary ? "true" : "false",
            "isTruncated": diff.isTruncated ? "true" : "false",
            "text": diff.lines.map(\.text).joined(separator: "\n"),
        ])
    }

    @MainActor
    private func gitStage(_ arguments: FlunnerMCPArguments) async throws -> FlunnerMCPToolResult {
        let paths = arguments.strings("paths")
        guard !paths.isEmpty else { return .error("Provide one or more paths.") }
        try await sourceControl.stageForMCP(paths: paths)
        return .ok(["staged": paths.joined(separator: ", ")])
    }

    @MainActor
    private func gitUnstage(_ arguments: FlunnerMCPArguments) async throws -> FlunnerMCPToolResult {
        let paths = arguments.strings("paths")
        guard !paths.isEmpty else { return .error("Provide one or more paths.") }
        try await sourceControl.unstageForMCP(paths: paths)
        return .ok(["unstaged": paths.joined(separator: ", ")])
    }

    @MainActor
    private func gitStageAll() async throws -> FlunnerMCPToolResult {
        try await sourceControl.stageAllForMCP()
        return .ok("Staged all changes.")
    }

    @MainActor
    private func gitCommit(_ arguments: FlunnerMCPArguments) async throws -> FlunnerMCPToolResult {
        let message = try arguments.requireString("message")
        try await sourceControl.commitForMCP(message: message)
        return .ok("Created commit.")
    }

    @MainActor
    private func gitFetch() async throws -> FlunnerMCPToolResult {
        try await sourceControl.fetchForMCP()
        return .ok("Fetched remotes.")
    }

    @MainActor
    private func gitPull() async throws -> FlunnerMCPToolResult {
        try await sourceControl.pullForMCP()
        return .ok("Pulled changes.")
    }

    @MainActor
    private func gitPush() async throws -> FlunnerMCPToolResult {
        try await sourceControl.pushForMCP()
        return .ok("Pushed changes.")
    }

    @MainActor
    private func gitBranches() -> FlunnerMCPToolResult {
        .ok(sourceControl.branches.map {
            [
                "name": $0.name,
                "fullName": $0.fullName,
                "isCurrent": $0.isCurrent ? "true" : "false",
                "isRemote": $0.isRemote ? "true" : "false",
            ]
        })
    }

    @MainActor
    private func gitSwitchBranch(_ arguments: FlunnerMCPArguments) async throws -> FlunnerMCPToolResult {
        let name = try arguments.requireString("name")
        try await sourceControl.switchBranchForMCP(name)
        return .ok(["switched": name])
    }

    @MainActor
    private func gitCreateBranch(_ arguments: FlunnerMCPArguments) async throws -> FlunnerMCPToolResult {
        let name = try arguments.requireString("name")
        try await sourceControl.createBranchForMCP(name, startPoint: arguments.string("startPoint"))
        return .ok(["created": name])
    }

    @MainActor
    private func gitDiscard(_ arguments: FlunnerMCPArguments) async throws -> FlunnerMCPToolResult {
        try requireConfirm(arguments)
        let paths = arguments.strings("paths")
        guard !paths.isEmpty else { return .error("Provide one or more paths.") }
        try await sourceControl.discardForMCP(paths: paths)
        return .ok(["discarded": paths.joined(separator: ", ")])
    }

    @MainActor
    private func gitDeleteBranch(_ arguments: FlunnerMCPArguments) async throws -> FlunnerMCPToolResult {
        try requireConfirm(arguments)
        let name = try arguments.requireString("name")
        try await sourceControl.deleteBranchForMCP(name)
        return .ok(["deleted": name])
    }

    @MainActor
    private func gitMerge(_ arguments: FlunnerMCPArguments) async throws -> FlunnerMCPToolResult {
        try requireConfirm(arguments)
        let name = try arguments.requireString("name")
        try await sourceControl.mergeForMCP(name)
        return .ok(["merged": name])
    }

    @MainActor
    private func gitRebase(_ arguments: FlunnerMCPArguments) async throws -> FlunnerMCPToolResult {
        try requireConfirm(arguments)
        let name = try arguments.requireString("name")
        try await sourceControl.rebaseForMCP(name)
        return .ok(["rebasedOnto": name])
    }

    private func requireConfirm(_ arguments: FlunnerMCPArguments) throws {
        guard arguments.bool("confirm") == true else {
            throw SourceControlViewModel.ActionError.confirmationRequired
        }
    }

    @MainActor
    private func emulator(matching id: String) -> Device? {
        viewModel.emulators.first {
            $0.id == id || $0.emulatorId == id || $0.name == id
        }
    }

    @MainActor
    private func devicePayload(_ device: Device, isRunning: Bool? = nil) -> FlunnerMCPStatusPayload.DevicePayload {
        .init(
            id: device.id,
            name: device.name,
            displayName: device.displayName,
            platform: device.platform,
            emulator: device.emulator,
            emulatorId: device.emulatorId,
            isRunning: isRunning
        )
    }

    @MainActor
    private func runPayload(_ run: LiveRun) -> FlunnerMCPStatusPayload.RunPayload {
        .init(
            id: run.id.uuidString,
            projectPath: run.projectPath,
            projectName: run.projectName,
            deviceId: run.deviceId,
            deviceName: run.deviceName,
            configurationName: run.configurationName,
            state: run.state.mcpName,
            startedAt: ISO8601DateFormatter().string(from: run.startedAt)
        )
    }
}

enum FlunnerMCPToolCatalog {
    static let tools: [Tool] = [
        FlunnerMCPSchema.tool("get_status", description: "Snapshot of the live Flunner workbench: project, devices, sessions, and capability flags.", readOnly: true),
        FlunnerMCPSchema.tool("list_projects", description: "List recent Flutter projects.", readOnly: true),
        FlunnerMCPSchema.tool("open_project", description: "Open a Flutter project by filesystem path.", properties: ["path": FlunnerMCPSchema.string("Absolute project path")], required: ["path"]),
        FlunnerMCPSchema.tool("select_project", description: "Switch the workbench to an already-known project path.", properties: ["path": FlunnerMCPSchema.string("Project path")], required: ["path"]),
        FlunnerMCPSchema.tool("remove_recent_project", description: "Remove a project from recents. Blocked while that project has a live session.", properties: ["path": FlunnerMCPSchema.string("Project path")], required: ["path"], destructive: true),
        FlunnerMCPSchema.tool("list_devices", description: "List connected Flutter devices.", readOnly: true),
        FlunnerMCPSchema.tool("select_device", description: "Select the target device for Run, logs, and controls.", properties: ["id": FlunnerMCPSchema.string("Device id")], required: ["id"]),
        FlunnerMCPSchema.tool("select_configuration", description: "Select a launch configuration by name.", properties: ["name": FlunnerMCPSchema.string("Launch configuration name")], required: ["name"]),
        FlunnerMCPSchema.tool("refresh_devices", description: "Refresh connected devices and emulator lists."),
        FlunnerMCPSchema.tool("list_emulators", description: "List iOS and Android emulators.", readOnly: true),
        FlunnerMCPSchema.tool("launch_emulator", description: "Launch an emulator by id, emulatorId, or name.", properties: ["id": FlunnerMCPSchema.string("Emulator id")], required: ["id"]),
        FlunnerMCPSchema.tool("kill_emulator", description: "Kill a running emulator.", properties: ["id": FlunnerMCPSchema.string("Emulator id")], required: ["id"], destructive: true),
        FlunnerMCPSchema.tool("kill_all_emulators", description: "Kill all running simulators and emulators.", destructive: true),
        FlunnerMCPSchema.tool("open_ios_simulator", description: "Open the iOS Simulator app."),
        FlunnerMCPSchema.tool("list_sessions", description: "List live run sessions.", readOnly: true),
        FlunnerMCPSchema.tool("select_session", description: "Jump to a live session, restoring its project, device, and launch config.", properties: ["id": FlunnerMCPSchema.string("Session UUID")], required: ["id"]),
        FlunnerMCPSchema.tool("run", description: "Run the current project on the selected device."),
        FlunnerMCPSchema.tool("stop", description: "Stop the selected live session."),
        FlunnerMCPSchema.tool("hot_reload", description: "Hot reload the selected running session."),
        FlunnerMCPSchema.tool("hot_restart", description: "Hot restart the selected running session."),
        FlunnerMCPSchema.tool(
            "get_logs",
            description: "Read console or output logs for the selected device.",
            properties: [
                "channel": FlunnerMCPSchema.string("console or output"),
                "limit": FlunnerMCPSchema.integer("Maximum lines to return, default 200"),
                "query": FlunnerMCPSchema.string("Case-insensitive search"),
                "types": FlunnerMCPSchema.strings("Log types: info, error, command"),
            ],
            readOnly: true
        ),
        FlunnerMCPSchema.tool("clear_logs", description: "Clear the selected log channel for the selected device.", destructive: true),
        FlunnerMCPSchema.tool("select_log_channel", description: "Show console or output logs.", properties: ["channel": FlunnerMCPSchema.string("console or output")], required: ["channel"]),
        FlunnerMCPSchema.tool("pub_get", description: "Run flutter pub get. Allowed while sessions are running."),
        FlunnerMCPSchema.tool("clean_and_pub_get", description: "Run flutter clean then pub get. Blocked while any session is running.", destructive: true),
        FlunnerMCPSchema.tool("get_sdk_info", description: "Return Flutter SDK path and version info.", readOnly: true),
        FlunnerMCPSchema.tool("open_devtools", description: "Open Flutter DevTools, optionally on a page.", properties: ["page": FlunnerMCPSchema.string("inspector, performance, cpuProfiler, memory, network, appSize, deepLinks")]),
        FlunnerMCPSchema.tool("open_widget_previewer", description: "Open the Flutter widget previewer."),
        FlunnerMCPSchema.tool("run_flutter_command", description: "Send a named Flutter CLI command to the integrated terminal.", properties: ["name": FlunnerMCPSchema.string("Command display name, e.g. Analyze or Build APK")], required: ["name"]),
        FlunnerMCPSchema.tool("restart_daemon", description: "Restart the Flutter daemon."),
        FlunnerMCPSchema.tool("get_terminal", description: "Inspect the integrated terminal for the current project.", readOnly: true),
        FlunnerMCPSchema.tool("toggle_terminal", description: "Show or hide the integrated terminal."),
        FlunnerMCPSchema.tool("send_terminal_text", description: "Type text into the active terminal tab and press return.", properties: ["text": FlunnerMCPSchema.string("Command or text to send")], required: ["text"]),
        FlunnerMCPSchema.tool("add_terminal_tab", description: "Open a new terminal tab for the current project."),
        FlunnerMCPSchema.tool("git_status", description: "Show branch, ahead/behind, and changed files.", readOnly: true),
        FlunnerMCPSchema.tool(
            "git_diff",
            description: "Show the diff for a path.",
            properties: [
                "path": FlunnerMCPSchema.string("Repository-relative path"),
                "staged": FlunnerMCPSchema.bool("If true, show the staged diff"),
            ],
            required: ["path"],
            readOnly: true
        ),
        FlunnerMCPSchema.tool("git_stage", description: "Stage paths.", properties: ["paths": FlunnerMCPSchema.strings("Repository-relative paths")], required: ["paths"]),
        FlunnerMCPSchema.tool("git_unstage", description: "Unstage paths.", properties: ["paths": FlunnerMCPSchema.strings("Repository-relative paths")], required: ["paths"]),
        FlunnerMCPSchema.tool("git_stage_all", description: "Stage all working tree changes."),
        FlunnerMCPSchema.tool("git_commit", description: "Commit staged changes.", properties: ["message": FlunnerMCPSchema.string("Commit message")], required: ["message"]),
        FlunnerMCPSchema.tool("git_fetch", description: "Fetch remotes."),
        FlunnerMCPSchema.tool("git_pull", description: "Pull the current branch."),
        FlunnerMCPSchema.tool("git_push", description: "Push the current branch."),
        FlunnerMCPSchema.tool("git_branches", description: "List local and remote branches.", readOnly: true),
        FlunnerMCPSchema.tool("git_switch_branch", description: "Switch to a branch.", properties: ["name": FlunnerMCPSchema.string("Branch name")], required: ["name"]),
        FlunnerMCPSchema.tool(
            "git_create_branch",
            description: "Create a branch.",
            properties: [
                "name": FlunnerMCPSchema.string("New branch name"),
                "startPoint": FlunnerMCPSchema.string("Optional start point"),
            ],
            required: ["name"]
        ),
        FlunnerMCPSchema.tool(
            "git_discard",
            description: "Discard working tree changes. Requires confirm=true.",
            properties: [
                "paths": FlunnerMCPSchema.strings("Repository-relative paths"),
                "confirm": FlunnerMCPSchema.bool("Must be true"),
            ],
            required: ["paths", "confirm"],
            destructive: true
        ),
        FlunnerMCPSchema.tool(
            "git_delete_branch",
            description: "Delete a local branch. Requires confirm=true.",
            properties: [
                "name": FlunnerMCPSchema.string("Branch name"),
                "confirm": FlunnerMCPSchema.bool("Must be true"),
            ],
            required: ["name", "confirm"],
            destructive: true
        ),
        FlunnerMCPSchema.tool(
            "git_merge",
            description: "Merge a branch into the current branch. Requires confirm=true.",
            properties: [
                "name": FlunnerMCPSchema.string("Branch name"),
                "confirm": FlunnerMCPSchema.bool("Must be true"),
            ],
            required: ["name", "confirm"],
            destructive: true
        ),
        FlunnerMCPSchema.tool(
            "git_rebase",
            description: "Rebase the current branch onto another. Requires confirm=true.",
            properties: [
                "name": FlunnerMCPSchema.string("Upstream branch name"),
                "confirm": FlunnerMCPSchema.bool("Must be true"),
            ],
            required: ["name", "confirm"],
            destructive: true
        ),
    ]

    static func register(on server: Server, host: FlunnerMCPToolHost) async {
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: tools)
        }
        await server.withMethodHandler(CallTool.self) { params in
            let result = await host.call(name: params.name, arguments: FlunnerMCPArguments(params.arguments))
            return .init(
                content: [.text(text: result.text, annotations: nil, _meta: nil)],
                isError: result.isError
            )
        }
    }
}
