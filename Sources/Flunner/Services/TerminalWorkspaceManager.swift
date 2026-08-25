import AppKit
import Combine
import Darwin
import Foundation
@preconcurrency import SwiftTerm

@MainActor
protocol TerminalSession: AnyObject {
    var view: NSView { get }

    func applyAppearance(fontSize: CGFloat, foreground: NSColor, background: NSColor, caret: NSColor)
    func focus()
    func terminate()
    func sendText(_ text: String)
}

@MainActor
protocol TerminalSessionCreating {
    func makeSession(
        id: UUID,
        projectPath: String,
        titleChanged: @escaping (String) -> Void,
        terminated: @escaping (Int32?) -> Void
    ) -> any TerminalSession
}

struct SwiftTermSessionFactory: TerminalSessionCreating {
    func makeSession(
        id: UUID,
        projectPath: String,
        titleChanged: @escaping (String) -> Void,
        terminated: @escaping (Int32?) -> Void
    ) -> any TerminalSession {
        SwiftTermSession(
            id: id,
            projectPath: projectPath,
            titleChanged: titleChanged,
            terminated: terminated
        )
    }
}

@MainActor
final class TerminalWorkspaceManager: ObservableObject {
    @Published private var workspaces: [String: TerminalWorkspaceSnapshot]
    @Published private(set) var focusRevision = 0

    var onSnapshotChange: ((String, TerminalWorkspaceSnapshot) -> Void)?

    private let sessionFactory: any TerminalSessionCreating
    private var sessionsByProject: [String: [UUID: any TerminalSession]] = [:]
    private var hydratedProjects: Set<String> = []

    init(
        projects: [RecentProject] = [],
        sessionFactory: (any TerminalSessionCreating)? = nil
    ) {
        self.sessionFactory = sessionFactory ?? SwiftTermSessionFactory()
        workspaces = Dictionary(
            uniqueKeysWithValues: projects.compactMap { project in
                project.terminalWorkspace.map { (project.path, $0) }
            }
        )
        // Always start with terminal hidden; users toggle it with Ctrl+`
        for key in workspaces.keys {
            var snapshot = workspaces[key]!
            snapshot.isVisible = false
            workspaces[key] = snapshot
        }
    }

    func snapshot(for projectPath: String) -> TerminalWorkspaceSnapshot {
        workspaces[projectPath] ?? TerminalWorkspaceSnapshot()
    }

    func isVisible(for projectPath: String?) -> Bool {
        guard let projectPath else { return false }
        return snapshot(for: projectPath).isVisible
    }

    func tabs(for projectPath: String) -> [TerminalTabSnapshot] {
        snapshot(for: projectPath).tabs
    }

    func selectedTabID(for projectPath: String) -> UUID? {
        snapshot(for: projectPath).selectedTabID
    }

    func selectedSession(for projectPath: String) -> (any TerminalSession)? {
        guard let selectedID = selectedTabID(for: projectPath) else { return nil }
        return sessionsByProject[projectPath]?[selectedID]
    }

    func activateProject(_ projectPath: String) {
        ensureWorkspace(for: projectPath)
        hydrateProjectIfNeeded(projectPath)

        let state = snapshot(for: projectPath)
        if state.isVisible, state.tabs.isEmpty {
            addTab(to: projectPath)
        }
    }

    func sendToActiveSession(_ command: FlutterCLICommand, in projectPath: String) {
        let text = (["flutter"] + command.arguments).joined(separator: " ")
        sendText(text, in: projectPath)
    }

    func sendText(_ text: String, in projectPath: String) {
        sendToActiveSession(text: text, in: projectPath)
    }

    private func sendToActiveSession(text: String, in projectPath: String) {
        ensureWorkspace(for: projectPath)
        var state = snapshot(for: projectPath)

        if state.tabs.isEmpty {
            addTab(to: projectPath)
            state = snapshot(for: projectPath)
        }

        if !state.isVisible {
            toggle(for: projectPath)
        }

        hydrateProjectIfNeeded(projectPath)
        selectedSession(for: projectPath)?.sendText(text + "\r")
    }

    func toggle(for projectPath: String) {
        ensureWorkspace(for: projectPath)
        var state = snapshot(for: projectPath)

        if state.isVisible {
            state.isVisible = false
            setSnapshot(state, for: projectPath)
            return
        }

        if state.tabs.isEmpty {
            addTab(to: projectPath)
            return
        }

        hydrateProjectIfNeeded(projectPath)
        state = snapshot(for: projectPath)
        state.isVisible = true
        setSnapshot(state, for: projectPath)
        requestFocus()
    }

    func addTab(to projectPath: String) {
        ensureWorkspace(for: projectPath)
        hydrateProjectIfNeeded(projectPath)

        var state = snapshot(for: projectPath)
        let tab = TerminalTabSnapshot(title: nextDefaultTitle(in: state.tabs))
        state.tabs.append(tab)
        state.selectedTabID = tab.id
        state.isVisible = true
        workspaces[projectPath] = state
        createSession(for: tab, projectPath: projectPath)
        persist(projectPath)
        requestFocus()
    }

    func selectTab(_ tabID: UUID, in projectPath: String) {
        var state = snapshot(for: projectPath)
        guard state.tabs.contains(where: { $0.id == tabID }) else { return }
        hydrateProjectIfNeeded(projectPath)
        state.selectedTabID = tabID
        state.isVisible = true
        setSnapshot(state, for: projectPath)
        requestFocus()
    }

    func closeTab(_ tabID: UUID, in projectPath: String) {
        closeTab(tabID, in: projectPath, terminateProcess: true)
    }

    func updatePaneHeight(_ height: Double, for projectPath: String, persist: Bool) {
        var state = snapshot(for: projectPath)
        let clamped = max(TerminalWorkspaceSnapshot.minimumPaneHeight, height)
        guard state.paneHeight != clamped else { return }
        state.paneHeight = clamped
        workspaces[projectPath] = state
        if persist { self.persist(projectPath) }
    }

    func persistPaneHeight(for projectPath: String) {
        persist(projectPath)
    }

    func removeProject(_ projectPath: String) {
        terminateSessions(for: projectPath)
        hydratedProjects.remove(projectPath)
        workspaces.removeValue(forKey: projectPath)
    }

    func retainProjects(_ projectPaths: Set<String>) {
        let removedPaths = Set(workspaces.keys).subtracting(projectPaths)
        for path in removedPaths {
            removeProject(path)
        }
    }

    func terminateAll() {
        for path in Array(sessionsByProject.keys) {
            terminateSessions(for: path)
        }
        hydratedProjects.removeAll()
    }

    private func ensureWorkspace(for projectPath: String) {
        if workspaces[projectPath] == nil {
            workspaces[projectPath] = TerminalWorkspaceSnapshot()
        }
    }

    private func hydrateProjectIfNeeded(_ projectPath: String) {
        guard !hydratedProjects.contains(projectPath) else { return }
        hydratedProjects.insert(projectPath)
        for tab in snapshot(for: projectPath).tabs {
            createSession(for: tab, projectPath: projectPath)
        }
    }

    private func createSession(for tab: TerminalTabSnapshot, projectPath: String) {
        guard sessionsByProject[projectPath]?[tab.id] == nil else { return }
        let session = sessionFactory.makeSession(
            id: tab.id,
            projectPath: projectPath,
            titleChanged: { [weak self] title in
                self?.updateTitle(title, for: tab.id, projectPath: projectPath)
            },
            terminated: { [weak self] _ in
                self?.closeTab(tab.id, in: projectPath, terminateProcess: false)
            }
        )
        sessionsByProject[projectPath, default: [:]][tab.id] = session
    }

    private func updateTitle(_ rawTitle: String, for tabID: UUID, projectPath: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var state = snapshot(for: projectPath)
        guard let index = state.tabs.firstIndex(where: { $0.id == tabID }),
              state.tabs[index].title != title else { return }
        state.tabs[index].title = title
        setSnapshot(state, for: projectPath)
    }

    private func closeTab(_ tabID: UUID, in projectPath: String, terminateProcess: Bool) {
        var state = snapshot(for: projectPath)
        guard let removedIndex = state.tabs.firstIndex(where: { $0.id == tabID }) else { return }

        let session = sessionsByProject[projectPath]?.removeValue(forKey: tabID)
        if sessionsByProject[projectPath]?.isEmpty == true {
            sessionsByProject.removeValue(forKey: projectPath)
        }
        if terminateProcess { session?.terminate() }

        state.tabs.remove(at: removedIndex)
        if state.tabs.isEmpty {
            state.selectedTabID = nil
            state.isVisible = false
        } else if state.selectedTabID == tabID {
            state.selectedTabID = state.tabs[min(removedIndex, state.tabs.count - 1)].id
        }

        setSnapshot(state, for: projectPath)
        if state.isVisible { requestFocus() }
    }

    private func terminateSessions(for projectPath: String) {
        let sessions = sessionsByProject.removeValue(forKey: projectPath)?.values ?? [:].values
        for session in sessions {
            session.terminate()
        }
    }

    private func nextDefaultTitle(in tabs: [TerminalTabSnapshot]) -> String {
        let titles = Set(tabs.map(\.title))
        var index = 1
        while titles.contains("Terminal \(index)") { index += 1 }
        return "Terminal \(index)"
    }

    private func setSnapshot(_ snapshot: TerminalWorkspaceSnapshot, for projectPath: String) {
        workspaces[projectPath] = snapshot
        persist(projectPath)
    }

    private func persist(_ projectPath: String) {
        guard let state = workspaces[projectPath] else { return }
        onSnapshotChange?(projectPath, state)
    }

    private func requestFocus() {
        focusRevision &+= 1
    }
}

@MainActor
private final class SwiftTermSession: NSObject, TerminalSession, LocalProcessTerminalViewDelegate {
    let id: UUID
    let terminalView: LocalProcessTerminalView

    var view: NSView { terminalView }

    private let titleChanged: (String) -> Void
    private let terminated: (Int32?) -> Void
    private var isTerminating = false

    init(
        id: UUID,
        projectPath: String,
        titleChanged: @escaping (String) -> Void,
        terminated: @escaping (Int32?) -> Void
    ) {
        self.id = id
        self.titleChanged = titleChanged
        self.terminated = terminated
        terminalView = LocalProcessTerminalView(frame: .zero)
        super.init()

        terminalView.processDelegate = self
        terminalView.wantsLayer = true
        terminalView.optionAsMetaKey = true

        let shell = LoginShellResolver.resolve()
        terminalView.startProcess(
            executable: shell,
            execName: "-\(URL(fileURLWithPath: shell).lastPathComponent)",
            currentDirectory: projectPath
        )
    }

    func applyAppearance(fontSize: CGFloat, foreground: NSColor, background: NSColor, caret: NSColor) {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if terminalView.font != font { terminalView.font = font }
        terminalView.nativeForegroundColor = foreground
        terminalView.nativeBackgroundColor = background
        terminalView.caretColor = caret
        terminalView.layer?.backgroundColor = background.cgColor
        terminalView.needsDisplay = true
    }

    func focus() {
        terminalView.window?.makeFirstResponder(terminalView)
    }

    func terminate() {
        guard !isTerminating else { return }
        isTerminating = true
        terminalView.terminate()
    }

    func sendText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        terminalView.process.send(data: ArraySlice(data))
    }

    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) { }

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in
            self?.titleChanged(title)
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) { }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            guard let self, !isTerminating else { return }
            terminated(exitCode)
        }
    }
}

private enum LoginShellResolver {
    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let shell = environment["SHELL"], FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }
        if let passwordEntry = getpwuid(getuid()),
           let shellPointer = passwordEntry.pointee.pw_shell {
            let shell = String(cString: shellPointer)
            if FileManager.default.isExecutableFile(atPath: shell) { return shell }
        }
        return FileManager.default.isExecutableFile(atPath: "/bin/zsh") ? "/bin/zsh" : "/bin/bash"
    }
}
