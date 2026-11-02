import Testing
import DriverAPI

@Suite("Driver settings keys")
struct DriverSettingsKeyTests {
    @Test func acceptsOnlyDefinedASCIIShape() {
        for raw in ["a", "interval", "display.mode", "x_1-2", "a" + String(repeating: "z", count: 127)] {
            #expect(DriverSettingKey(raw)?.rawValue == raw)
        }
        for raw in ["", "1abc", "_a", ".a", "a b", "a/b", "é", "a" + String(repeating: "z", count: 128)] {
            #expect(DriverSettingKey(raw) == nil)
        }
    }

    @Test func typedReadsNeverCoerce() {
        let key = DriverSettingKey("value")!
        let settings = StubSettings(stored: .integer(3))
        #expect(settings.integer(for: key) == 3)
        #expect(settings.bool(for: key) == nil)
        #expect(settings.number(for: key) == nil)
        #expect(settings.text(for: key) == nil)
    }
}

private struct StubSettings: DriverSettings {
    let stored: DriverSettingValue
    func value(for key: DriverSettingKey) -> DriverSettingValue? { stored }
}
