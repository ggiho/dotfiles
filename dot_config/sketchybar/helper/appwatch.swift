import AppKit
setbuf(stdout, nil)
// Prints one line per app event for wsbar.py:
//   activate\t<app name>   an app became the frontmost one (to notice when a click on the Dock / Cmd+Tab
//                          activates an app but AeroSpace then sends the focus somewhere else)
//   terminate\t<app name>  an app quit (AeroSpace has no event for closed windows, so the bar would
//                          only find out at its next periodic check)
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil) { n in
    let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    print("activate\t\(app?.localizedName ?? "?")")
}
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: nil) { n in
    let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    print("terminate\t\(app?.localizedName ?? "?")")
}
RunLoop.main.run()
