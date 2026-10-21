import CoreGraphics
import Foundation

// winframes            print "<window id> <x> <y> <w> <h>" for every on-screen normal window.
// winframes --watch    stay running and print "change" whenever a window appears or disappears (the set of
//                      ids, not their positions). AeroSpace has no event for a closed window, and starting
//                      this program for every look costs more than looking inside one process.
func onScreenWindows() -> [(id: Int, rect: CGRect)]? {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
    var out = [(id: Int, rect: CGRect)]()
    for window in windows {
        guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
              let number = window[kCGWindowNumber as String] as? Int,
              let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
        out.append((number, bounds))
    }
    return out
}

if CommandLine.arguments.contains("--watch") {
    setbuf(stdout, nil)
    var previous: Set<Int>? = nil
    while true {
        autoreleasepool {
            if let w = onScreenWindows() {
                let ids = Set(w.map { $0.id })
                if let p = previous, p != ids { print("change") }
                previous = ids
            }
        }
        usleep(400_000)
    }
}

guard let windows = onScreenWindows() else { exit(1) }
for w in windows {
    print(w.id, Int(w.rect.origin.x), Int(w.rect.origin.y), Int(w.rect.width), Int(w.rect.height))
}
