import Foundation
import XCTest
@testable import FreeroomCore

final class MeasurerTests: XCTestCase {
    var root: String!

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "freeroom-tests-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    @discardableResult
    func write(_ relative: String, bytes: Int = 200_000) throws -> String {
        let path = root + "/" + relative
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        // Random bytes so APFS cannot compress or dedupe them.
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        try data.write(to: URL(fileURLWithPath: path))
        return path
    }

    func allocated(_ path: String) -> Int64 {
        var st = stat()
        lstat(path, &st)
        return Int64(st.st_blocks) * 512
    }

    func testHardLinksInsideRootAreCountedOnce() throws {
        let file = try write("pkg/a.bin")
        try FileManager.default.linkItem(atPath: file, toPath: root + "/pkg/b.bin")
        try FileManager.default.linkItem(atPath: file, toPath: root + "/pkg/c.bin")

        let report = Measurer().measure([root + "/pkg"])
        let item = report.items[0]
        let one = allocated(file)
        XCTAssertGreaterThanOrEqual(item.allocatedBytes, one)
        XCTAssertLessThan(item.allocatedBytes, one * 2, "a file with 3 links must be counted once")
        XCTAssertEqual(item.sharedBytes, 0, "all links are inside the root, so deleting frees everything")
        XCTAssertEqual(item.fileCount, 3)
    }

    func testHardLinksOutsideRootAreReportedAsShared() throws {
        // Like pnpm: node_modules links into a global store.
        let stored = try write("store/blob.bin")
        try FileManager.default.createDirectory(atPath: root + "/app/node_modules", withIntermediateDirectories: true)
        try FileManager.default.linkItem(atPath: stored, toPath: root + "/app/node_modules/blob.bin")

        let item = Measurer().measure([root + "/app/node_modules"]).items[0]
        XCTAssertEqual(item.sharedBytes, allocated(stored))
        XCTAssertLessThan(item.reclaimableBytes, allocated(stored), "deleting node_modules does not free the store blob")
    }

    func testOverlappingRootsAreDeduplicatedInTotal() throws {
        try write("x/big.bin")
        let report = Measurer().measure([root + "/x", root + "/x"])
        XCTAssertEqual(report.totalAllocatedBytes, report.items[0].allocatedBytes)
    }

    func testSymlinksAreNotFollowed() throws {
        try write("real/big.bin", bytes: 1_000_000)
        try FileManager.default.createDirectory(atPath: root + "/view", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: root + "/view/link", withDestinationPath: root + "/real")

        let item = Measurer().measure([root + "/view"]).items[0]
        XCTAssertLessThan(item.allocatedBytes, 100_000)
    }

    func testMissingPath() {
        let item = Measurer().measure([root + "/nope"]).items[0]
        XCTAssertFalse(item.exists)
        XCTAssertEqual(item.allocatedBytes, 0)
    }

    func testTopChildren() throws {
        try write("t/big/a.bin", bytes: 600_000)
        try write("t/small/a.bin", bytes: 50_000)
        let item = Measurer(topChildren: 1).measure([root + "/t"]).items[0]
        XCTAssertEqual(item.children?.count, 1)
        XCTAssertEqual(item.children?.first?.path, root + "/t/big")
    }

    // MARK: Build artifact rules

    func testRustTargetNeedsCargoToml() throws {
        try write("rust/Cargo.toml", bytes: 10)
        try write("rust/target/debug/app")
        try write("notrust/target/keep.txt") // a folder that merely happens to be called target

        let matches = ProjectScanner().scan(roots: [root])
        XCTAssertTrue(matches.contains { $0.path.hasSuffix("/rust/target") && $0.rule == "rust-target" })
        XCTAssertFalse(matches.contains { $0.path.hasSuffix("/notrust/target") })
    }

    func testVenvNeedsPyvenvCfg() throws {
        try write("py/.venv/pyvenv.cfg", bytes: 10)
        try write("fake/venv/notes.txt", bytes: 10)
        let paths = ProjectScanner().scan(roots: [root]).map(\.path)
        XCTAssertTrue(paths.contains { $0.hasSuffix("/py/.venv") })
        XCTAssertFalse(paths.contains { $0.hasSuffix("/fake/venv") })
    }

    func testDotnetObjNeedsProjectFile() throws {
        try write("api/Api.csproj", bytes: 10)
        try write("api/obj/project.assets.json", bytes: 10)
        try write("other/obj/model.obj", bytes: 10) // a 3D model folder, not .NET
        let paths = ProjectScanner().scan(roots: [root]).map(\.path)
        XCTAssertTrue(paths.contains { $0.hasSuffix("/api/obj") })
        XCTAssertFalse(paths.contains { $0.hasSuffix("/other/obj") })
    }

    func testNestedNodeModulesMatchedOnce() throws {
        try write("web/package.json", bytes: 10)
        try write("web/node_modules/dep/package.json", bytes: 10)
        try write("web/node_modules/dep/node_modules/sub/index.js", bytes: 10)
        let matches = ProjectScanner().scan(roots: [root]).filter { $0.rule == "node-modules" }
        XCTAssertEqual(matches.count, 1)
    }

    func testGitFoldersAreSkipped() throws {
        try write("repo/.git/modules/x/package.json", bytes: 10)
        try write("repo/.git/modules/x/node_modules/a.js", bytes: 10)
        XCTAssertTrue(ProjectScanner().scan(roots: [root]).isEmpty)
    }
}

final class ProbeTests: XCTestCase {
    func testDockerSizeParsing() {
        XCTAssertEqual(Probes.parseDockerSize("5.104GB"), 5_104_000_000)
        XCTAssertEqual(Probes.parseDockerSize("1.522GB (77%)"), 1_522_000_000)
        XCTAssertEqual(Probes.parseDockerSize("40.96kB"), 40_960)
        XCTAssertEqual(Probes.parseDockerSize("0B (0%)"), 0)
        XCTAssertEqual(Probes.parseDockerSize("garbage"), 0)
    }

    func testDockerFindings() {
        let output = """
        {"Active":"1","Reclaimable":"1.522GB (77%)","Size":"1.96GB","TotalCount":"19","Type":"Images"}
        {"Active":"1","Reclaimable":"0B (0%)","Size":"40.96kB","TotalCount":"1","Type":"Containers"}
        {"Active":"1","Reclaimable":"1.53GB (7%)","Size":"20.03GB","TotalCount":"8","Type":"Local Volumes"}
        {"Active":"0","Reclaimable":"5.104GB","Size":"12.42GB","TotalCount":"271","Type":"Build Cache"}
        """
        let findings = Probes.docker(output: output)
        XCTAssertEqual(Set(findings.map(\.id)), ["docker-build-cache", "docker-unused-images", "docker-unused-volumes"])
        let volumes = findings.first { $0.id == "docker-unused-volumes" }
        XCTAssertEqual(volumes?.safety, .review, "volumes can hold databases")
        XCTAssertEqual(findings.first { $0.id == "docker-build-cache" }?.command, "docker builder prune -a -f")
    }

    func testSimulatorRuntimesKeepMostRecentPerPlatform() {
        let json = """
        {
          "A": {"identifier":"A","version":"26.4","build":"23E244","platformIdentifier":"com.apple.platform.iphonesimulator","sizeBytes":8000000000,"lastUsedAt":"2026-04-06T02:52:35Z","deletable":true},
          "B": {"identifier":"B","version":"26.5","build":"23F77","platformIdentifier":"com.apple.platform.iphonesimulator","sizeBytes":8500000000,"lastUsedAt":"2026-06-27T15:17:29Z","deletable":true},
          "C": {"identifier":"C","version":"26.4","build":"23T239","platformIdentifier":"com.apple.platform.watchsimulator","sizeBytes":3700000000,"deletable":true}
        }
        """
        let findings = Probes.simulatorRuntimes(json: json)
        XCTAssertEqual(findings.map(\.id), ["sim-runtime-A"], "keeps iOS 26.5 and the only watchOS runtime")
        XCTAssertEqual(findings.first?.command, "xcrun simctl runtime delete A")
    }
}

final class StoreTests: XCTestCase {
    func testRoundTrip() throws {
        let path = NSTemporaryDirectory() + "freeroom-\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let store = try Store(path: path)

        let scan = try store.beginScan(source: .agent, note: "test")
        XCTAssertEqual(try store.openScan(source: .agent)?.id, scan.id)

        let finding = Finding(id: "agent:x", title: "X", paths: ["/tmp/x"], sizeBytes: 42, safety: .safe,
                              source: .agent, category: .devCaches, explanation: "Cache.", action: .delete)
        try store.upsert(finding, scanId: scan.id)
        var updated = finding
        updated.sizeBytes = 99
        try store.upsert(updated, scanId: scan.id)

        let saved = try store.findings(scanId: scan.id)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.sizeBytes, 99)
        XCTAssertEqual(saved.first?.scanId, scan.id)

        try store.endScan(id: scan.id)
        XCTAssertNil(try store.openScan(source: .agent))

        try store.setTranslation(findingId: "agent:x", lang: "es", text: "Caché.")
        XCTAssertEqual(try store.translations(lang: "es")["agent:x"], "Caché.")

        try store.recordCleanup(HistoryEntry(findingId: "agent:x", title: "X", freedBytes: 99, at: Date(), origin: "cli"))
        XCTAssertEqual(try store.history().first?.freedBytes, 99)
    }

    func testFindingJSONIsVersioned() throws {
        let finding = Finding(id: "a", title: "A", paths: [], sizeBytes: 1, safety: .keep, source: .rule,
                              category: .system, explanation: "", action: .none)
        let json = String(decoding: try JSONEncoder.freeroom.encode(finding), as: UTF8.self)
        XCTAssertTrue(json.contains("\"schema\" : 1"))
    }
}

final class OverlapTests: XCTestCase {
    func testNestedRootsCountOnceInTotal() throws {
        let root = NSTemporaryDirectory() + "freeroom-overlap-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        try FileManager.default.createDirectory(atPath: root + "/a/b", withIntermediateDirectories: true)
        try Data(count: 300_000).write(to: URL(fileURLWithPath: root + "/a/b/f.bin"))
        let report = Measurer().measure([root + "/a", root + "/a/b"])
        XCTAssertEqual(report.totalAllocatedBytes, report.items[0].allocatedBytes)
        XCTAssertGreaterThan(report.items[1].allocatedBytes, 0, "the nested item is still measured on its own")
    }
}
