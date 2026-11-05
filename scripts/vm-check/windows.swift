// Lists on-screen windows of a process (no Screen Recording needed for owner/bounds).
// usage: swift windows.swift [ownerName]   (run in the GUI session)
import CoreGraphics
import Foundation
let owner = CommandLine.arguments.dropFirst().first
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where owner == nil || (w[kCGWindowOwnerName as String] as? String) == owner {
    print(w[kCGWindowOwnerName as String] ?? "?", w[kCGWindowLayer as String] ?? "?",
          w[kCGWindowIsOnscreen as String] ?? false, w[kCGWindowBounds as String] ?? "?")
}
print("count:", list.count, "AXTrusted: n/a")
