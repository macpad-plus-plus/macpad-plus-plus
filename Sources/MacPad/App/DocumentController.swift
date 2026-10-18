import AppKit

/// Quits without "Do you want to save?" prompts, like Notepad++: unsaved
/// content is written to the session backups instead and restored at launch.
/// With session restore turned off in Settings, the usual prompts apply.
///
/// Being the first NSDocumentController created makes it the shared instance.
final class DocumentController: NSDocumentController {
    override func reviewUnsavedDocuments(
        withAlertTitle title: String?, cancellable: Bool, delegate: Any?,
        didReviewAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?
    ) {
        // Only reached when quitting (or logging out / restarting).
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        guard Preferences.restoreSession, !isRunningTests else {
            return super.reviewUnsavedDocuments(
                withAlertTitle: title, cancellable: cancellable, delegate: delegate,
                didReviewAllSelector: didReviewAllSelector, contextInfo: contextInfo)
        }
        SessionStore.shared.save()
        for document in documents where document.isDocumentEdited {
            document.updateChangeCount(.changeCleared)
        }
        super.reviewUnsavedDocuments(
            withAlertTitle: title, cancellable: cancellable, delegate: delegate,
            didReviewAllSelector: didReviewAllSelector, contextInfo: contextInfo)
    }
}
