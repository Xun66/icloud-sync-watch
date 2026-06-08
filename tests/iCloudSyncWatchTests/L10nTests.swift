import Testing
@testable import iCloudSyncWatch

struct L10nTests {
    @Test
    func loadsLocalizedStringsFromResourceBundle() {
        #expect(L10n.tr("app.name") == "iCloud Sync Watch")
    }
}
