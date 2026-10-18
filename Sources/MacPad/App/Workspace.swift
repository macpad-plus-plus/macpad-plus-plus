import AppKit
import CoreServices

/// Folders opened with File ▸ Open Folder…, shown in every window's sidebar
/// (Notepad++'s "Folder as Workspace").
@MainActor
final class Workspace {
    static let shared = Workspace()
    static let didChange = Notification.Name("MacPadWorkspaceDidChange")
    /// Posted when files inside a workspace folder change on disk.
    static let contentsDidChange = Notification.Name("MacPadWorkspaceContentsDidChange")

    private static let foldersKey = "workspaceFolders"

    private(set) var folders: [URL]
    private var watcher: DirectoryWatcher?

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.foldersKey) ?? []
        folders = paths.map { URL(filePath: $0, directoryHint: .isDirectory) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        watch()
    }

    func add(_ folder: URL) {
        let folder = folder.standardizedFileURL
        guard !folders.contains(folder) else { return }
        folders.append(folder)
        save()
        NSDocumentController.shared.noteNewRecentDocumentURL(folder)
    }

    func remove(_ folder: URL) {
        folders.removeAll { $0 == folder }
        save()
    }

    /// File ▸ Open Folder…
    func chooseFolder(for window: NSWindow?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add to Workspace")
        panel.message = String(localized: "Choose folders to show in the sidebar.")
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            MainActor.assumeIsolated {
                panel.urls.forEach(self.add)
            }
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(panel.runModal())
        }
    }

    private func save() {
        UserDefaults.standard.set(folders.map(\.path), forKey: Self.foldersKey)
        watch()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private func watch() {
        watcher = folders.isEmpty ? nil : DirectoryWatcher(paths: folders.map(\.path)) {
            NotificationCenter.default.post(name: Workspace.contentsDidChange, object: Workspace.shared)
        }
    }
}

/// Coalesced FSEvents notifications for a set of directory trees.
final class DirectoryWatcher {
    private var stream: FSEventStreamRef?
    private let handler: @MainActor () -> Void

    init(paths: [String], handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        // Events are delivered on the main queue (see FSEventStreamSetDispatchQueue).
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            nonisolated(unsafe) let pointer = info
            MainActor.assumeIsolated {
                Unmanaged<DirectoryWatcher>.fromOpaque(pointer).takeUnretainedValue().handler()
            }
        }
        stream = FSEventStreamCreate(
            nil, callback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5,
            UInt32(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
