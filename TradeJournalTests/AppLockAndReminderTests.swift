import XCTest
@testable import TradeJournal

final class AppLockAndReminderTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "AppLockAndReminderTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: - App-slot

    func test_shouldLock() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertFalse(AppLockService.shouldLock(isEnabled: false, backgroundedAt: nil, now: now, gracePeriod: 0))
        XCTAssertTrue(AppLockService.shouldLock(isEnabled: true, backgroundedAt: nil, now: now, gracePeriod: 300))
        XCTAssertTrue(AppLockService.shouldLock(isEnabled: true, backgroundedAt: now.addingTimeInterval(-1), now: now, gracePeriod: 0))
        XCTAssertFalse(AppLockService.shouldLock(isEnabled: true, backgroundedAt: now.addingTimeInterval(-59), now: now, gracePeriod: 60))
        XCTAssertTrue(AppLockService.shouldLock(isEnabled: true, backgroundedAt: now.addingTimeInterval(-60), now: now, gracePeriod: 60))
    }

    func test_appLockSettings_persist() {
        let service = AppLockService(defaults: defaults)
        XCTAssertFalse(service.isEnabled)
        XCTAssertEqual(service.gracePeriod, 0)
        service.isEnabled = true
        service.gracePeriod = 300
        let reloaded = AppLockService(defaults: defaults)
        XCTAssertTrue(reloaded.isEnabled)
        XCTAssertEqual(reloaded.gracePeriod, 300)
    }

    // MARK: - Herinneringen

    func test_reminderSettings_defaultsAndClamping() {
        let settings = ReminderSettings(defaults: defaults)
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.hour, ReminderSettings.defaultHour)
        XCTAssertEqual(settings.minute, ReminderSettings.defaultMinute)
        XCTAssertTrue(settings.weekdaysOnly)
        XCTAssertEqual(settings.message, ReminderSettings.defaultMessage)

        settings.hour = 25
        settings.minute = -3
        settings.message = "   "
        XCTAssertEqual(settings.hour, 23)
        XCTAssertEqual(settings.minute, 0)
        XCTAssertEqual(settings.message, ReminderSettings.defaultMessage)

        settings.hour = 0
        XCTAssertEqual(settings.hour, 0)
    }

    func test_triggerComponents_weekdaysOrDaily() {
        let weekdays = ReminderService.triggerComponents(hour: 17, minute: 30, weekdaysOnly: true)
        XCTAssertEqual(weekdays.compactMap(\.weekday), [2, 3, 4, 5, 6])
        XCTAssertTrue(weekdays.allSatisfy { $0.hour == 17 && $0.minute == 30 })

        let daily = ReminderService.triggerComponents(hour: 8, minute: 0, weekdaysOnly: false)
        XCTAssertEqual(daily.count, 1)
        XCTAssertNil(daily[0].weekday)
        XCTAssertEqual(daily[0].hour, 8)
    }

    func test_identifiers_coverAllTriggers() {
        let all = Set(ReminderService.allIdentifiers)
        for components in ReminderService.triggerComponents(hour: 1, minute: 2, weekdaysOnly: true)
            + ReminderService.triggerComponents(hour: 1, minute: 2, weekdaysOnly: false) {
            XCTAssertTrue(all.contains(ReminderService.identifier(for: components)))
        }
    }
}
