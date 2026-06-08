import Testing
@testable import iCloudSyncWatch

struct DateFormattingTests {
    @Test
    func showsByteUnitForSmallFiles() {
        #expect(DateFormatting.fileSizeText(12) == "12 bytes")
    }
}
