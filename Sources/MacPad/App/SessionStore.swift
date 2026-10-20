import AppKit

/// Open windows and tabs as saved to disk, Notepad++ "session snapshot" style.
struct Session: Codable, Equatable {
    struct Window: Codable, Equatable {
        var frame: String?
        var selectedTab: Int
        var tabs: [Tab]
    }

    struct Tab: Codable, Equatable {
        /// File path; nil for untitled documents.
        var path: String?
        /// File name in the backup directory holding unsaved content.
        var backup: String?
        var encoding: String
        var lineEnding: String
        var language: String
        var viewState: ScintillaEditor.ViewState
        var wrapsLines: Bool
        // Added in 0.4; absent from older sessions.
        /// N of "Untitled N", kept so names don't change across launches.
        var untitledNumber: Int?
        /// A name given with Rename to an untitled document.
        var name: String?
        var pinned: Bool?
        var color: String?
        var readOnly: Bool?
        /// The file was being followed (tail -f).
        var follow: Bool?
    }

    var windows: [Window] = []
}

/// Saves the session (and backups of unsaved content) periodically and on quit,
/// and reopens it at launch, so quitting never asks to save.
@MainActor
final class SessionStore {
    static let shared = SessionStore()

    private let directory: URL
    private var sessionURL: URL { directory.appending(path: "session.json") }
    private var backupDirectory: URL { directory.appending(path: "Backups", directoryHint: .isDirectory) }

    /// Backup file name and the editor content version it holds, per document.
    private var backups: [ObjectIdentifier: (name: String, version: Int)] = [:]
    private var timer: Timer?

    /// Notepad++ backs up every 7 seconds by default.
    static let backupInterval: TimeInterval = 7

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "MacPad++", directoryHint: .isDirectory)
    }

    // MARK: Saving

    func startPeriodicBackups() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.backupInterval, repeats: true) { _ in
            MainActor.assumeIsolated {
                if Preferences.restoreSession { SessionStore.shared.save() }
            }
        }
    }

    /// Writes session.json plus a backup for every document with unsaved changes.
    func save() {
        do {
            try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            let session = capture()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(session).write(to: sessionURL, options: .atomic)
            removeOrphanedBackups(keeping: Set(session.windows.flatMap(\.tabs).compactMap(\.backup)))
        } catch {
            NSLog("MacPad++: could not save session: \(error)")
        }
    }

    private func capture() -> Session {
        var session = Session()
        var seenGroups = Set<ObjectIdentifier>()
        var liveDocuments = Set<ObjectIdentifier>()

        // Front-to-back window order; each tab group is saved once, in tab order.
        for window in NSApp.orderedWindows where window.windowController is DocumentWindowController {
            let tabWindows = window.tabGroup?.windows ?? [window]
            let groupID = ObjectIdentifier(window.tabGroup ?? window)
            guard seenGroups.insert(groupID).inserted else { continue }

            var tabs: [Session.Tab] = []
            var selectedTab = 0
            for tabWindow in tabWindows {
                guard let document = tabWindow.windowController?.document as? TextDocument,
                      let tab = capture(document)
                else { continue }
                liveDocuments.insert(ObjectIdentifier(document))
                if tabWindow == (window.tabGroup?.selectedWindow ?? window) {
                    selectedTab = tabs.count
                }
                tabs.append(tab)
            }
            if !tabs.isEmpty {
                session.windows.append(Session.Window(frame: NSStringFromRect(window.frame), selectedTab: selectedTab, tabs: tabs))
            }
        }
        backups = backups.filter { liveDocuments.contains($0.key) }
        return session
    }

    private func capture(_ document: TextDocument) -> Session.Tab? {
        guard let editor = document.editor else { return nil }
        // Untitled documents with nothing typed are not worth restoring.
        if document.fileURL == nil, !document.isDocumentEdited { return nil }

        var backupName: String?
        if document.isDocumentEdited, !document.isFollowing {
            let id = ObjectIdentifier(document)
            let name = backups[id]?.name ?? "\(UUID().uuidString).txt"
            if backups[id]?.version != editor.contentVersion {
                do {
                    try editor.utf8Text().write(to: backupDirectory.appending(path: name), options: .atomic)
                    backups[id] = (name, editor.contentVersion)
                } catch {
                    NSLog("MacPad++: could not back up \(document.displayName ?? "document"): \(error)")
                }
            }
            backupName = name
        }

        return Session.Tab(
            path: document.fileURL?.path,
            backup: backupName,
            encoding: document.format.encoding.rawValue,
            lineEnding: document.format.lineEnding.rawValue,
            language: editor.language.id,
            viewState: editor.viewState,
            wrapsLines: editor.wrapsLines,
            untitledNumber: document.fileURL == nil ? document.untitledNumber : nil,
            name: document.fileURL == nil ? document.customName : nil,
            pinned: document.isPinned ? true : nil,
            color: document.tabColor?.rawValue,
            readOnly: document.isReadOnly ? true : nil,
            follow: document.isFollowing ? true : nil)
    }

    private func removeOrphanedBackups(keeping names: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !names.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: Restoring

    /// Reopens the saved session. Returns true if at least one tab was opened.
    @discardableResult
    func restore() -> Bool {
        guard let data = try? Data(contentsOf: sessionURL),
              let session = try? JSONDecoder().decode(Session.self, from: data)
        else { return false }

        var restoredAny = false
        var selectedWindows: [NSWindow] = []
        for savedWindow in session.windows.reversed() {
            var groupWindows: [NSWindow] = []
            for tab in savedWindow.tabs {
                guard let window = open(tab) else { continue }
                if let last = groupWindows.last {
                    last.addTabbedWindow(window, ordered: .above)
                } else {
                    // Start a new window instead of joining the frontmost tab group.
                    window.tabbingMode = .disallowed
                    if let frame = savedWindow.frame {
                        window.setFrame(NSRectFromString(frame), display: false)
                    }
                    window.windowController?.showWindow(nil)
                    window.tabbingMode = .preferred
                }
                groupWindows.append(window)
                restoredAny = true
            }
            if groupWindows.indices.contains(savedWindow.selectedTab) {
                selectedWindows.append(groupWindows[savedWindow.selectedTab])
            } else if let first = groupWindows.first {
                selectedWindows.append(first)
            }
        }
        // Windows were opened back to front; bring each group's selected tab forward.
        for window in selectedWindows {
            window.makeKeyAndOrderFront(nil)
        }
        return restoredAny
    }

    private func open(_ tab: Session.Tab) -> NSWindow? {
        let controller = NSDocumentController.shared
        let fileURL = tab.path.map { URL(filePath: $0) }
        let fileExists = fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        let backup = tab.backup.flatMap { try? Data(contentsOf: backupDirectory.appending(path: $0)) }
        guard fileExists || backup != nil else { return nil }

        let document: TextDocument
        do {
            if let fileURL, fileExists {
                let type = try controller.typeForContents(of: fileURL)
                guard let opened = try controller.makeDocument(withContentsOf: fileURL, ofType: type) as? TextDocument else { return nil }
                document = opened
            } else {
                // The file is gone but unsaved content survives: reopen it as untitled.
                guard let type = controller.defaultType,
                      let untitled = try controller.makeUntitledDocument(ofType: type) as? TextDocument
                else { return nil }
                document = untitled
            }
        } catch {
            NSLog("MacPad++: could not reopen \(tab.path ?? "untitled document"): \(error)")
            return nil
        }

        document.untitledNumber = tab.untitledNumber
        document.customName = tab.name
        document.isPinned = tab.pinned ?? false
        document.tabColor = tab.color.flatMap(TabColor.init(rawValue:))
        document.isReadOnly = tab.readOnly ?? false
        controller.addDocument(document)
        document.makeWindowControllers()
        guard let window = document.windowControllers.first?.window, let editor = document.editor else { return nil }

        if let backup, let name = tab.backup {
            // Unsaved content keeps the format it was being edited with.
            document.format = TextFormat(
                encoding: TextEncoding(rawValue: tab.encoding) ?? document.format.encoding,
                lineEnding: LineEnding(rawValue: tab.lineEnding) ?? document.format.lineEnding)
            editor.replaceText(utf8: backup)
            editor.setLineEnding(document.format.lineEnding, convertExisting: false)
            backups[ObjectIdentifier(document)] = (name, editor.contentVersion)
        }
        if let language = Language.with(id: tab.language) {
            editor.setLanguage(language)
        }
        editor.wrapsLines = tab.wrapsLines
        // Scrolling needs the final layout, which happens once the window is shown.
        let editorController = (document.windowControllers.first as? DocumentWindowController)?.editorController
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if tab.follow == true, tab.backup == nil {
                    editorController?.startFollowing()
                } else {
                    editor.viewState = tab.viewState
                }
            }
        }
        return window
    }
}
