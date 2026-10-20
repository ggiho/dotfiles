import AppKit
setbuf(stdout, nil)
// Prints one line per app activation: "activate\t<app name>". Used by wsbar.py to notice when a
// click on the Dock / Cmd+Tab activates an app but AeroSpace then sends the focus somewhere else.
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { n in
    let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    print("activate\t\(app?.localizedName ?? "?")")
}
RunLoop.main.run()
