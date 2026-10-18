import AppKit

// The first document controller created becomes the shared one.
_ = DocumentController()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.mainMenu = MainMenu.build()
app.run()
