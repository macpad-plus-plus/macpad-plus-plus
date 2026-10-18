import AppKit

/// Notices when another app changes or deletes an open file, and asks what to
/// do, as Notepad++ does when it regains focus.
extension TextDocument {
    enum ExternalChange: Equatable {
        /// The file on disk is newer than what was loaded or last saved.
        case modified
        /// The file is gone (deleted, or moved somewhere AppKit could not follow).
        case deleted
    }

    /// Compares the file on disk with the version this document last read or wrote.
    func externalChange() -> ExternalChange? {
        guard let fileURL else { return nil }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .deleted }
        guard let onDisk = Self.modificationDate(of: fileURL), let known = fileModificationDate else { return nil }
        return onDisk.timeIntervalSince(known) > 0.001 ? .modified : nil
    }

    /// Read from the file system each time: URL.resourceValues caches per URL instance.
    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Checks for an external change and, if there is one, asks the user in a sheet.
    @MainActor
    func checkForExternalChanges(in window: NSWindow) {
        guard !isPresentingExternalChangeAlert, window.attachedSheet == nil,
              let change = externalChange(), let fileURL
        else { return }
        // Ask once per change: after an answer the document matches the disk again,
        // or the user chose to keep their version.
        isPresentingExternalChangeAlert = true
        let name = fileURL.lastPathComponent
        let alert = NSAlert()
        alert.alertStyle = .warning
        // One action per button, in button order.
        let actions: [(title: String, run: () -> Void)]

        switch change {
        case .modified:
            alert.messageText = String(localized: "“\(name)” was changed by another app.")
            alert.informativeText = isDocumentEdited
                ? String(localized: "Reload it from disk? Your unsaved changes in MacPad++ will be lost.")
                : String(localized: "Reload it from disk to see the changes?")
            actions = [
                (String(localized: "Reload"), reloadFromDisk),
                (String(localized: "Keep This Version"), keepThisVersion),
                (String(localized: "Close"), close),
            ]
        case .deleted:
            alert.messageText = String(localized: "“\(name)” no longer exists on disk.")
            alert.informativeText = String(localized: "It was deleted or moved by another app. Save it again to keep it, or close it.")
            actions = [
                (String(localized: "Save"), { self.saveAgain(to: fileURL) }),
                (String(localized: "Save As…"), { self.saveAs(nil) }),
                (String(localized: "Close Without Saving"), close),
            ]
        }

        for action in actions {
            alert.addButton(withTitle: action.title)
        }
        alert.buttons.last?.hasDestructiveAction = change == .deleted
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                self.isPresentingExternalChangeAlert = false
                let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
                if actions.indices.contains(index) { actions[index].run() }
            }
        }
    }

    /// Writes the document back where the deleted file was.
    private func saveAgain(to url: URL) {
        save(to: url, ofType: fileType ?? "public.plain-text", for: .saveOperation) { error in
            if let error { self.presentError(error) }
        }
    }

    /// Replaces the buffer with the file on disk.
    private func reloadFromDisk() {
        guard let fileURL, let fileType else { return }
        do {
            try revert(toContentsOf: fileURL, ofType: fileType)
        } catch {
            presentError(error)
        }
    }

    /// Keeps the editor's text; the document now differs from the file, so it
    /// counts as edited and saving overwrites the other app's changes.
    private func keepThisVersion() {
        guard let fileURL else { return }
        fileModificationDate = Self.modificationDate(of: fileURL)
        updateChangeCount(.changeDone)
    }
}
