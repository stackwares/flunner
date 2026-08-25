import AppKit
import Combine
import Foundation

enum SourceControlConfirmation: Identifiable, Equatable {
    case discard([GitFileSelection])
    case trash([GitFileSelection])
    case deleteBranch(String)
    case merge(String)
    case rebase(String)
    case dropStash(GitStash)
    case revert(GitCommit)
    case abort(GitRepositoryOperation)
    case amend(String)

    var id: String {
        switch self {
        case let .discard(files): "discard:\(files.map(\.id).joined(separator: ","))"
        case let .trash(files): "trash:\(files.map(\.id).joined(separator: ","))"
        case let .deleteBranch(name): "delete:\(name)"
        case let .merge(name): "merge:\(name)"
        case let .rebase(name): "rebase:\(name)"
        case let .dropStash(stash): "stash:\(stash.id)"
        case let .revert(commit): "revert:\(commit.id)"
        case let .abort(operation): "abort:\(operation.rawValue)"
        case let .amend(message): "amend:\(message)"
        }
    }
}

@MainActor
final class SourceControlViewModel: ObservableObject {
    static let historyPageSize = 100

    @Published private(set) var snapshot: GitRepositorySnapshot?
    @Published private(set) var branches: [GitBranch] = []
    @Published private(set) var commits: [GitCommit] = []
    @Published private(set) var stashes: [GitStash] = []
    @Published private(set) var diff: GitDiff?
    @Published private(set) var activity: SourceControlActivity = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRepositoryMissing = false
    @Published private(set) var hasMoreHistory = false
    @Published var selectedSection: SourceControlSection = .changes
    @Published var selectedFiles: Set<GitFileSelection> = []
    @Published var selectedCommit: GitCommit?
    @Published var commitMessage = "" {
        didSet {
            guard let root = snapshot?.rootURL.path else { return }
            commitDrafts[root] = commitMessage
        }
    }
    @Published var confirmation: SourceControlConfirmation?

    private let client: any GitClientProtocol
    private var projectURL: URL?
    private var commitDrafts: [String: String] = [:]
    private var refreshTask: Task<Void, Never>?
    private var diffTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var refreshGeneration = UUID()

    init(client: any GitClientProtocol = GitProcessClient()) {
        self.client = client
    }

    var repositoryName: String {
        snapshot?.rootURL.lastPathComponent ?? projectURL?.lastPathComponent ?? "Source Control"
    }

    var currentBranch: String { snapshot?.branch ?? "No repository" }
    var isBusy: Bool { activity != .idle }
    var canCommit: Bool {
        snapshot?.hasStagedChanges == true
            && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBusy
    }
    var canAmend: Bool {
        snapshot?.isUnborn == false
            && !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBusy
    }
    var canStageAll: Bool { snapshot?.hasWorkingTreeChanges == true && !isBusy }
    var canPush: Bool { snapshot?.upstream != nil && !isBusy }
    var canPull: Bool { snapshot?.upstream != nil && !isBusy }
    var canPublish: Bool {
        snapshot?.upstream == nil && snapshot?.remotes.isEmpty == false && snapshot?.isUnborn == false && !isBusy
    }

    var conflicts: [GitFileSelection] {
        snapshot?.files.filter(\.isConflicted).map { GitFileSelection(file: $0, comparison: .workingTree) } ?? []
    }

    var stagedChanges: [GitFileSelection] {
        snapshot?.files.filter { $0.hasStagedChanges && !$0.isConflicted }
            .map { GitFileSelection(file: $0, comparison: .staged) } ?? []
    }

    var workingTreeChanges: [GitFileSelection] {
        snapshot?.files.filter { $0.hasWorkingTreeChanges && !$0.isUntracked && !$0.isConflicted }
            .map { GitFileSelection(file: $0, comparison: .workingTree) } ?? []
    }

    var untrackedChanges: [GitFileSelection] {
        snapshot?.files.filter(\.isUntracked).map { GitFileSelection(file: $0, comparison: .workingTree) } ?? []
    }

    func setProjectPath(_ path: String?) {
        let newURL = path.map { URL(fileURLWithPath: $0).standardizedFileURL }
        guard newURL != projectURL else { return }
        if let oldRoot = snapshot?.rootURL.path { commitDrafts[oldRoot] = commitMessage }
        projectURL = newURL
        resetRepositoryState()
        stopPolling()
        if newURL != nil {
            startPolling()
        }
    }

    var projectPath: String? { projectURL?.path }

    func startPolling() {
        guard pollingTask == nil else { return }
        refresh()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard let self else { return }
                await self.refreshStatusOnly()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() {
        refreshTask?.cancel()
        let generation = UUID()
        refreshGeneration = generation
        refreshTask = Task { [weak self] in
            await self?.refreshNow(generation: generation)
        }
    }

    func refreshAfterActivation() {
        guard pollingTask != nil else { return }
        refresh()
    }

    func initializeRepository() {
        guard let projectURL else { return }
        perform("Initializing repository…") { client in
            _ = try await client.initializeRepository(at: projectURL)
        }
    }

    func selectionChanged() {
        selectedCommit = nil
        guard selectedFiles.count == 1, let selection = selectedFiles.first, let root = snapshot?.rootURL else {
            diffTask?.cancel()
            diff = nil
            return
        }
        loadDiff(selection: selection, root: root)
    }

    func selectCommit(_ commit: GitCommit) {
        selectedFiles = []
        selectedCommit = commit
        guard let root = snapshot?.rootURL else { return }
        diffTask?.cancel()
        diffTask = Task { [weak self, client] in
            do {
                let loaded = try await client.commitDiff(at: root, commit: commit)
                guard let self, self.selectedCommit?.id == commit.id else { return }
                self.diff = loaded
            } catch is CancellationError {
                return
            } catch {
                self?.present(error)
            }
        }
    }

    func loadMoreHistory() {
        guard hasMoreHistory, let root = snapshot?.rootURL, operationTask == nil else { return }
        let offset = commits.count
        perform("Loading more history…", refreshAfterward: false) { [weak self] client in
            let next = try await client.history(at: root, offset: offset, limit: Self.historyPageSize)
            guard let self else { return }
            self.commits.append(contentsOf: next)
            self.hasMoreHistory = next.count == Self.historyPageSize
        }
    }

    func stageSelected() {
        let paths = selectedFiles.filter { $0.comparison == .workingTree }.map(\.file.path)
        guard let root = snapshot?.rootURL, !paths.isEmpty else { return }
        perform("Staging files…") { try await $0.stage(paths: paths, at: root) }
    }

    func unstageSelected() {
        let paths = selectedFiles.filter { $0.comparison == .staged }.map(\.file.path)
        guard let root = snapshot?.rootURL, !paths.isEmpty else { return }
        perform("Unstaging files…") { try await $0.unstage(paths: paths, at: root) }
    }

    func stage(_ selection: GitFileSelection) {
        guard let root = snapshot?.rootURL else { return }
        perform("Staging \(selection.file.displayName)…") {
            try await $0.stage(paths: [selection.file.path], at: root)
        }
    }

    func unstage(_ selection: GitFileSelection) {
        guard let root = snapshot?.rootURL else { return }
        perform("Unstaging \(selection.file.displayName)…") {
            try await $0.unstage(paths: [selection.file.path], at: root)
        }
    }

    func stageAll() {
        guard let root = snapshot?.rootURL else { return }
        perform("Staging all changes…") { try await $0.stageAll(at: root) }
    }

    func unstageAll() {
        guard let root = snapshot?.rootURL else { return }
        perform("Unstaging all changes…") { try await $0.unstageAll(at: root) }
    }

    func requestDiscard(_ selections: [GitFileSelection]) {
        let tracked = selections.filter { !$0.file.isUntracked && $0.comparison == .workingTree }
        guard !tracked.isEmpty else { return }
        confirmation = .discard(tracked)
    }

    func requestTrash(_ selections: [GitFileSelection]) {
        let untracked = selections.filter(\.file.isUntracked)
        guard !untracked.isEmpty else { return }
        confirmation = .trash(untracked)
    }

    func commit() {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canCommit, let root = snapshot?.rootURL else { return }
        perform("Creating commit…") { [weak self] client in
            try await client.commit(message: message, at: root)
            self?.commitMessage = ""
            self?.commitDrafts[root.path] = ""
        }
    }

    func requestAmend() {
        let message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAmend, !message.isEmpty else { return }
        confirmation = .amend(message)
    }

    func fetch() {
        guard let root = snapshot?.rootURL else { return }
        perform("Fetching from remotes…") { try await $0.fetch(at: root) }
    }

    func pull() {
        guard canPull, let root = snapshot?.rootURL else { return }
        perform("Pulling changes…") { try await $0.pull(at: root) }
    }

    func push() {
        guard canPush, let root = snapshot?.rootURL else { return }
        perform("Pushing changes…") { try await $0.push(at: root) }
    }

    func publish() {
        guard canPublish, let root = snapshot?.rootURL, let snapshot else { return }
        let remote = snapshot.remotes.first(where: { $0.name == "origin" })?.name ?? snapshot.remotes[0].name
        perform("Publishing branch…") { try await $0.publish(branch: snapshot.branch, remote: remote, at: root) }
    }

    func switchBranch(_ branch: GitBranch) {
        guard !branch.isCurrent, let root = snapshot?.rootURL else { return }
        let name: String
        if branch.isRemote {
            name = branch.name.split(separator: "/", maxSplits: 1).last.map(String.init) ?? branch.name
        } else {
            name = branch.name
        }
        perform("Switching to \(name)…") { try await $0.switchBranch(name, at: root) }
    }

    func createBranch(named rawName: String, startPoint: String? = nil) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let root = snapshot?.rootURL else { return }
        perform("Creating \(name)…") { try await $0.createBranch(name, startPoint: startPoint, at: root) }
    }

    func renameCurrentBranch(to rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let root = snapshot?.rootURL else { return }
        perform("Renaming branch…") { try await $0.renameCurrentBranch(to: name, at: root) }
    }

    func requestDeleteBranch(_ branch: GitBranch) {
        guard !branch.isCurrent, !branch.isRemote else { return }
        confirmation = .deleteBranch(branch.name)
    }

    func requestMerge(_ branch: GitBranch) {
        guard !branch.isCurrent else { return }
        confirmation = .merge(branch.name)
    }

    func requestRebase(_ branch: GitBranch) {
        guard !branch.isCurrent else { return }
        confirmation = .rebase(branch.name)
    }

    func createStash(message: String?, includeUntracked: Bool) {
        guard let root = snapshot?.rootURL else { return }
        perform("Stashing changes…") {
            try await $0.createStash(message: message, includeUntracked: includeUntracked, at: root)
        }
    }

    func applyStash(_ stash: GitStash) {
        guard let root = snapshot?.rootURL else { return }
        perform("Applying stash…") { try await $0.applyStash(stash.reference, at: root) }
    }

    func popStash(_ stash: GitStash) {
        guard let root = snapshot?.rootURL else { return }
        perform("Popping stash…") { try await $0.popStash(stash.reference, at: root) }
    }

    func requestDropStash(_ stash: GitStash) { confirmation = .dropStash(stash) }
    func requestRevert(_ commit: GitCommit) { confirmation = .revert(commit) }
    func requestAbort(_ operation: GitRepositoryOperation) { confirmation = .abort(operation) }

    func continueOperation() {
        guard let operation = snapshot?.operation, let root = snapshot?.rootURL else { return }
        perform("Continuing \(operation.rawValue)…") { try await $0.continueOperation(operation, at: root) }
    }

    func confirmPendingAction() {
        guard let confirmation, let root = snapshot?.rootURL else { return }
        self.confirmation = nil
        switch confirmation {
        case let .discard(files):
            let paths = files.map(\.file.path)
            perform("Discarding changes…") { try await $0.discard(paths: paths, at: root) }
        case let .trash(files):
            let urls = files.map { root.appendingPathComponent($0.file.path) }
            perform("Moving files to Trash…") { [weak self] _ in try await self?.moveToTrash(urls) }
        case let .deleteBranch(name):
            perform("Deleting \(name)…") { try await $0.deleteBranch(name, at: root) }
        case let .merge(name):
            perform("Merging \(name)…") { try await $0.mergeBranch(name, at: root) }
        case let .rebase(name):
            perform("Rebasing onto \(name)…") { try await $0.rebase(onto: name, at: root) }
        case let .dropStash(stash):
            perform("Deleting stash…") { try await $0.dropStash(stash.reference, at: root) }
        case let .revert(commit):
            perform("Reverting \(commit.shortSHA)…") { try await $0.revertCommit(commit.sha, at: root) }
        case let .abort(operation):
            perform("Aborting \(operation.rawValue)…") { try await $0.abortOperation(operation, at: root) }
        case let .amend(message):
            perform("Amending latest commit…") { [weak self] client in
                try await client.amendCommit(message: message, at: root)
                self?.commitMessage = ""
                self?.commitDrafts[root.path] = ""
            }
        }
    }

    func openFile(_ selection: GitFileSelection) {
        guard let root = snapshot?.rootURL else { return }
        NSWorkspace.shared.open(root.appendingPathComponent(selection.file.path))
    }

    func revealRepository() {
        guard let root = snapshot?.rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    func copySHA(_ commit: GitCommit) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commit.sha, forType: .string)
    }

    func dismissError() { errorMessage = nil }

    private func loadDiff(selection: GitFileSelection, root: URL) {
        diffTask?.cancel()
        diffTask = Task { [weak self, client] in
            do {
                let loaded = try await client.diff(at: root, selection: selection)
                guard let self, self.selectedFiles == Set([selection]) else { return }
                self.diff = loaded
            } catch is CancellationError {
                return
            } catch {
                self?.present(error)
            }
        }
    }

    private func refreshStatusOnly() async {
        guard operationTask == nil, let root = snapshot?.rootURL else { return }
        do {
            let updated = try await client.snapshot(at: root)
            snapshot = updated
            reconcileSelection(with: updated)
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    private func apply(
        snapshot: GitRepositorySnapshot,
        branches: [GitBranch],
        commits: [GitCommit],
        stashes: [GitStash]
    ) {
        let previousRoot = self.snapshot?.rootURL.path
        self.snapshot = snapshot
        self.branches = branches
        self.commits = commits
        self.stashes = stashes
        isRepositoryMissing = false
        hasMoreHistory = commits.count == Self.historyPageSize
        if previousRoot != snapshot.rootURL.path {
            commitMessage = commitDrafts[snapshot.rootURL.path] ?? ""
            selectedFiles = []
            selectedCommit = nil
            diff = nil
        } else {
            reconcileSelection(with: snapshot)
        }
    }

    private func reconcileSelection(with snapshot: GitRepositorySnapshot) {
        let currentByPath = Dictionary(uniqueKeysWithValues: snapshot.files.map { ($0.path, $0) })
        selectedFiles = Set(selectedFiles.compactMap { selection in
            guard let file = currentByPath[selection.file.path] else { return nil }
            if selection.comparison == .staged && !file.hasStagedChanges { return nil }
            if selection.comparison == .workingTree && !file.hasWorkingTreeChanges && !file.isUntracked { return nil }
            return GitFileSelection(file: file, comparison: selection.comparison)
        })
        if selectedFiles.count == 1 { selectionChanged() } else if selectedCommit == nil { diff = nil }
    }

    private func perform(
        _ label: String,
        refreshAfterward: Bool = true,
        operation: @escaping @MainActor (any GitClientProtocol) async throws -> Void
    ) {
        guard operationTask == nil else { return }
        refreshTask?.cancel()
        errorMessage = nil
        activity = .running(label)
        operationTask = Task { [weak self, client] in
            do {
                try await operation(client)
                guard let self else { return }
                self.operationTask = nil
                self.activity = .idle
                if refreshAfterward { self.refresh() }
            } catch is CancellationError {
                self?.operationTask = nil
                self?.activity = .idle
            } catch {
                guard let self else { return }
                self.operationTask = nil
                self.activity = .idle
                self.present(error)
                if refreshAfterward { self.refreshStatusWithoutClearingError() }
            }
        }
    }

    private func refreshStatusWithoutClearingError() {
        guard let root = snapshot?.rootURL else { return }
        Task { [weak self, client] in
            guard let updated = try? await client.snapshot(at: root) else { return }
            self?.snapshot = updated
        }
    }

    private func moveToTrash(_ urls: [URL]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.recycle(urls) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func present(_ error: Error) {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            errorMessage = description
        } else {
            errorMessage = error.localizedDescription
        }
    }

    func diffForMCP(path: String, staged: Bool) async throws -> GitDiff {
        let root = try await requireRootForMCP()
        let file = snapshot?.files.first { $0.path == path } ?? GitFileStatus(
            path: path,
            originalPath: nil,
            indexStatus: staged ? Character("M") : Character("."),
            workTreeStatus: staged ? Character(".") : Character("M"),
            kind: .modified
        )
        let selection = GitFileSelection(
            file: file,
            comparison: staged ? .staged : .workingTree
        )
        return try await client.diff(at: root, selection: selection)
    }

    func stageForMCP(paths: [String]) async throws {
        let root = try await requireRootForMCP()
        try await client.stage(paths: paths, at: root)
        await refreshNow()
    }

    func unstageForMCP(paths: [String]) async throws {
        let root = try await requireRootForMCP()
        try await client.unstage(paths: paths, at: root)
        await refreshNow()
    }

    func stageAllForMCP() async throws {
        let root = try await requireRootForMCP()
        try await client.stageAll(at: root)
        await refreshNow()
    }

    func commitForMCP(message: String) async throws {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ActionError.message("Commit message is empty.") }
        let root = try await requireRootForMCP()
        guard snapshot?.hasStagedChanges == true else {
            throw ActionError.message("Nothing is staged to commit.")
        }
        try await client.commit(message: trimmed, at: root)
        commitMessage = ""
        commitDrafts[root.path] = ""
        await refreshNow()
    }

    func fetchForMCP() async throws {
        let root = try await requireRootForMCP()
        try await client.fetch(at: root)
        await refreshNow()
    }

    func pullForMCP() async throws {
        guard canPull else { throw ActionError.message("Pull is not available.") }
        let root = try await requireRootForMCP()
        try await client.pull(at: root)
        await refreshNow()
    }

    func pushForMCP() async throws {
        guard canPush else { throw ActionError.message("Push is not available.") }
        let root = try await requireRootForMCP()
        try await client.push(at: root)
        await refreshNow()
    }

    func switchBranchForMCP(_ name: String) async throws {
        let root = try await requireRootForMCP()
        try await client.switchBranch(name, at: root)
        await refreshNow()
    }

    func createBranchForMCP(_ name: String, startPoint: String?) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ActionError.message("Branch name is empty.") }
        let root = try await requireRootForMCP()
        try await client.createBranch(trimmed, startPoint: startPoint, at: root)
        await refreshNow()
    }

    func discardForMCP(paths: [String]) async throws {
        let root = try await requireRootForMCP()
        try await client.discard(paths: paths, at: root)
        await refreshNow()
    }

    func deleteBranchForMCP(_ name: String) async throws {
        let root = try await requireRootForMCP()
        try await client.deleteBranch(name, at: root)
        await refreshNow()
    }

    func mergeForMCP(_ name: String) async throws {
        let root = try await requireRootForMCP()
        try await client.mergeBranch(name, at: root)
        await refreshNow()
    }

    func rebaseForMCP(_ name: String) async throws {
        let root = try await requireRootForMCP()
        try await client.rebase(onto: name, at: root)
        await refreshNow()
    }

    private func requireRootForMCP() async throws -> URL {
        if let root = snapshot?.rootURL { return root }
        guard let projectURL else { throw ActionError.noProject }
        guard let root = try await client.repositoryRoot(from: projectURL) else {
            throw ActionError.noRepository
        }
        return root
    }

    private func refreshNow(generation: UUID = UUID()) async {
        guard operationTask == nil else { return }
        refreshGeneration = generation

        guard let projectURL else {
            resetRepositoryState()
            return
        }

        activity = .refreshing
        errorMessage = nil
        do {
            guard let root = try await client.repositoryRoot(from: projectURL) else {
                guard refreshGeneration == generation else { return }
                snapshot = nil
                branches = []
                commits = []
                stashes = []
                diff = nil
                isRepositoryMissing = true
                activity = .idle
                return
            }

            async let loadedSnapshot = client.snapshot(at: root)
            async let loadedBranches = client.branches(at: root)
            async let loadedCommits = client.history(at: root, offset: 0, limit: Self.historyPageSize)
            async let loadedStashes = client.stashes(at: root)
            let values = try await (loadedSnapshot, loadedBranches, loadedCommits, loadedStashes)

            guard refreshGeneration == generation, !Task.isCancelled else { return }
            apply(snapshot: values.0, branches: values.1, commits: values.2, stashes: values.3)
            activity = .idle
        } catch is CancellationError {
            return
        } catch {
            guard refreshGeneration == generation else { return }
            present(error)
            activity = .idle
        }
    }

    private func resetRepositoryState() {
        refreshTask?.cancel()
        diffTask?.cancel()
        snapshot = nil
        branches = []
        commits = []
        stashes = []
        diff = nil
        selectedFiles = []
        selectedCommit = nil
        commitMessage = ""
        isRepositoryMissing = false
        hasMoreHistory = false
        activity = .idle
        errorMessage = nil
    }
}

extension SourceControlViewModel {
    enum ActionError: LocalizedError {
        case noProject
        case noRepository
        case confirmationRequired
        case message(String)

        var errorDescription: String? {
            switch self {
            case .noProject: "Open a Flutter project first."
            case .noRepository: "This project is not a Git repository."
            case .confirmationRequired: "This destructive Git action requires confirm=true."
            case let .message(text): text
            }
        }
    }
}

extension Notification.Name {
    static let showSourceControlSheet = Notification.Name("showSourceControlSheet")
}
