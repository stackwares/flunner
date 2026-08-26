import AppKit
import SwiftUI

struct WorkbenchSidebar: View {
    @ObservedObject var viewModel: WorkspaceViewModel
    @State private var projectSearchText = ""

    private var filteredProjects: [RecentProject] {
        let query = projectSearchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return viewModel.recentProjects }
        return viewModel.recentProjects.filter { project in
            project.displayName.localizedCaseInsensitiveContains(query) ||
            project.path.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            Section("Projects") {
                projectSearchBar

                ForEach(filteredProjects) { project in
                    let isSelected = viewModel.selection == .project(project.path)
                    Button {
                        viewModel.selectWorkspace(.project(project.path))
                    } label: {
                        SidebarProjectRow(
                            project: project,
                            icon: viewModel.projectIcons[project.path],
                            isCurrent: project.path == viewModel.projectPath,
                            runState: viewModel.runState(for: project.path)
                        )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(SidebarSelectionBackground(isSelected: isSelected))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .help("Open \(project.displayName)")
                        .contextMenu {
                            Button("Reveal in Finder") { viewModel.revealProject(project) }
                            Button("Remove", role: .destructive) {
                                viewModel.removeRecentProject(project)
                            }
                            .disabled(viewModel.isProjectRunning(project.path))
                        }
                }

                Button(action: viewModel.chooseProject) {
                    Label("Open Project…", systemImage: "folder.badge.plus")
                        .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
            }

            if !viewModel.liveRuns.isEmpty {
                Section("Sessions") {
                    ForEach(viewModel.liveRuns) { run in
                        let isSelected = viewModel.selectedLiveRunID == run.id
                        Button {
                            viewModel.selectLiveRun(run.id)
                        } label: {
                            SidebarSessionRow(
                                run: run,
                                systemImage: viewModel.devices.first(where: { $0.id == run.deviceId })?.systemImage
                                    ?? "display"
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(SidebarSelectionBackground(isSelected: isSelected))
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        .help("Switch to \(run.deviceName)")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollIndicators(.never)
    }

    private var projectSearchBar: some View {
        HStack(spacing: WorkbenchSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(WorkbenchColor.textSecondary)
            WorkbenchSearchField(text: $projectSearchText, placeholder: "Filter projects")
            if !projectSearchText.isEmpty {
                Button {
                    projectSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(WorkbenchColor.textSecondary)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, WorkbenchSpacing.compact)
        .frame(height: 26)
        .background(WorkbenchColor.background, in: RoundedRectangle(cornerRadius: WorkbenchRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: WorkbenchRadius.large)
                .stroke(WorkbenchColor.divider, lineWidth: 1)
        }
        .padding(.bottom, WorkbenchSpacing.medium)
    }
}

private struct SidebarSelectionBackground: View {
    let isSelected: Bool

    var body: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: WorkbenchRadius.small, style: .continuous)
                .fill(WorkbenchColor.accentSoft)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(WorkbenchColor.accent)
                        .frame(width: 3)
                        .padding(.vertical, WorkbenchSpacing.xs)
                }
                .padding(.vertical, 2)
        }
    }
}

private struct SidebarProjectRow: View {
    let project: RecentProject
    let icon: NSImage?
    let isCurrent: Bool
    let runState: AppState

    var body: some View {
        HStack(spacing: WorkbenchSpacing.small) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: isCurrent ? "folder.fill" : "folder")
                        .foregroundStyle(isCurrent ? WorkbenchColor.accent : WorkbenchColor.textSecondary)
                }
            }
            .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.displayName)
                    .workbenchFont(.body, weight: isCurrent ? .semibold : .regular)
                    .foregroundStyle(WorkbenchColor.textPrimary)
                    .lineLimit(1)
                Text(project.path.abbreviatingWithTildeInPath)
                    .workbenchFont(.caption)
                    .foregroundStyle(WorkbenchColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: WorkbenchSpacing.xs)

            WorkbenchRunStateDot(state: runState)
        }
        .padding(.vertical, WorkbenchSpacing.xs)
        .accessibilityElement(children: .combine)
    }
}

private struct SidebarSessionRow: View {
    let run: LiveRun
    let systemImage: String

    var body: some View {
        HStack(spacing: WorkbenchSpacing.small) {
            Image(systemName: systemImage)
                .foregroundStyle(WorkbenchColor.textSecondary)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(run.deviceName)
                    .workbenchFont(.body, weight: .regular)
                    .foregroundStyle(WorkbenchColor.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .workbenchFont(.caption)
                    .foregroundStyle(WorkbenchColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: WorkbenchSpacing.xs)

            WorkbenchRunStateDot(state: run.state)
        }
        .padding(.vertical, WorkbenchSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(run.deviceName), \(detail)")
    }

    private var detail: String {
        if !run.projectName.isEmpty {
            return "\(run.configurationName) · (\(run.projectName))"
        }
        return run.configurationName
    }
}

struct WorkbenchRunStateDot: View {
    let state: AppState

    var body: some View {
        if state.isRunning {
            Circle()
                .fill(state == .running ? WorkbenchColor.success : WorkbenchColor.warning)
                .frame(width: 7, height: 7)
                .accessibilityLabel(state == .running ? "Running" : "Transitioning")
        } else if state == .error {
            Circle()
                .fill(WorkbenchColor.error)
                .frame(width: 7, height: 7)
                .accessibilityLabel("Run failed")
        }
    }
}

extension String {
    var abbreviatingWithTildeInPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard hasPrefix(home) else { return self }
        return "~" + dropFirst(home.count)
    }
}

struct WorkbenchSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.drawsBackground = false
        field.focusRingType = .none
        field.isBordered = false
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: NSColor.secondaryLabelColor]
        )
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}
