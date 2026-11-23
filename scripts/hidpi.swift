// Switches the main display to a HiDPI mode (2x) while this process runs; macOS restores the
// previous mode when it exits. Used by screenshots.sh so captures are sharp on Retina screens even
// on a 1x monitor. Prints "ready" once the mode is active.
import CoreGraphics
import Foundation

let display = CGMainDisplayID()
let current = CGDisplayCopyDisplayMode(display)!
let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
let modes = (CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode]) ?? []
// Largest 2x mode whose pixels are the panel's native pixels (or the largest 2x mode at all).
let hidpi = modes.filter { $0.pixelWidth == 2 * $0.width }
guard let mode = hidpi.filter({ $0.pixelWidth == current.pixelWidth }).max(by: { $0.refreshRate < $1.refreshRate })
        ?? hidpi.max(by: { $0.pixelWidth < $1.pixelWidth })
else { FileHandle.standardError.write("no HiDPI mode\n".data(using: .utf8)!); exit(1) }
if current.pixelWidth == 2 * current.width { print("ready"); fflush(stdout) } else {
    var config: CGDisplayConfigRef?
    CGBeginDisplayConfiguration(&config)
    CGConfigureDisplayWithDisplayMode(config, display, mode, nil)
    guard CGCompleteDisplayConfiguration(config, .forAppOnly) == .success else { exit(1) }
    print("ready"); fflush(stdout)
}
signal(SIGTERM) { _ in exit(0) }
signal(SIGINT) { _ in exit(0) }
while true { sleep(60) }
