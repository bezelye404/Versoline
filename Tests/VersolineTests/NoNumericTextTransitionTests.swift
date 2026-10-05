import Testing
import Foundation

/// `.contentTransition(.numericText())` on the sidebar counts made every count change keep about 1.4 MB: reading 100
/// articles took the app from 81 MB to 203 MB (see docs/benchmark.md). Plain text costs nothing, so the transition must
/// not come back without a new measurement with `scripts/benchmark.sh Release 36 2 mark-only`.
struct NoNumericTextTransitionTests {

    @Test func sourcesDoNotUseTheNumericTextTransition() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // VersolineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains(".numericText") { offenders.append(url.lastPathComponent) }
        }
        #expect(offenders.isEmpty, "numericText transition found in: \(offenders.joined(separator: ", "))")
    }
}
