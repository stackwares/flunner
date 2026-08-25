import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @ObservedObject var keyboardShortcuts: KeyboardShortcutStore
    @ObservedObject var mcpServer: FlunnerMCPServer
    @AppStorage(PreferenceKeys.themeMode) private var themeMode = ThemeMode.system.rawValue
    @AppStorage(PreferenceKeys.appFontSize) private var appFontSize = AppFontSizing.defaultSize
    @AppStorage(PreferenceKeys.consoleFontSize) private var consoleFontSize = 12.0
    @AppStorage(PreferenceKeys.showTimestamps) private var showTimestamps = true
    @AppStorage(PreferenceKeys.followOutput) private var followOutput = true
    @AppStorage(PreferenceKeys.mcpEnabled) private var mcpEnabled = true

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var copyright: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
            ?? "Copyright © 2026 Stackwares. All rights reserved."
    }

    var body: some View {
        TabView {
            Form {
                Section {
                    HStack(spacing: WorkbenchSpacing.medium) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 56, height: 56)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Flunner")
                                .font(.headline)
                            Text("Version \(appVersion) (\(buildNumber)) • The AI-Agent Sidekick")
                                .workbenchFont(.body)
                                .foregroundStyle(WorkbenchColor.textSecondary)
                            Text("Crafted with ❤️ by Oliver Martinez (@oliverbytes)")
                                .workbenchFont(.caption)
                                .foregroundStyle(WorkbenchColor.accent)
                        }

                        Spacer()

                        Button("About & Credits…") {
                            NotificationCenter.default.post(name: .showAboutSheet, object: nil)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, WorkbenchSpacing.xs)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $themeMode) {
                        ForEach(ThemeMode.allCases, id: \.rawValue) { theme in
                            Label(theme.label, systemImage: theme.icon).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("App Font Size")
                        Slider(
                            value: $appFontSize,
                            in: AppFontSizing.minimumSize...AppFontSizing.maximumSize,
                            step: AppFontSizing.step
                        )
                        Text("\(Int(appFontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(WorkbenchColor.textSecondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                Section("Logs") {
                    HStack {
                        Text("Log Font Size")
                        Slider(value: $consoleFontSize, in: 9...20, step: 1)
                        Text("\(Int(consoleFontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(WorkbenchColor.textSecondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                    Toggle("Show timestamps", isOn: $showTimestamps)
                    Toggle("Follow new output", isOn: $followOutput)
                }

                Section {
                    Button("Restore Defaults") {
                        restoreDefaults()
                    }
                } footer: {
                    Text("Resets all General settings to their original values.")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Recent Projects") {
                    LabeledContent("Stored", value: "\(viewModel.recentProjects.count) of \(WorkspaceStore.recentProjectLimit)")
                    Button("Clear Recent Projects", role: .destructive, action: viewModel.clearRecentProjects)
                        .disabled(viewModel.recentProjects.isEmpty || viewModel.hasRunningProjects)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Data", systemImage: "internaldrive") }

            ShortcutSettingsView(keyboardShortcuts: keyboardShortcuts)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            Form {
                Section {
                    Toggle("Enable MCP Server", isOn: $mcpEnabled)
                    LabeledContent("Status", value: mcpServer.isRunning ? "Listening" : "Stopped")
                    LabeledContent("URL") {
                        Text(mcpServer.connectionURLString)
                            .textSelection(.enabled)
                            .workbenchFont(.body, design: .monospaced)
                    }
                    if let token = mcpServer.token {
                        LabeledContent("Token") {
                            Text(token)
                                .textSelection(.enabled)
                                .workbenchFont(.caption, design: .monospaced)
                                .lineLimit(1)
                        }
                    }
                    if let error = mcpServer.lastError {
                        Text(error)
                            .foregroundStyle(WorkbenchColor.error)
                            .workbenchFont(.caption)
                    }
                } footer: {
                    Text("Agents connect to Flunner over localhost while the app is running. The bearer token is regenerated each launch.")
                }

                Section("Client configuration") {
                    Text(mcpServer.cursorConfigSnippet)
                        .workbenchFont(.caption, design: .monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Copy Cursor / Claude Config") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(mcpServer.cursorConfigSnippet, forType: .string)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Agents", systemImage: "cpu") }
        }
        .frame(width: 600, height: 500)
        .workbenchAppFontSize(appFontSize)
        .tint(WorkbenchColor.accent)
    }

    private func restoreDefaults() {
        themeMode = ThemeMode.system.rawValue
        appFontSize = AppFontSizing.defaultSize
        consoleFontSize = 12
        showTimestamps = true
        followOutput = true
        mcpEnabled = true
    }
}

private struct ShortcutSettingsView: View {
    @ObservedObject var keyboardShortcuts: KeyboardShortcutStore

    var body: some View {
        Form {
            Section("Project") {
                ForEach(WorkbenchAction.projectActions) { action in
                    ShortcutRow(action: action, keyboardShortcuts: keyboardShortcuts)
                }
            }

            Section("Run") {
                ForEach(WorkbenchAction.runActions) { action in
                    ShortcutRow(action: action, keyboardShortcuts: keyboardShortcuts)
                }
            }

            Section("Logs") {
                ForEach(WorkbenchAction.logActions) { action in
                    ShortcutRow(action: action, keyboardShortcuts: keyboardShortcuts)
                }
            }

            Section("Terminal") {
                ForEach(WorkbenchAction.terminalActions) { action in
                    ShortcutRow(action: action, keyboardShortcuts: keyboardShortcuts)
                }
            }

            Section("Source Control") {
                ForEach(WorkbenchAction.sourceControlActions) { action in
                    ShortcutRow(action: action, keyboardShortcuts: keyboardShortcuts)
                }
            }

            Section("Appearance") {
                ForEach(WorkbenchAction.appearanceActions) { action in
                    ShortcutRow(action: action, keyboardShortcuts: keyboardShortcuts)
                }
            }

            Section("Tools") {
                ForEach(WorkbenchAction.toolsActions) { action in
                    ShortcutRow(action: action, keyboardShortcuts: keyboardShortcuts)
                }
            }

            if let validationMessage = keyboardShortcuts.validationMessage {
                Section {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .workbenchFont(.caption)
                        .foregroundStyle(WorkbenchColor.error)
                }
            }

            Section {
                Button("Restore Default Shortcuts", action: keyboardShortcuts.resetAll)
            } footer: {
                Text("Changes apply immediately. Shortcuts must include Command, Option, or Control and cannot be assigned to more than one action.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRow: View {
    let action: WorkbenchAction
    @ObservedObject var keyboardShortcuts: KeyboardShortcutStore

    private var shortcut: WorkbenchShortcut { keyboardShortcuts.binding(for: action) }

    var body: some View {
        LabeledContent(action.label) {
            Menu {
                Section("Modifiers") {
                    ForEach(ShortcutModifier.displayOrder) { modifier in
                        Button {
                            keyboardShortcuts.toggleModifier(modifier, for: action)
                        } label: {
                            Label(
                                modifier.label,
                                systemImage: shortcut.modifiers.contains(modifier) ? "checkmark" : "circle"
                            )
                        }
                    }
                }

                Divider()
                keyMenu("Letters", keys: ShortcutKey.letters)
                keyMenu("Numbers", keys: ShortcutKey.numbers)
                keyMenu("Symbols", keys: ShortcutKey.symbols)
                keyMenu("Special Keys", keys: ShortcutKey.special)
                Divider()
                Button("Restore \(action.label) Default") {
                    keyboardShortcuts.reset(action)
                }
            } label: {
                Text(shortcut.displayName)
                    .workbenchFont(.body, design: .monospaced)
                    .foregroundStyle(WorkbenchColor.textPrimary)
                    .frame(minWidth: 62, minHeight: 32, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("\(action.label) shortcut, \(shortcut.displayName)")
        }
    }

    private func keyMenu(_ title: String, keys: [ShortcutKey]) -> some View {
        Menu(title) {
            ForEach(keys) { key in
                Button {
                    keyboardShortcuts.setKey(key, for: action)
                } label: {
                    if shortcut.key == key {
                        Label(key.displayName, systemImage: "checkmark")
                    } else {
                        Text(key.displayName)
                    }
                }
            }
        }
    }
}
