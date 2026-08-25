import SwiftUI

enum ThemeMode: String, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var next: ThemeMode {
        switch self {
        case .system: .light
        case .light: .dark
        case .dark: .system
        }
    }
}

@main
struct FlunnerApp: App {
    @StateObject private var viewModel: WorkspaceViewModel
    @StateObject private var sourceControlViewModel: SourceControlViewModel
    @StateObject private var mcpServer: FlunnerMCPServer
    @StateObject private var keyboardShortcuts = KeyboardShortcutStore()
    @AppStorage(PreferenceKeys.themeMode) private var themeMode = ThemeMode.system.rawValue
    @AppStorage(PreferenceKeys.appFontSize) private var appFontSize = AppFontSizing.defaultSize

    private var selectedTheme: ThemeMode { ThemeMode(rawValue: themeMode) ?? .system }

    init() {
        let viewModel = WorkspaceViewModel()
        let sourceControl = SourceControlViewModel()
        _viewModel = StateObject(wrappedValue: viewModel)
        _sourceControlViewModel = StateObject(wrappedValue: sourceControl)
        _mcpServer = StateObject(wrappedValue: FlunnerMCPServer(
            viewModel: viewModel,
            sourceControl: sourceControl
        ))
    }

    var body: some Scene {
        WindowGroup(id: "workspace") {
            ContentView(viewModel: viewModel, sourceControlViewModel: sourceControlViewModel)
                .frame(minWidth: 820, minHeight: 520)
                .preferredColorScheme(selectedTheme.colorScheme)
                .workbenchAppFontSize(appFontSize)
                .environmentObject(keyboardShortcuts)
                .onAppear { mcpServer.startIfEnabled() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    mcpServer.stop()
                }
        }
        .defaultSize(width: 1120, height: 1440)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Flunner") {
                    NotificationCenter.default.post(name: .showAboutSheet, object: nil)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Open Flutter Project…") {
                    viewModel.chooseProject()
                }
                .keyboardShortcut("O", modifiers: .command)
            }
            SidebarCommands()
            WorkbenchCommands(
                viewModel: viewModel,
                terminalWorkspaces: viewModel.terminalWorkspaces,
                sourceControlViewModel: sourceControlViewModel,
                keyboardShortcuts: keyboardShortcuts,
                appFontSize: $appFontSize
            )
            CommandGroup(replacing: .help) {
                Button("About Flunner") {
                    NotificationCenter.default.post(name: .showAboutSheet, object: nil)
                }
                Button("Welcome to Flunner (Onboarding)…") {
                    NotificationCenter.default.post(name: .showOnboardingSheet, object: nil)
                }
                Divider()
                Button("Flunner GitHub Repository") {
                    viewModel.openLink(URL(string: "https://github.com/stackwares/flunner")!)
                }
                Button("Flutter Documentation") {
                    viewModel.openLink(URL(string: "https://docs.flutter.dev")!)
                }
                Button("Report an Issue…") {
                    viewModel.openLink(URL(string: "https://github.com/stackwares/flunner/issues")!)
                }
            }
        }

        Settings {
            SettingsView(
                viewModel: viewModel,
                keyboardShortcuts: keyboardShortcuts,
                mcpServer: mcpServer
            )
                .preferredColorScheme(selectedTheme.colorScheme)
                .workbenchAppFontSize(appFontSize)
        }
    }
}

private struct WorkbenchCommands: Commands {
    @ObservedObject var viewModel: WorkspaceViewModel
    @ObservedObject var terminalWorkspaces: TerminalWorkspaceManager
    @ObservedObject var sourceControlViewModel: SourceControlViewModel
    @ObservedObject var keyboardShortcuts: KeyboardShortcutStore
    @Binding var appFontSize: Double

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()

            Button("Increase App Font Size") {
                appFontSize = AppFontSizing.increased(appFontSize)
            }
            .workbenchShortcut(keyboardShortcuts.binding(for: .increaseAppFontSize))
            .disabled(appFontSize >= AppFontSizing.maximumSize)

            Button("Decrease App Font Size") {
                appFontSize = AppFontSizing.decreased(appFontSize)
            }
            .workbenchShortcut(keyboardShortcuts.binding(for: .decreaseAppFontSize))
            .disabled(appFontSize <= AppFontSizing.minimumSize)
        }

        CommandMenu("Project") {
            Button("Pub Get", systemImage: "shippingbox.fill", action: viewModel.pubGet)
                .workbenchShortcut(keyboardShortcuts.binding(for: .pubGet))
                .disabled(!viewModel.canPubGet)

            Button("Clean + Pub Get…", systemImage: "eraser.fill", action: viewModel.requestCleanAndPubGet)
                .workbenchShortcut(keyboardShortcuts.binding(for: .cleanAndPubGet))
                .disabled(!viewModel.canCleanAndPubGet)
        }

        CommandMenu("Run") {
            Button("Run", systemImage: "play.fill", action: viewModel.runApp)
                .workbenchShortcut(keyboardShortcuts.binding(for: .run))
                .disabled(!viewModel.canRun)

            Button("Stop", systemImage: "stop.fill", action: viewModel.stopApp)
                .workbenchShortcut(keyboardShortcuts.binding(for: .stop))
                .disabled(!viewModel.canStopSelectedRun)

            Divider()

            Button("Hot Reload", systemImage: "bolt.fill", action: viewModel.hotReload)
                .workbenchShortcut(keyboardShortcuts.binding(for: .hotReload))
                .disabled(!viewModel.canControlSelectedRun)

            Button("Hot Restart", systemImage: "arrow.triangle.2.circlepath", action: viewModel.hotRestart)
                .workbenchShortcut(keyboardShortcuts.binding(for: .hotRestart))
                .disabled(!viewModel.canControlSelectedRun)
        }

        CommandMenu("Device") {
            Button("Open iOS Simulator", systemImage: "iphone") {
                viewModel.openiOSSimulator()
            }

            Menu(content: {
                if viewModel.androidEmulators.isEmpty {
                    Button("Refresh Emulator List") {
                        viewModel.refreshEmulators()
                    }
                }
                ForEach(viewModel.androidEmulators) { device in
                    if viewModel.isEmulatorRunning(device) {
                        Button("Kill \(device.name)") {
                            viewModel.killEmulator(device)
                        }
                    } else {
                        Button(device.name) {
                            viewModel.launchEmulator(device)
                        }
                    }
                }
            }, label: {
                Label("Open Android Emulator", systemImage: "rectangle.landscape.rotate")
            })

            if !viewModel.runningEmulators.isEmpty {
                Divider()

                Button("Kill All Simulators", systemImage: "xmark.circle") {
                    viewModel.killAllEmulators()
                }
                .workbenchShortcut(keyboardShortcuts.binding(for: .killAllSimulators))
            }
        }

        CommandMenu("Tools") {
            Button("Flutter SDK Info…", systemImage: "info.circle") {
                NotificationCenter.default.post(name: .showFlutterSDKInfo, object: nil)
            }

            Divider()

            Menu("Useful Links") {
                Button("DartPad", systemImage: "play.rectangle") {
                    viewModel.openLink(URL(string: "https://dartpad.dev")!)
                }
                Button("Pub.dev", systemImage: "shippingbox") {
                    viewModel.openLink(URL(string: "https://pub.dev")!)
                }
                Button("Flutter Docs", systemImage: "book") {
                    viewModel.openLink(URL(string: "https://docs.flutter.dev")!)
                }
                Button("Dart Docs", systemImage: "books.vertical") {
                    viewModel.openLink(URL(string: "https://dart.dev/guides")!)
                }
            }

            Divider()

            Button("Open DevTools", systemImage: "wrench.and.screwdriver") {
                viewModel.openDevTools()
            }
            .workbenchShortcut(keyboardShortcuts.binding(for: .openDevTools))
            .disabled(!viewModel.isDevToolsAvailable)

            Menu("DevTools") {
                ForEach(DevToolsPage.allCases, id: \.rawValue) { page in
                    Button(page.label, systemImage: page.systemImage) {
                        viewModel.openDevTools(page: page)
                    }
                    .disabled(!viewModel.isDevToolsAvailable)
                }
            }
            .disabled(!viewModel.isDevToolsAvailable)

            Divider()

            Button("Widget Previewer", systemImage: "square.grid.3x3") {
                viewModel.openWidgetPreviewer()
            }
            .workbenchShortcut(keyboardShortcuts.binding(for: .openWidgetPreviewer))
            .disabled(!viewModel.isWidgetPreviewerAvailable)
        }

        CommandMenu("Terminal") {
            Button(
                terminalWorkspaces.isVisible(for: viewModel.projectPath) ? "Hide Terminal" : "Show Terminal",
                systemImage: "terminal",
                action: viewModel.toggleTerminal
            )
            .workbenchShortcut(keyboardShortcuts.binding(for: .toggleTerminal))
            .disabled(!viewModel.isTerminalAvailable)
        }

        CommandMenu("Logs") {
            Button {
                viewModel.selectLogChannel(.console)
            } label: {
                Label(
                    "Show Console",
                    systemImage: viewModel.selectedLogChannel == .console ? "checkmark" : LogChannel.console.systemImage
                )
            }
            .workbenchShortcut(keyboardShortcuts.binding(for: .showConsole))

            Button {
                viewModel.selectLogChannel(.output)
            } label: {
                Label(
                    "Show Output",
                    systemImage: viewModel.selectedLogChannel == .output ? "checkmark" : LogChannel.output.systemImage
                )
            }
            .workbenchShortcut(keyboardShortcuts.binding(for: .showOutput))

            Divider()

            Button("Find in \(viewModel.selectedLogChannel.label)", systemImage: "magnifyingglass") {
                NotificationCenter.default.post(name: .focusConsoleSearch, object: nil)
            }
            .workbenchShortcut(keyboardShortcuts.binding(for: .focusConsoleSearch))

            Button("Copy Visible Output", systemImage: "doc.on.doc", action: viewModel.copyVisibleLogs)
                .workbenchShortcut(keyboardShortcuts.binding(for: .copyVisibleOutput))
                .disabled(viewModel.filteredLogs.isEmpty)

            Button("Export Visible Output…", systemImage: "square.and.arrow.up", action: viewModel.exportVisibleLogs)
                .workbenchShortcut(keyboardShortcuts.binding(for: .exportVisibleOutput))
                .disabled(viewModel.filteredLogs.isEmpty)

            Divider()

            Button("Clear \(viewModel.selectedLogChannel.label)", systemImage: "trash", action: viewModel.clearLogs)
                .workbenchShortcut(keyboardShortcuts.binding(for: .clearConsole))
                .disabled(viewModel.logLines.isEmpty)
        }

        CommandMenu("Source Control") {
            Button("Show Source Control…", systemImage: "arrow.triangle.branch") {
                NotificationCenter.default.post(name: .showSourceControlSheet, object: nil)
            }
            .workbenchShortcut(keyboardShortcuts.binding(for: .showSourceControl))

            Divider()

            Button("Stage All Changes", systemImage: "plus") {
                sourceControlViewModel.stageAll()
            }
            .workbenchShortcut(keyboardShortcuts.binding(for: .stageAllChanges))
            .disabled(!sourceControlViewModel.canStageAll)

            Button("Commit Staged Changes", systemImage: "checkmark.circle") {
                sourceControlViewModel.commit()
            }
            .workbenchShortcut(keyboardShortcuts.binding(for: .commitStagedChanges))
            .disabled(!sourceControlViewModel.canCommit)

            Divider()

            Button("Fetch", systemImage: "arrow.down.circle", action: sourceControlViewModel.fetch)
                .workbenchShortcut(keyboardShortcuts.binding(for: .fetchSourceControl))
                .disabled(sourceControlViewModel.snapshot?.remotes.isEmpty != false || sourceControlViewModel.isBusy)

            Button("Pull", systemImage: "arrow.down.to.line", action: sourceControlViewModel.pull)
                .workbenchShortcut(keyboardShortcuts.binding(for: .pullSourceControl))
                .disabled(!sourceControlViewModel.canPull)

            Button("Push", systemImage: "arrow.up.to.line", action: sourceControlViewModel.push)
                .workbenchShortcut(keyboardShortcuts.binding(for: .pushSourceControl))
                .disabled(!sourceControlViewModel.canPush)

            Button("Refresh", systemImage: "arrow.clockwise", action: sourceControlViewModel.refresh)
                .disabled(sourceControlViewModel.isBusy || sourceControlViewModel.snapshot == nil)
        }
    }
}

private extension View {
    func workbenchShortcut(_ shortcut: WorkbenchShortcut) -> some View {
        keyboardShortcut(shortcut.key.keyEquivalent, modifiers: shortcut.eventModifiers)
    }
}
