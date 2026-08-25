import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentPage = 0
    @State private var isValidationErrorPresented = false
    let onProjectOpened: () -> Void

    private let totalPages = 4

    var body: some View {
        VStack(spacing: 0) {
            header

            ZStack {
                switch currentPage {
                case 0: page1.transition(pageTransition)
                case 1: page2.transition(pageTransition)
                case 2: page3.transition(pageTransition)
                default: page4.transition(pageTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: currentPage)

            bottomBar
        }
        .frame(width: 640, height: 460)
        .background(WorkbenchColor.background)
        .tint(WorkbenchColor.accent)
        .alert(
            "Not a Flutter Project",
            isPresented: $isValidationErrorPresented,
            presenting: viewModel.lastValidationError
        ) { error in
            Button("Choose Another Folder") {
                viewModel.chooseProject()
            }
            Button("Cancel", role: .cancel) {
                viewModel.clearValidationError()
            }
        } message: { error in
            Text(error.localizedDescription)
        }
        .onReceive(viewModel.$lastValidationError) { error in
            if error != nil {
                isValidationErrorPresented = true
            }
        }
        .onChange(of: viewModel.projectPath) { _, newValue in
            if newValue != nil {
                onProjectOpened()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: WorkbenchSpacing.compact) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Flunner")
                        .font(.headline)
                    Text("The AI-Agent Sidekick for Flutter")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Step \(currentPage + 1) of \(totalPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                if viewModel.projectPath != nil {
                    Button(action: onProjectOpened) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close Onboarding")
                }
            }
            .padding(.horizontal, WorkbenchSpacing.large)
            .frame(height: 64)

            Divider()
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: WorkbenchSpacing.small) {
                if currentPage < totalPages - 1 {
                    Button("Skip", action: skip)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Spacer()

                pageIndicator

                Spacer()

                if currentPage > 0 {
                    Button("Back", action: goBack)
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }

                if currentPage < totalPages - 1 {
                    Button("Continue", action: continueToNextPage)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
                    .tint(WorkbenchColor.accent)
                    .accessibilityHint("Go to the next page")
                } else {
                    Button("Open Flutter Project…", action: viewModel.chooseProject)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .keyboardShortcut(.defaultAction)
                    .tint(WorkbenchColor.accent)
                    .accessibilityHint("Open a file picker to choose a Flutter project folder")
                }
            }
            .frame(height: 62)
            .padding(.horizontal, 24)
        }
        .background(.bar)
    }

    private var pageIndicator: some View {
        HStack(spacing: WorkbenchSpacing.small) {
            ForEach(0..<totalPages, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? WorkbenchColor.accent : WorkbenchColor.divider)
                    .frame(width: index == currentPage ? 22 : 7, height: 7)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: currentPage)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(currentPage + 1) of \(totalPages)")
    }

    // MARK: - Pages

    private var page1: some View {
        VStack(spacing: WorkbenchSpacing.compact) {
            OnboardingPage(
                symbol: "bolt.badge.automatic.fill",
                stepLabel: "AI-FIRST COMPANION",
                headline: "Your Agent's Runtime Sidekick",
                bodyText: "While your AI coding agent writes and refactors code, Flunner commands the runtime: instant hot-reloads, device orchestration, live log streams, and Git checkpoints.",
                highlights: [
                    "Pairs seamlessly with Cursor, Claude, Windsurf & Copilot",
                    "Instant hot-reload, restart, and state observation",
                ]
            )

            HStack {
                Label("Connect Cursor, Claude, or Codex in one click", systemImage: "cpu")
                    .workbenchFont(.caption, weight: .medium)
                    .foregroundStyle(WorkbenchColor.textSecondary)
                Spacer()
                Button("Set up in Settings…") {
                    NotificationCenter.default.post(name: .openAgentsSettings, object: nil)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, WorkbenchSpacing.extraLarge)
            .padding(.bottom, WorkbenchSpacing.small)
        }
    }

    private var page2: some View {
        OnboardingPage(
            symbol: "waveform.and.magnifyingglass",
            stepLabel: "INSTANT OBSERVABILITY",
            headline: "Live Diagnostics for AI Loops",
            bodyText: "Inspect exceptions, filter logs, and copy structured diagnostic dumps in one click to feed accurate runtime context back into your agent's prompt.",
            highlights: [
                "High-throughput log filtering & regex search",
                "One-click diagnostics export for agent prompts",
            ]
        )
    }

    private var page3: some View {
        OnboardingPage(
            symbol: "square.grid.3x3.fill",
            stepLabel: "FOCUSED WORKBENCH",
            headline: "Everything in Reach",
            bodyText: "Keep interactive PTY terminal tabs, Git commits, and device targets in one calm, native macOS workbench without IDE clutter.",
            highlights: [
                "Built-in PTY terminal tabs for CLI tools",
                "Native Git staging & commit checkpoints",
            ]
        )
    }

    private var page4: some View {
        OnboardingPage(
            symbol: "folder.badge.plus",
            stepLabel: "READY TO BUILD",
            headline: "Open a Flutter Project",
            bodyText: "Choose any Flutter project folder to begin. Flunner validates your environment, detects FVM configurations, and restores your workspace automatically.",
            highlights: [
                "Validates Flutter project & FVM setup",
                "Restores workspace state automatically",
            ]
        )
    }

    private var pageTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    private func skip() {
        if viewModel.projectPath != nil {
            onProjectOpened()
        } else {
            setPage(totalPages - 1)
        }
    }

    private func goBack() {
        setPage(max(0, currentPage - 1))
    }

    private func continueToNextPage() {
        setPage(min(totalPages - 1, currentPage + 1))
    }

    private func setPage(_ page: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            currentPage = page
        }
    }
}

// MARK: - Shared Page Layout

private struct OnboardingPage: View {
    let symbol: String
    let stepLabel: String
    let headline: String
    let bodyText: String
    let highlights: [String]

    var body: some View {
        HStack(spacing: WorkbenchSpacing.extraLarge) {
            ZStack {
                RoundedRectangle(cornerRadius: WorkbenchRadius.large)
                    .fill(WorkbenchColor.accentSoft)

                Image(systemName: symbol)
                    .font(.system(size: 70, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(WorkbenchColor.accent)
                    .accessibilityHidden(true)
            }
            .frame(width: 190, height: 230)
            .overlay {
                RoundedRectangle(cornerRadius: WorkbenchRadius.large)
                    .stroke(WorkbenchColor.accent.opacity(0.18))
            }

            VStack(alignment: .leading, spacing: WorkbenchSpacing.compact) {
                Text(stepLabel)
                    .font(.caption)
                    .bold()
                    .foregroundStyle(WorkbenchColor.accent)

                Text(headline)
                    .font(.largeTitle)
                    .bold()
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .padding(.vertical, WorkbenchSpacing.xs)

                VStack(alignment: .leading, spacing: WorkbenchSpacing.small) {
                    ForEach(highlights, id: \.self) { highlight in
                        Label(highlight, systemImage: "checkmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, WorkbenchSpacing.extraLarge)
        .padding(.vertical, WorkbenchSpacing.large)
    }
}
