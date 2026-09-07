import Foundation
import Testing
@testable import ARCHiDesktop

@Suite @MainActor
struct ReactorWorkerConnectionTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ARCHI_REACTOR_PUBLIC_PREFLIGHT"] == "1"))
    func installedWorkerPublicPreflightReachesNativeOwner() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let python = root.appendingPathComponent("output/creative-tools/reactor/runtime/bin/python3")
        let script = root.appendingPathComponent("desktop/Sources/ARCHiDesktop/Resources/ReactorBridge/worker.py")
        let subject = ReactorExpressionStore(factory: { ReactorWorkerConnection(python: python, script: script) })
        let reference = try Data(contentsOf: #require(CompanionVisualAsset.resourceURL(named: CompanionVisualAsset.lumenFilename)))
        subject.updateReference(id: "test-reference", label: "Lumen", png: reference, motionAllowed: true, visible: true)
        defer { subject.stop() }
        subject.prepare()
        for _ in 0..<150 where subject.state == .checking { try await Task.sleep(for: .milliseconds(100)) }
        #expect(subject.state == .prepared, "\(subject.status)")
        #expect(subject.runtimeReady)
        #expect(subject.quote != nil)
    }

    @Test func realChildDeliversResponseWhileStdinRemainsOpen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archi-worker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = directory.appendingPathComponent("echo.py")
        try "import sys\nfor line in sys.stdin:\n print(line.strip(), flush=True)\n".write(to: script, atomically: true, encoding: .utf8)
        let python = URL(fileURLWithPath: "/usr/bin/python3")
        let connection = ReactorWorkerConnection(python: python, script: script)
        defer { connection.terminate() }
        var lines: [Data] = []
        // Native UI actions drain their autorelease pool before the child replies.
        // The connection must retain its own reading handle beyond that event.
        try autoreleasepool {
            try connection.launch(onLine: { lines.append($0) }, onExit: {})
        }
        let message = Data("{\"command\":\"preflight\"}".utf8)
        connection.send(message)
        for _ in 0..<50 where lines.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
        #expect(lines == [message])
    }
}
