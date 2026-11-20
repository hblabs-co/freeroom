import Darwin
import Foundation

/// Result of measuring one root path.
public struct DiskMeasurement: Codable, Equatable, Sendable {
    public struct Child: Codable, Equatable, Sendable {
        public var path: String
        public var allocatedBytes: Int64
    }

    public var path: String
    public var exists: Bool
    /// Bytes actually allocated on disk, each inode counted once across the whole measurement.
    public var allocatedBytes: Int64
    /// Part of `allocatedBytes` held by files that also have hard links *outside* the measured
    /// paths (e.g. pnpm's content-addressable store). Deleting the path will not free these bytes.
    public var sharedBytes: Int64
    public var fileCount: Int
    public var directoryCount: Int
    /// Directories on another volume that were not entered (mounted disk images, network shares…).
    public var skippedMounts: [String]
    /// Entries that could not be read (usually missing Full Disk Access).
    public var unreadableCount: Int
    /// Largest first-level children, when requested.
    public var children: [Child]?

    /// Best estimate of the space freed by deleting this path.
    public var reclaimableBytes: Int64 { max(0, allocatedBytes - sharedBytes) }
}

public struct MeasureReport: Codable, Equatable, Sendable {
    public var items: [DiskMeasurement]
    /// Sum over all items with each inode counted once (items may overlap or share hard links).
    public var totalAllocatedBytes: Int64
    public var totalSharedBytes: Int64
    public var totalReclaimableBytes: Int64 { max(0, totalAllocatedBytes - totalSharedBytes) }
}

/// Measures real disk usage, avoiding the classic `du` pitfalls:
///
/// * **Hard links** are counted once (by device + inode), across *all* roots of one call.
/// * Hard links that point **outside** the measured roots are reported as `sharedBytes`,
///   because deleting the root does not free them.
/// * **Other volumes** (mounted DMGs such as Xcode simulator runtimes, network shares) are not
///   entered; they are listed in `skippedMounts` instead of being double counted.
/// * **Symlinks** are never followed.
///
/// Known limitation: APFS clones (`cp -c`) share blocks invisibly and are counted in full,
/// exactly like Finder and `du` do.
public struct Measurer: Sendable {
    public var topChildren: Int

    /// Every mount point except "/". Needed because APFS volume groups report the same st_dev for
    /// the system and data volumes (e.g. /System and /System/Volumes/Data), so a device check alone
    /// would walk into the data volume and count the whole disk again.
    public static let mountPoints: Set<String> = {
        var buffer: UnsafeMutablePointer<statfs>?
        let count = getmntinfo(&buffer, MNT_NOWAIT)
        guard count > 0, let buffer else { return [] }
        var points = Set<String>()
        for i in 0..<Int(count) {
            var entry = buffer[i]
            let path = withUnsafePointer(to: &entry.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
            if path != "/" { points.insert(path) }
        }
        return points
    }()

    public init(topChildren: Int = 0) {
        self.topChildren = topChildren
    }

    private struct InodeKey: Hashable {
        let dev: Int32
        let ino: UInt64
    }

    private struct InodeInfo {
        let root: Int
        let allocated: Int64
        let links: Int
        var seen: Int
    }

    public func measure(_ paths: [String]) -> MeasureReport {
        let roots = paths.map { PathUtils.expand($0) }
        // Roots that are equal to or inside another root would be counted twice in the total.
        // Measure each item on its own, and the total from the outermost roots only.
        var outermost: [String] = []
        for (i, root) in roots.enumerated() {
            let covered = roots.enumerated().contains { j, other in
                j != i && (root.hasPrefix(other + "/") || (root == other && j < i))
            }
            if !covered { outermost.append(root) }
        }
        guard outermost.count < roots.count else { return walk(roots) }
        let items = roots.map { walk([$0]).items[0] }
        let total = walk(outermost)
        return MeasureReport(items: items, totalAllocatedBytes: total.totalAllocatedBytes,
                             totalSharedBytes: total.totalSharedBytes)
    }

    private func walk(_ roots: [String]) -> MeasureReport {
        var items: [DiskMeasurement] = roots.map {
            DiskMeasurement(path: $0, exists: false, allocatedBytes: 0, sharedBytes: 0,
                        fileCount: 0, directoryCount: 0, skippedMounts: [], unreadableCount: 0,
                        children: nil)
        }
        var childSizes: [[String: Int64]] = Array(repeating: [:], count: roots.count)
        var inodes: [InodeKey: InodeInfo] = [:]
        var totalAllocated: Int64 = 0

        for (index, root) in roots.enumerated() {
            var rootStat = stat()
            guard lstat(root, &rootStat) == 0 else { continue }
            items[index].exists = true
            let rootDev = rootStat.st_dev

            var cPaths: [UnsafeMutablePointer<CChar>?] = [strdup(root), nil]
            defer { cPaths.forEach { free($0) } }
            guard let fts = fts_open(&cPaths, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
                items[index].unreadableCount += 1
                continue
            }
            defer { fts_close(fts) }

            var currentChild: String?
            while let entry = fts_read(fts) {
                let info = Int32(entry.pointee.fts_info)
                let level = Int(entry.pointee.fts_level)
                let path = String(cString: entry.pointee.fts_path)

                if level == 1 { currentChild = path }

                switch info {
                case FTS_DP:
                    continue // post-order visit of a directory already counted
                case FTS_DNR, FTS_ERR, FTS_NS:
                    items[index].unreadableCount += 1
                    continue
                default:
                    break
                }

                guard let st = entry.pointee.fts_statp?.pointee else { continue }

                if info == FTS_D {
                    if level > 0 && (st.st_dev != rootDev || Self.mountPoints.contains(path)) {
                        items[index].skippedMounts.append(path)
                        fts_set(fts, entry, FTS_SKIP)
                        continue
                    }
                    items[index].directoryCount += 1
                } else {
                    items[index].fileCount += 1
                }

                let allocated = Int64(st.st_blocks) * 512
                var counted = allocated

                if info != FTS_D && st.st_nlink > 1 {
                    let key = InodeKey(dev: st.st_dev, ino: st.st_ino)
                    if var known = inodes[key] {
                        known.seen += 1
                        inodes[key] = known
                        counted = 0
                    } else {
                        inodes[key] = InodeInfo(root: index, allocated: allocated,
                                                links: Int(st.st_nlink), seen: 1)
                    }
                }

                guard counted > 0 else { continue }
                items[index].allocatedBytes += counted
                totalAllocated += counted
                if topChildren > 0, level >= 1, let child = currentChild {
                    childSizes[index][child, default: 0] += counted
                }
            }
        }

        // Hard-linked inodes whose links were not all inside the measured roots.
        var totalShared: Int64 = 0
        for info in inodes.values where info.seen < info.links {
            items[info.root].sharedBytes += info.allocated
            totalShared += info.allocated
        }

        if topChildren > 0 {
            for index in items.indices where items[index].exists {
                items[index].children = childSizes[index]
                    .sorted { $0.value > $1.value }
                    .prefix(topChildren)
                    .map { DiskMeasurement.Child(path: $0.key, allocatedBytes: $0.value) }
            }
        }

        return MeasureReport(items: items, totalAllocatedBytes: totalAllocated,
                             totalSharedBytes: totalShared)
    }
}

public enum PathUtils {
    /// Expands `~` and standardizes the path (no symlink resolution).
    public static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
            .replacingOccurrences(of: "//", with: "/")
            .trimmingTrailingSlash()
    }

    public static var home: String { NSHomeDirectory() }

    /// Replaces the home directory with `~` for display and for anything that leaves the machine.
    public static func abbreviate(_ path: String) -> String {
        let home = Self.home
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

extension String {
    func trimmingTrailingSlash() -> String {
        var s = self
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
