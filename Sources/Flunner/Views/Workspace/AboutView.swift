import AppKit
import SwiftUI

struct AboutView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    let onDismiss: () -> Void

    @State private var hasCopiedDiagnostics = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var architectureString: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        return "Intel (x86_64)"
        #else
        return "Universal"
        #endif
    }

    private var macOSVersionString: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider()

            ScrollView {
                VStack(spacing: WorkbenchSpacing.large) {
                    heroSection
                    
                    creatorCard
                    
                    linksGrid
                    
                    systemDiagnosticsCard
                    
                    legalCard
                }
                .padding(WorkbenchSpacing.large)
            }
        }
        .frame(width: 520, height: 710)
        .background(WorkbenchColor.background)
        .tint(WorkbenchColor.accent)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("About Flunner")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close About Dialog")
        }
        .padding(.horizontal, WorkbenchSpacing.large)
        .padding(.vertical, WorkbenchSpacing.compact)
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: WorkbenchSpacing.small) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(WorkbenchColor.surface)
                    .frame(width: 88, height: 88)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(WorkbenchColor.accent.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 76, height: 76)
            }

            Text("Flunner")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(WorkbenchColor.textPrimary)

            HStack(spacing: WorkbenchSpacing.xs) {
                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("•")
                    .foregroundStyle(.secondary)

                Text("Build \(buildNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(WorkbenchColor.accentSoft)
            .clipShape(Capsule())

            Text("The AI-Agent Sidekick & Native macOS Workbench for Flutter.")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(WorkbenchColor.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WorkbenchSpacing.medium)

            Text("Engineered to pair alongside AI coding agents and modern editors. The in-app MCP server lets agents drive the live runtime — runs, logs, devices, git, and terminal.")
                .font(.caption)
                .foregroundStyle(WorkbenchColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, WorkbenchSpacing.large)

            Button("Connect your AI agent…") {
                NotificationCenter.default.post(name: .openAgentsSettings, object: nil)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                onDismiss()
            }
            .buttonStyle(.link)
            .workbenchFont(.caption, weight: .medium)
        }
        .padding(.top, WorkbenchSpacing.small)
    }

    // MARK: - Creator Card

    private var creatorCard: some View {
        VStack(alignment: .leading, spacing: WorkbenchSpacing.compact) {
            Label("AUTHOR & PUBLISHER", systemImage: "person.crop.circle.fill")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(WorkbenchColor.accent)

            HStack(alignment: .center, spacing: WorkbenchSpacing.compact) {
                authorAvatar

                VStack(alignment: .leading, spacing: 2) {
                    Text("Oliver Martinez")
                        .font(.headline)
                        .foregroundStyle(WorkbenchColor.textPrimary)

                    Text("Creator & Lead Developer")
                        .font(.caption)
                        .foregroundStyle(WorkbenchColor.textSecondary)
                }

                Spacer()

                HStack(spacing: WorkbenchSpacing.small) {
                    Button {
                        viewModel.openLink(URL(string: "https://x.com/oliverbytes")!)
                    } label: {
                        HStack(spacing: 4) {
                            Text("𝕏")
                                .fontWeight(.bold)
                            Text("@oliverbytes")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(WorkbenchColor.accentSoft)
                        .foregroundStyle(WorkbenchColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Follow Oliver Martinez on X (@oliverbytes)")

                    Button {
                        viewModel.openLink(URL(string: "https://github.com/oliverbytes")!)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "curlybraces")
                                .font(.system(size: 10, weight: .bold))
                            Text("GitHub")
                        }
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(WorkbenchColor.surface)
                        .foregroundStyle(WorkbenchColor.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(WorkbenchColor.divider, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("View Oliver's GitHub profile")
                }
            }
            .padding(WorkbenchSpacing.medium)
            .background(WorkbenchColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchRadius.medium, style: .continuous)
                    .stroke(WorkbenchColor.divider, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var authorAvatar: some View {
        if let nsImage = NSImage(named: "OliverMartinez") {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(WorkbenchColor.accent.opacity(0.35), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .foregroundStyle(WorkbenchColor.accent)
        }
    }

    // MARK: - Quick Links Grid

    private var linksGrid: some View {
        VStack(alignment: .leading, spacing: WorkbenchSpacing.compact) {
            Label("COMMUNITY & LINKS", systemImage: "link")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(WorkbenchColor.accent)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: WorkbenchSpacing.small) {
                linkButton(
                    title: "GitHub Repository",
                    subtitle: "stackwares/flunner",
                    systemImage: "star.fill",
                    url: "https://github.com/stackwares/flunner"
                )

                linkButton(
                    title: "Report an Issue",
                    subtitle: "Bug reports & requests",
                    systemImage: "ladybug.fill",
                    url: "https://github.com/stackwares/flunner/issues"
                )

                linkButton(
                    title: "Release Notes",
                    subtitle: "Changelog & updates",
                    systemImage: "sparkles",
                    url: "https://github.com/stackwares/flunner/releases"
                )

                linkButton(
                    title: "Stackwares Org",
                    subtitle: "github.com/stackwares",
                    systemImage: "building.2.fill",
                    url: "https://github.com/stackwares"
                )
            }
        }
    }

    private func linkButton(title: String, subtitle: String, systemImage: String, url: String) -> some View {
        Button {
            viewModel.openLink(URL(string: url)!)
        } label: {
            HStack(spacing: WorkbenchSpacing.small) {
                Image(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(WorkbenchColor.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(WorkbenchColor.textPrimary)

                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(WorkbenchColor.textSecondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(WorkbenchColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchRadius.small, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchRadius.small, style: .continuous)
                    .stroke(WorkbenchColor.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - System Diagnostics Card

    private var systemDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: WorkbenchSpacing.compact) {
            HStack {
                Label("SYSTEM & RUNTIME", systemImage: "cpu.fill")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(WorkbenchColor.accent)

                Spacer()

                Button {
                    copyDiagnosticInfo()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: hasCopiedDiagnostics ? "checkmark" : "doc.on.doc")
                        Text(hasCopiedDiagnostics ? "Copied" : "Copy Diagnostics")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(hasCopiedDiagnostics ? WorkbenchColor.success : WorkbenchColor.accent)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 6) {
                diagnosticRow(label: "Operating System", value: macOSVersionString)
                diagnosticRow(label: "Architecture", value: architectureString)
                diagnosticRow(label: "SDK Environment", value: viewModel.sdkInfoService.sdkInfo?.flutterVersion ?? "Flutter 3.x • Dart 3.x")
            }
            .padding(WorkbenchSpacing.medium)
            .background(WorkbenchColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: WorkbenchRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WorkbenchRadius.medium, style: .continuous)
                    .stroke(WorkbenchColor.divider, lineWidth: 1)
            )
        }
    }

    private func diagnosticRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(WorkbenchColor.textSecondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(WorkbenchColor.textPrimary)
        }
    }

    private func copyDiagnosticInfo() {
        let text = """
        Flunner: \(appVersion) (\(buildNumber))
        OS: \(macOSVersionString)
        Arch: \(architectureString)
        Flutter: \(viewModel.sdkInfoService.sdkInfo?.flutterVersion ?? "N/A")
        Dart: \(viewModel.sdkInfoService.sdkInfo?.dartVersion ?? "N/A")
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        hasCopiedDiagnostics = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            hasCopiedDiagnostics = false
        }
    }

    // MARK: - Legal & Licensing

    private var legalCard: some View {
        VStack(spacing: WorkbenchSpacing.xs) {
            HStack(spacing: 6) {
                Text("Released under the MIT License")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(WorkbenchColor.textSecondary)

                Text("•")
                    .font(.caption)
                    .foregroundStyle(WorkbenchColor.textSecondary.opacity(0.5))

                Button("View License") {
                    viewModel.openLink(URL(string: "https://github.com/stackwares/flunner/blob/main/LICENSE")!)
                }
                .font(.caption)
                .buttonStyle(.link)
            }

            Text("Copyright © 2026 Stackwares. All rights reserved.")
                .font(.system(size: 11))
                .foregroundStyle(WorkbenchColor.textSecondary.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WorkbenchSpacing.small)
    }
}
