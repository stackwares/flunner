import AppKit
import SwiftUI

extension Notification.Name {
    static let focusConsoleSearch = Notification.Name("focusConsoleSearch")
    static let showFlutterSDKInfo = Notification.Name("showFlutterSDKInfo")
    static let showOnboardingSheet = Notification.Name("showOnboardingSheet")
    static let showAboutSheet = Notification.Name("showAboutSheet")
    static let openAgentsSettings = Notification.Name("openAgentsSettings")
}

struct ConsoleToolbar: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @EnvironmentObject private var keyboardShortcuts: KeyboardShortcutStore
    @FocusState private var searchFocused: Bool
    @AppStorage(PreferenceKeys.followOutput) private var followOutput = true

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularToolbar
            compactToolbar
            narrowToolbar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, WorkbenchSpacing.medium)
        .padding(.vertical, 2)
        .background(WorkbenchColor.surface)
        .onReceive(NotificationCenter.default.publisher(for: .focusConsoleSearch)) { _ in
            searchFocused = true
        }
    }

    private var regularToolbar: some View {
        HStack(spacing: WorkbenchSpacing.small) {
            toolbarLeadingContent(
                searchMaxWidth: 240,
                channelWidth: 200,
                includeMaintenanceLabel: true
            )

            Spacer(minLength: WorkbenchSpacing.small)

            trailingActions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactToolbar: some View {
        HStack(spacing: WorkbenchSpacing.xs) {
            toolbarLeadingContent(
                searchMaxWidth: 220,
                channelWidth: 164,
                includeMaintenanceLabel: false,
                usesFilterMenu: true
            )

            Spacer(minLength: WorkbenchSpacing.small)

            trailingActions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var narrowToolbar: some View {
        HStack(spacing: WorkbenchSpacing.xs) {
            toolbarLeadingContent(
                searchMaxWidth: 160,
                channelWidth: 150,
                includeMaintenanceLabel: false,
                usesFilterMenu: true
            )

            Spacer(minLength: WorkbenchSpacing.small)

            trailingActionsMenu
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func toolbarLeadingContent(
        searchMaxWidth: CGFloat,
        channelWidth: CGFloat,
        includeMaintenanceLabel: Bool,
        usesFilterMenu: Bool = false
    ) -> some View {
        HStack(spacing: usesFilterMenu ? WorkbenchSpacing.xs : WorkbenchSpacing.small) {
            searchField.frame(minWidth: usesFilterMenu ? 96 : 140, maxWidth: searchMaxWidth)

            if usesFilterMenu {
                filtersMenu
            } else {
                ForEach(LogEntryType.allCases, id: \.self) { type in
                    FilterChip(
                        title: type.label,
                        systemImage: type.systemImage,
                        selected: viewModel.enabledLogTypes.contains(type)
                    ) {
                        viewModel.toggleFilter(type)
                    }
                }

                if viewModel.selectedLogChannel == .console {
                    FilterChip(
                        title: "Flutter",
                        systemImage: "bird",
                        selected: viewModel.isFlutterConsoleFilterEnabled
                    ) {
                        viewModel.toggleFlutterConsoleFilter()
                    }
                }
            }

            channelPicker(width: channelWidth)
            maintenanceIndicator(includeLabel: includeMaintenanceLabel)
        }
        .layoutPriority(0)
    }

    private func channelPicker(width: CGFloat) -> some View {
        Picker(
            "",
            selection: Binding(
                get: { viewModel.selectedLogChannel },
                set: { channel in viewModel.selectLogChannel(channel) }
            )
        ) {
            ForEach(LogChannel.allCases) { channel in
                Label(channel.label, systemImage: channel.systemImage)
                    .tag(channel)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: width)
        .accessibilityLabel("Log Channel")
    }

    @ViewBuilder
    private func maintenanceIndicator(includeLabel: Bool) -> some View {
        if viewModel.isCurrentProjectMaintenanceRunning {
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
            if includeLabel {
                Text("Project maintenance running")
                    .workbenchFont(.caption, weight: .medium)
                    .foregroundStyle(WorkbenchColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var filtersMenu: some View {
        Menu {
            ForEach(LogEntryType.allCases, id: \.self) { type in
                Button {
                    viewModel.toggleFilter(type)
                } label: {
                    Label(type.label, systemImage: viewModel.enabledLogTypes.contains(type) ? "checkmark" : type.systemImage)
                }
            }
            if viewModel.selectedLogChannel == .console {
                Divider()
                Button {
                    viewModel.toggleFlutterConsoleFilter()
                } label: {
                    Label(
                        "Flutter",
                        systemImage: viewModel.isFlutterConsoleFilterEnabled ? "checkmark" : "bird"
                    )
                }
            }
        } label: {
            Label("Log Filters", systemImage: "line.3.horizontal.decrease")
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
        }
        .menuStyle(.borderlessButton)
        .workbenchTooltip("Filter \(viewModel.selectedLogChannel.label.lowercased()) output", placement: .below)
        .accessibilityLabel("Log Filters")
    }

    private var searchField: some View {
        HStack(spacing: WorkbenchSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WorkbenchColor.textSecondary)
            WorkbenchSearchField(
                text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.searchText = $0 }
                ),
                placeholder: "Search \(viewModel.selectedLogChannel.label.lowercased())"
            )
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(WorkbenchColor.textSecondary)
                .workbenchTooltip("Clear \(viewModel.selectedLogChannel.label.lowercased()) search", placement: .below)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, WorkbenchSpacing.compact)
        .frame(height: 26)
        .background(WorkbenchColor.background, in: RoundedRectangle(cornerRadius: WorkbenchRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchRadius.large)
                .stroke(searchFocused ? WorkbenchColor.accent : WorkbenchColor.divider, lineWidth: 1)
        }
    }

    private var trailingActions: some View {
        HStack(spacing: WorkbenchSpacing.xs) {
            Button {
                followOutput.toggle()
            } label: {
                Label("Follow Output", systemImage: followOutput ? "arrow.down.to.line.compact" : "pause")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(WorkbenchIconButtonStyle())
            .workbenchTooltip(
                followOutput ? "Auto-scroll outputs" : "Output following paused",
                placement: .below
            )
            .accessibilityLabel(followOutput ? "Pause output following" : "Follow new output")

            Button(action: viewModel.copyVisibleLogs) {
                Label("Copy Visible Output", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(WorkbenchIconButtonStyle())
            .disabled(viewModel.filteredLogs.isEmpty)
            .workbenchTooltip(actionHelp("Copy Visible Output", action: .copyVisibleOutput), placement: .below)
            .accessibilityLabel("Copy Visible Output")

            Button(action: viewModel.exportVisibleLogs) {
                Label("Export Visible Output", systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(WorkbenchIconButtonStyle())
            .disabled(viewModel.filteredLogs.isEmpty)
            .workbenchTooltip(actionHelp("Export Visible Output", action: .exportVisibleOutput), placement: .below)
            .accessibilityLabel("Export Visible Output")

            Button(action: viewModel.clearLogs) {
                Label("Clear \(viewModel.selectedLogChannel.label)", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(WorkbenchIconButtonStyle())
            .disabled(viewModel.logLines.isEmpty)
            .workbenchTooltip(
                actionHelp("Clear \(viewModel.selectedLogChannel.label)", action: .clearConsole),
                placement: .below
            )
            .accessibilityLabel("Clear \(viewModel.selectedLogChannel.label)")

            flutterCLIMenu
        }
        .layoutPriority(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.trailing, WorkbenchSpacing.xs)
    }

    @ViewBuilder
    private var flutterCLIMenu: some View {
        if viewModel.projectPath != nil {
            Menu {
                ForEach(FlutterCLICommand.groups) { group in
                    Section(group.name) {
                        ForEach(group.commands) { command in
                            Button {
                                viewModel.runFlutterCommand(command)
                            } label: {
                                Label(command.name, systemImage: command.systemImage)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "terminal.fill")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(WorkbenchColor.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .workbenchTooltip("Run Flutter CLI command", placement: .below)
            .accessibilityLabel("Flutter CLI Commands")
        }
    }

    private var trailingActionsMenu: some View {
        Menu {
            Button {
                followOutput.toggle()
            } label: {
                Label(followOutput ? "Pause Output Following" : "Follow New Output", systemImage: followOutput ? "pause" : "arrow.down.to.line.compact")
            }

            Divider()

            Button(action: viewModel.copyVisibleLogs) {
                Label("Copy Visible Output", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.filteredLogs.isEmpty)

            Button(action: viewModel.exportVisibleLogs) {
                Label("Export Visible Output", systemImage: "square.and.arrow.up")
            }
            .disabled(viewModel.filteredLogs.isEmpty)

            Button(action: viewModel.clearLogs) {
                Label("Clear \(viewModel.selectedLogChannel.label)", systemImage: "trash")
            }
            .disabled(viewModel.logLines.isEmpty)

            if viewModel.projectPath != nil {
                Divider()

                Menu {
                    ForEach(FlutterCLICommand.groups) { group in
                        Section(group.name) {
                            ForEach(group.commands) { command in
                                Button {
                                    viewModel.runFlutterCommand(command)
                                } label: {
                                    Label(command.name, systemImage: command.systemImage)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Flutter CLI Commands", systemImage: "terminal.fill")
                }
            }
        } label: {
            Label("Log Actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .layoutPriority(1)
        .padding(.trailing, WorkbenchSpacing.xs)
        .workbenchTooltip("More \(viewModel.selectedLogChannel.label.lowercased()) actions", placement: .below)
        .accessibilityLabel("Log Actions")
    }

    private func actionHelp(_ title: String, action: WorkbenchAction) -> String {
        "\(title) (\(keyboardShortcuts.binding(for: action).displayName))"
    }
}

private struct FilterChip: View {
    let title: String
    let systemImage: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .workbenchFont(.caption, weight: .medium)
                .foregroundStyle(selected ? WorkbenchColor.textPrimary : WorkbenchColor.textSecondary)
                .padding(.horizontal, WorkbenchSpacing.small)
                .frame(height: 26)
                .background(
                    selected ? WorkbenchColor.accentSoft : .clear,
                    in: Capsule()
                )
                .overlay { Capsule().stroke(WorkbenchColor.divider, lineWidth: selected ? 0 : 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "On" : "Off")
    }
}

struct ConsolePanel: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @AppStorage(PreferenceKeys.consoleFontSize) private var consoleFontSize = 12.0
    @AppStorage(PreferenceKeys.showTimestamps) private var showTimestamps = true
    @AppStorage(PreferenceKeys.followOutput) private var followOutput = true

    var body: some View {
        Group {
            if viewModel.logLines.isEmpty {
                LogEmptyState(viewModel: viewModel)
            } else if viewModel.filteredLogs.isEmpty {
                ContentUnavailableView(
                    "No Matching Output",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Change the search or enable another log type.")
                )
            } else {
                SelectableConsoleTextView(
                    entries: viewModel.filteredLogs,
                    fontSize: consoleFontSize,
                    showTimestamps: showTimestamps,
                    followOutput: followOutput,
                    accessibilityLabel: "\(viewModel.selectedLogChannel.label) output"
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WorkbenchColor.surface)
    }
}

private struct SelectableConsoleTextView: NSViewRepresentable {
    let entries: [LogEntry]
    let fontSize: CGFloat
    let showTimestamps: Bool
    let followOutput: Bool
    let accessibilityLabel: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(
            width: WorkbenchSpacing.medium,
            height: WorkbenchSpacing.compact
        )
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel(accessibilityLabel)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.setAccessibilityLabel(accessibilityLabel)
        context.coordinator.update(
            textView: textView,
            in: scrollView,
            entries: entries,
            fontSize: fontSize,
            showTimestamps: showTimestamps,
            followOutput: followOutput
        )
    }

    @MainActor
    final class Coordinator {
        private var renderedEntryIDs: [UUID] = []
        private var renderedFontSize: CGFloat?
        private var renderedShowTimestamps: Bool?

        func update(
            textView: NSTextView,
            in scrollView: NSScrollView,
            entries: [LogEntry],
            fontSize: CGFloat,
            showTimestamps: Bool,
            followOutput: Bool
        ) {
            let entryIDs = entries.map(\.id)
            let presentationUnchanged = renderedFontSize == fontSize
                && renderedShowTimestamps == showTimestamps

            guard entryIDs != renderedEntryIDs || !presentationUnchanged else { return }

            let selectedRange = textView.selectedRange()
            let visibleOrigin = scrollView.contentView.bounds.origin
            let canAppend = presentationUnchanged
                && !renderedEntryIDs.isEmpty
                && entryIDs.count > renderedEntryIDs.count
                && entryIDs.starts(with: renderedEntryIDs)

            if canAppend {
                let newEntries = entries.dropFirst(renderedEntryIDs.count)
                let addition = ConsoleTextRenderer.attributedString(
                    for: newEntries,
                    fontSize: fontSize,
                    showTimestamps: showTimestamps,
                    includeLeadingNewline: true
                )
                textView.textStorage?.append(addition)
            } else {
                let content = ConsoleTextRenderer.attributedString(
                    for: entries[...],
                    fontSize: fontSize,
                    showTimestamps: showTimestamps,
                    includeLeadingNewline: false
                )
                textView.textStorage?.setAttributedString(content)
            }

            let textLength = textView.string.utf16.count
            let selectionLocation = min(selectedRange.location, textLength)
            let selectionLength = min(selectedRange.length, textLength - selectionLocation)
            textView.setSelectedRange(NSRange(location: selectionLocation, length: selectionLength))

            renderedEntryIDs = entryIDs
            renderedFontSize = fontSize
            renderedShowTimestamps = showTimestamps

            if followOutput, selectedRange.length == 0 {
                textView.scrollToEndOfDocument(nil)
            } else if !canAppend {
                scrollView.contentView.scroll(to: visibleOrigin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        }
    }
}

private enum ConsoleTextRenderer {
    private static let timestampStyle = Date.FormatStyle.dateTime
        .hour(.twoDigits(amPM: .omitted))
        .minute(.twoDigits)
        .second(.twoDigits)
        .secondFraction(.fractional(3))
        .locale(Locale(identifier: "en_US_POSIX"))

    static func attributedString(
        for entries: ArraySlice<LogEntry>,
        fontSize: CGFloat,
        showTimestamps: Bool,
        includeLeadingNewline: Bool
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let symbolFont = NSFont.monospacedSystemFont(ofSize: max(9, fontSize - 2), weight: .semibold)
        let prefixTemplate = showTimestamps ? "00:00:00.000  ●  " : "●  "
        let wrappedLineIndent = (prefixTemplate as NSString).size(withAttributes: [.font: font]).width

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = wrappedLineIndent
        paragraphStyle.paragraphSpacing = 2

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: namedColor("WorkbenchTextPrimary", fallback: .labelColor),
            .paragraphStyle: paragraphStyle,
        ]

        if includeLeadingNewline, !entries.isEmpty {
            result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
        }

        for (offset, entry) in entries.enumerated() {
            if offset > 0 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }

            if showTimestamps {
                let timestampAttributes = baseAttributes.merging([
                    .foregroundColor: namedColor("WorkbenchTextSecondary", fallback: .secondaryLabelColor)
                        .withAlphaComponent(0.78),
                ]) { _, new in new }
                result.append(NSAttributedString(
                    string: entry.timestamp.formatted(timestampStyle) + "  ",
                    attributes: timestampAttributes
                ))
            }

            let symbolAttributes = baseAttributes.merging([
                .font: symbolFont,
                .foregroundColor: symbolColor(for: entry.type),
            ]) { _, new in new }
            result.append(NSAttributedString(
                string: symbol(for: entry.type) + "  ",
                attributes: symbolAttributes
            ))

            let messageAttributes = baseAttributes.merging([
                .foregroundColor: entry.type == .error
                    ? namedColor("WorkbenchError", fallback: .systemRed)
                    : namedColor("WorkbenchTextPrimary", fallback: .labelColor),
            ]) { _, new in new }
            result.append(NSAttributedString(string: entry.text, attributes: messageAttributes))
        }

        return result
    }

    private static func symbol(for type: LogEntryType) -> String {
        switch type {
        case .info: "●"
        case .error: "×"
        case .command: "›"
        }
    }

    private static func symbolColor(for type: LogEntryType) -> NSColor {
        switch type {
        case .info:
            namedColor("WorkbenchTextSecondary", fallback: .secondaryLabelColor).withAlphaComponent(0.5)
        case .error:
            namedColor("WorkbenchError", fallback: .systemRed)
        case .command:
            namedColor("WorkbenchAccent", fallback: .controlAccentColor)
        }
    }

    private static func namedColor(_ name: String, fallback: NSColor) -> NSColor {
        NSColor(named: NSColor.Name(name)) ?? fallback
    }
}

private struct LogEmptyState: View {
    @ObservedObject var viewModel: WorkspaceViewModel

    var body: some View {
        if viewModel.projectPath == nil {
            ContentUnavailableView {
                Label("Choose a Flutter Project", systemImage: "folder.badge.plus")
            } description: {
                Text("Open a project to choose a device and start a run.")
            } actions: {
                Button("Open Project…", action: viewModel.chooseProject)
                    .buttonStyle(WorkbenchPrimaryButtonStyle())
            }
        } else if viewModel.selectedLogChannel == .output {
            ContentUnavailableView(
                "Output Ready",
                systemImage: "text.alignleft",
                description: Text("Run Pub Get or Clean + Pub Get to see project maintenance output.")
            )
        } else if !viewModel.isDaemonRunning {
            ContentUnavailableView {
                Label("Flutter Tools Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(viewModel.status)
            } actions: {
                Button("Retry", action: viewModel.retryDaemon)
                    .buttonStyle(WorkbenchPrimaryButtonStyle())
            }
        } else {
            ContentUnavailableView(
                "Console Ready",
                systemImage: "terminal",
                description: Text(viewModel.runBlockReason ?? "Run the selected project to see live Flutter output.")
            )
        }
    }
}

struct WorkbenchStatusBar: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @ObservedObject var sourceControlViewModel: SourceControlViewModel
    @Binding var isSourceControlSheetPresented: Bool
    @AppStorage(PreferenceKeys.consoleFontSize) private var consoleFontSize = 12.0

    var body: some View {
        HStack(spacing: WorkbenchSpacing.small) {
            gitGlance

            daemonIndicator
            Text(viewModel.status)
                .workbenchFont(.caption, weight: .medium)
                .foregroundStyle(WorkbenchColor.textSecondary)
                .lineLimit(1)
            Spacer()
            if !viewModel.logLines.isEmpty {
                Text("\(viewModel.filteredLogs.count) of \(viewModel.logLines.count) lines")
                    .workbenchFont(.caption, design: .monospaced)
                    .monospacedDigit()
                    .foregroundStyle(WorkbenchColor.textSecondary)
            }

            Button {
                consoleFontSize = max(9, consoleFontSize - 1)
            } label: {
                Label("Decrease Log Font Size", systemImage: "textformat.size.smaller")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(WorkbenchIconButtonStyle())
            .disabled(consoleFontSize <= 9)
            .workbenchTooltip("Decrease log font size")
            .accessibilityLabel("Decrease Log Font Size")

            Button {
                consoleFontSize = min(20, consoleFontSize + 1)
            } label: {
                Label("Increase Log Font Size", systemImage: "textformat.size.larger")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(WorkbenchIconButtonStyle())
            .disabled(consoleFontSize >= 20)
            .workbenchTooltip("Increase log font size")
            .accessibilityLabel("Increase Log Font Size")
        }
        .padding(.horizontal, WorkbenchSpacing.medium)
        .frame(height: 44)
        .background(WorkbenchColor.background)
        .overlay(alignment: .top) { Divider().overlay(WorkbenchColor.divider) }
    }

    @ViewBuilder
    private var gitGlance: some View {
        if let snapshot = sourceControlViewModel.snapshot {
            Button {
                isSourceControlSheetPresented = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .medium))
                    Text(snapshot.branch)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if snapshot.ahead > 0 {
                        Text("↑\(snapshot.ahead)")
                            .foregroundStyle(WorkbenchColor.accent)
                    }
                    if snapshot.behind > 0 {
                        Text("↓\(snapshot.behind)")
                            .foregroundStyle(WorkbenchColor.warning)
                    }
                    if snapshot.changeCount > 0 {
                        Text("\(snapshot.changeCount) files")
                            .foregroundStyle(WorkbenchColor.warning)
                    }
                }
                .workbenchFont(.caption, weight: .medium)
                .foregroundStyle(WorkbenchColor.textSecondary)
            }
            .buttonStyle(.plain)
            .workbenchTooltip("View source control (⌘2)", placement: .above)
            .accessibilityLabel("Source Control: \(snapshot.branch)")
            .accessibilityValue("\(snapshot.changeCount) files changed")
        } else if sourceControlViewModel.projectPath != nil {
            Label("No Repository", systemImage: "arrow.triangle.branch")
                .workbenchFont(.caption)
                .foregroundStyle(WorkbenchColor.textSecondary.opacity(0.6))
        }
    }

    private var statusColor: Color {
        if viewModel.selectedLogChannel == .output, viewModel.isCurrentProjectMaintenanceRunning {
            return WorkbenchColor.warning
        }
        return switch viewModel.appState {
        case .idle: viewModel.isDaemonRunning ? WorkbenchColor.textSecondary : WorkbenchColor.warning
        case .starting, .stopping: WorkbenchColor.warning
        case .running: WorkbenchColor.success
        case .error: WorkbenchColor.error
        }
    }

    @ViewBuilder
    private var daemonIndicator: some View {
        let display = daemonStatusDisplay
        HStack(spacing: 4) {
            Image(systemName: display.icon)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(display.color)
            Text(display.label)
                .workbenchFont(.caption, weight: .medium)
                .foregroundStyle(display.color)
            if daemonNeedsRestart {
                Button {
                    viewModel.restartDaemon()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .workbenchTooltip("Restart Flutter daemon")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(display.color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .help(display.help)
    }

    private var daemonNeedsRestart: Bool {
        if case .failed = viewModel.daemonState { return true }
        return viewModel.daemonState == .stopped
    }

    private var daemonStatusDisplay: (color: Color, icon: String, label: String, help: String) {
        if viewModel.appState != .idle {
            return switch viewModel.appState {
            case .starting:
                (WorkbenchColor.warning, "play.fill", "Starting", "Launching app…")
            case .running:
                (WorkbenchColor.success, "bolt.fill", "Running", "App is running")
            case .stopping:
                (WorkbenchColor.warning, "stop.fill", "Stopping", "Stopping app…")
            case .error:
                (WorkbenchColor.error, "xmark.circle.fill", "Error", "App encountered an error")
            case .idle:
                (WorkbenchColor.textSecondary, "circle", "", "")
            }
        }
        return switch viewModel.daemonState {
        case .idle:
            (WorkbenchColor.textSecondary, "circle.dotted", "Offline", "Flutter daemon has not been started")
        case .starting:
            (WorkbenchColor.warning, "arrow.triangle.2.circlepath", "Connecting", "Starting Flutter daemon…")
        case .connected:
            (WorkbenchColor.success, "circle.fill", "Ready", "Flutter daemon is connected and ready")
        case .failed(let reason):
            (WorkbenchColor.error, "xmark.circle.fill", "Failed", "Daemon failed: \(reason)")
        case .stopped:
            (WorkbenchColor.textSecondary, "circle.slash", "Stopped", "Daemon has stopped")
        }
    }
}
