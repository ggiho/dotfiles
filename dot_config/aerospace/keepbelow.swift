import ApplicationServices
import CoreGraphics
import Foundation

// keepbelow   (run by aerospace.toml when a window is detected)
//
// The bar is drawn over the top of the screen, and a new floating window often opens there, with its
// close button under the bar. This moves such windows down to where the tiled windows start (a window
// that is already below the bar is left where it is). Only floating windows are touched: tiled ones are
// placed by AeroSpace itself.
// Waits a moment first: apps place their window a little after it is created. Only windows that reach
// above the line are moved, and only down; full-screen windows are left alone.
//
// KEEPBELOW_DRY=1 only prints what would be done.

let dry = ProcessInfo.processInfo.environment["KEEPBELOW_DRY"] != nil
let waits: [useconds_t] = dry ? [0] : [600_000, 1_400_000]       // look again later: some apps move late

// where the tiled windows start, counted from the top of a screen: [gaps] outer.top in aerospace.toml
// (the notched built-in screen is 28 for the notch + 10, the others 38)
let inset: CGFloat = 38

// ids of the floating windows on the visible workspaces; only those are ever moved
func floatingIds() -> Set<Int>? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/aerospace")
    p.arguments = ["list-windows", "--workspace", "visible", "--format", "%{window-id}|%{window-layout}"]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    var out = Set<Int>()
    for line in (String(data: data, encoding: .utf8) ?? "").split(separator: "\n") {
        let f = line.split(separator: "|")
        if f.count == 2, f[1] == "floating", let id = Int(f[0]) { out.insert(id) }
    }
    return out
}

func displays() -> [(id: CGDirectDisplayID, bounds: CGRect)] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 16)
    var n: UInt32 = 0
    CGGetActiveDisplayList(16, &ids, &n)
    return ids.prefix(Int(n)).map { ($0, CGDisplayBounds($0)) }
}

func sweep() {
    let screens = displays()
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    // First only look at the frames: in nearly every run nothing reaches under the bar, and then AeroSpace
    // is not asked anything (each question costs it ~40 ms of its main thread).
    var over = [(id: Int, pid: Int32, name: String, r: CGRect, line: CGFloat)]()
    for w in list {
        guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
              let id = w[kCGWindowNumber as String] as? Int,
              let pid = w[kCGWindowOwnerPID as String] as? Int32,
              let b = w[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b as CFDictionary),
              r.width > 80, r.height > 80,
              let s = screens.first(where: { $0.bounds.contains(CGPoint(x: r.midX, y: r.minY + 1)) }) else { continue }
        // down to the tiled start, but not so far that the bottom edge leaves the screen
        let line = min(s.bounds.minY + inset, s.bounds.maxY - r.height)
        if r.minY >= s.bounds.minY + inset - 8 || line <= r.minY { continue }      // below the bar already (the 8 is the gap under it)
        if r.width >= s.bounds.width - 2 && r.height >= s.bounds.height - 2 { continue }        // full screen
        over.append((id, pid, w[kCGWindowOwnerName as String] as? String ?? "?", r, line))
    }
    if over.isEmpty { return }
    guard let floating = floatingIds() else { return }
    for o in over where floating.contains(o.id) {
        if dry { print("\(o.name) top \(Int(o.r.minY)) -> \(Int(o.line))"); continue }
        // find the window of that app with the same frame and move it
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(o.pid), kAXWindowsAttribute as CFString, &ref) == .success,
              let wins = ref as? [AXUIElement] else { continue }
        for win in wins {
            var pv: CFTypeRef?, sv: CFTypeRef?
            var p = CGPoint.zero, sz = CGSize.zero
            guard AXUIElementCopyAttributeValue(win, kAXPositionAttribute as CFString, &pv) == .success,
                  AXUIElementCopyAttributeValue(win, kAXSizeAttribute as CFString, &sv) == .success,
                  AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &sz),
                  abs(p.x - o.r.minX) < 2, abs(p.y - o.r.minY) < 2, abs(sz.width - o.r.width) < 2 else { continue }
            var to = CGPoint(x: p.x, y: o.line)
            if let v = AXValueCreate(.cgPoint, &to) { AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, v) }
            break
        }
    }
}

for w in waits {
    usleep(w)
    sweep()
}
