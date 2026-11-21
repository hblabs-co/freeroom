// Prints the CGWindowID of the largest on-screen window of an app (for screencapture -l).
// Usage: swift scripts/window-id.swift Freeroom [--any-layer]   (--any-layer: include popovers/panels)
import CoreGraphics
import Foundation

let args = CommandLine.arguments.dropFirst()
let owner = args.first { !$0.hasPrefix("--") } ?? "Freeroom"
let anyLayer = args.contains("--any-layer")
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = list.filter { ($0[kCGWindowOwnerName as String] as? String) == owner && (anyLayer || ($0[kCGWindowLayer as String] as? Int) == 0) }
func area(_ w: [String: Any]) -> Double {
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    return (b["Width"] ?? 0) * (b["Height"] ?? 0)
}
if let best = windows.max(by: { area($0) < area($1) }), let id = best[kCGWindowNumber as String] as? Int {
    print(id)
} else {
    exit(1)
}
