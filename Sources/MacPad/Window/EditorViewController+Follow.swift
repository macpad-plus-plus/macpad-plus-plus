import AppKit

/// Following a file like `tail -f` (View ▸ Follow File), as Notepad++'s
/// Monitoring and OxyPad's log mode do: the document becomes read-only, what
/// is appended to the file shows up at the end, the view stays at the
/// bottom unless scrolled up, and error, warning and debug lines are colored.
/// Following survives the file being truncated or rotated.
extension EditorViewController {
    /// How often the file is looked at.
    static let followInterval: TimeInterval = 0.25
    /// How much of the end of a file is shown when following starts.
    static let followInitialBytes = 2 * 1024 * 1024
    /// Older lines are dropped from the top beyond this.
    static let followMaxLines = 200_000

    /// What the status bar says about following.
    enum FollowStatus: Equatable {
        case following, paused, truncated, rotated
    }

    @objc func toggleFollow(_ sender: Any?) {
        guard let document else { return }
        if document.isFollowing {
            stopFollowing()
        } else {
            startFollowing()
        }
    }

    /// Starts following the document's file; asks to save first when there
    /// are changes, since the file is what is followed.
    func startFollowing() {
        guard let document, let window = view.window else { return }
        guard let url = document.fileURL, !document.isDocumentEdited else {
            let alert = NSAlert()
            alert.messageText = String(localized: "Save the file before following it.")
            alert.informativeText = document.fileURL == nil
                ? String(localized: "Only a file on disk can be followed.")
                : String(localized: "Following shows the file as other apps write it, so your unsaved changes would be lost.")
            alert.addButton(withTitle: String(localized: "OK"))
            alert.beginSheetModal(for: window)
            return
        }
        let follower: LogFollower
        let text: Data
        do {
            (follower, text) = try LogFollower.open(url, initialBytes: Self.followInitialBytes)
        } catch {
            presentError(error)
            return
        }
        editor.collectsUndo = false
        editor.load(utf8: decoded(text), lineEnding: document.format.lineEnding)
        editor.colorLogLevels(from: 0)
        document.isFollowing = true
        followStatus = .following
        editor.scrollToEnd()
        startPolling(follower)
        refreshStatus()
    }

    /// Stops following, and shows the whole file again so it can be edited.
    func stopFollowing() {
        guard let document, document.isFollowing else { return }
        followTimer?.cancel()
        followTimer = nil
        document.isFollowing = false
        followStatus = nil
        editor.clearLogLevels()
        editor.collectsUndo = true
        if let url = document.fileURL, let type = document.fileType {
            try? document.revert(toContentsOf: url, ofType: type)
        }
        refreshStatus()
    }

    private func startPolling(_ follower: LogFollower) {
        let queue = DispatchQueue(label: "MacPad.follow", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.followInterval, repeating: Self.followInterval, leeway: .milliseconds(50))
        timer.setEventHandler(handler: Self.pollHandler(follower, owner: self, timer: timer))
        followTimer = timer
        timer.resume()
    }

    /// Runs on the follow queue. Built outside the main actor: a closure
    /// written in a main-actor method would be checked to run on it, and trap.
    private nonisolated static func pollHandler(
        _ follower: LogFollower, owner: EditorViewController, timer: DispatchSourceTimer
    ) -> @Sendable () -> Void {
        { [weak owner, weak timer] in
            guard owner != nil else {
                // The tab was closed.
                timer?.cancel()
                return
            }
            guard let event = try? follower.poll() else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { owner?.apply(event) }
            }
        }
    }

    private func apply(_ event: LogFollower.Event) {
        guard let document, document.isFollowing else { return }
        switch event {
        case .appended(let data):
            let atEnd = editor.isScrolledToEnd
            let start = editor.length
            editor.appendWithoutUndo(utf8: decoded(data))
            // Colored before old lines go, while `start` still points at the new text.
            editor.colorLogLevels(from: start)
            editor.dropOldLines(keeping: Self.followMaxLines)
            followStatus = atEnd ? .following : .paused
            if atEnd { editor.scrollToEnd() }
        case .reset(let data, let reason):
            editor.load(utf8: decoded(data), lineEnding: document.format.lineEnding)
            editor.colorLogLevels(from: 0)
            followStatus = reason == .truncated ? .truncated : .rotated
            editor.scrollToEnd()
        }
        // The file changed under the document on purpose: not an external change.
        document.acceptDiskVersion()
        refreshStatus()
    }

    /// File bytes as the editor's UTF-8, from the document's encoding.
    private func decoded(_ data: Data) -> Data {
        guard let encoding = document?.format.encoding, encoding != .utf8, encoding != .utf8BOM else { return data }
        return (String(data: data, encoding: encoding.stringEncoding) ?? String(decoding: data, as: UTF8.self)).data(using: .utf8) ?? data
    }

    /// The status bar's text for following, or nil when not following.
    var followStatusText: String? {
        switch followStatus {
        case .following: String(localized: "Following")
        case .paused: String(localized: "Following: paused while scrolled up")
        case .truncated: String(localized: "Following (the file was truncated)")
        case .rotated: String(localized: "Following (the file was rotated)")
        case nil: nil
        }
    }
}
