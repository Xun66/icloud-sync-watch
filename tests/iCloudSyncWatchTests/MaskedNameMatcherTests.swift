import Testing
@testable import iCloudSyncWatch

struct MaskedNameMatcherTests {
    @Test
    func matchesUnicodeScalarCounts() {
        #expect(MaskedNameMatcher.matches(maskedName: "翻{4}.epub", candidate: "翻译乃大道.epub"))
        #expect(!MaskedNameMatcher.matches(maskedName: "翻{3}.epub", candidate: "翻译乃大道.epub"))
    }
}
