import CoreGraphics
import Foundation

// Print "<window id> <x> <y> <w> <h>" for every on-screen normal window.
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { exit(1) }

for window in windows {
    guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
          let number = window[kCGWindowNumber as String] as? Int,
          let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
          let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
    print(number, Int(bounds.origin.x), Int(bounds.origin.y), Int(bounds.width), Int(bounds.height))
}
