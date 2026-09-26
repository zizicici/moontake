import XCTest
@testable import moontake

final class MoonCalendarTests: XCTestCase {
    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func calendar(_ timeZone: String = "UTC", firstWeekday: Int = 1) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func month(_ value: String, calendar: Calendar) throws -> MoonCalendarMonth {
        let instant = try date(value)
        return try XCTUnwrap(MoonCalendarMonth.calculate(containing: instant, calendar: calendar, now: instant))
    }

    func testFullMoonBelongsToTheLocalCivilDay() throws {
        // Existing USNO fixture: September 26, 2026 at 16:49 UTC.
        let utc = calendar()
        let singapore = calendar("Asia/Singapore")
        let timestamp = "2026-09-15T12:00:00Z"
        let utcMonth = try month(timestamp, calendar: utc)
        let localMonth = try month(timestamp, calendar: singapore)
        XCTAssertEqual(utc.component(.day, from: try XCTUnwrap(utcMonth.events.first { $0.quarter == .fullMoon }).date), 26)
        let full = try XCTUnwrap(localMonth.events.first { $0.quarter == .fullMoon })
        XCTAssertEqual(singapore.component(.day, from: full.date), 27)
        XCTAssertEqual(full.date.timeIntervalSince(try date("2026-09-26T16:49:00Z")), 0, accuracy: 120)
        XCTAssertEqual(localMonth.days[26].event?.quarter, .fullMoon)
        XCTAssertEqual(localMonth.days[26].angle, 180)
        XCTAssertEqual(localMonth.days.count, 30)
    }

    func testMonthWithTwoFullMoonsKeepsBothEventsInOrder() throws {
        let calendar = calendar()
        let result = try month("2026-05-15T12:00:00Z", calendar: calendar)
        let fullMoons = result.events.filter { $0.quarter == .fullMoon }
        XCTAssertEqual(fullMoons.count, 2)
        XCTAssertEqual(fullMoons.map { calendar.component(.day, from: $0.date) }, [1, 31])
        XCTAssertEqual(result.events.map(\.date), result.events.map(\.date).sorted())
        XCTAssertEqual(Set(result.events.map(\.date)).count, result.events.count)
        XCTAssertEqual(result.nextFullMoon.timeIntervalSince(try XCTUnwrap(fullMoons.last).date), 0, accuracy: 1)
    }

    func testLeapMonthAndLocaleWeekStart() throws {
        let sunday = try month("2024-02-15T12:00:00Z", calendar: calendar(firstWeekday: 1))
        let monday = try month("2024-02-15T12:00:00Z", calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(sunday.days.count, 29)
        XCTAssertEqual(sunday.leadingEmptyDays, 4)
        XCTAssertEqual(monday.leadingEmptyDays, 3)
    }

    func testDaylightSavingTransitionDoesNotSkipOrDuplicateADay() throws {
        let calendar = calendar("America/New_York")
        let result = try month("2026-03-15T12:00:00Z", calendar: calendar)
        XCTAssertEqual(result.days.map { calendar.component(.day, from: $0.date) }, Array(1...31))
        XCTAssertTrue(result.days.allSatisfy { calendar.component(.hour, from: $0.date) == 0 })
        XCTAssertEqual(result.days[8].date.timeIntervalSince(result.days[7].date), 23 * 3600)
    }

    func testSkippedCivilDatesStayInsideTheirMonthAndKeepWeekdayColumns() throws {
        for (zone, timestamp, missingDay) in [
            ("Pacific/Apia", "2011-12-15T12:00:00Z", 30),
            ("Pacific/Kiritimati", "1994-12-15T12:00:00Z", 31),
        ] {
            for firstWeekday in [1, 2] {
                let calendar = calendar(zone, firstWeekday: firstWeekday)
                let result = try month(timestamp, calendar: calendar)
                let interval = try XCTUnwrap(calendar.dateInterval(of: .month, for: try date(timestamp)))
                XCTAssertEqual(result.days.map { calendar.component(.day, from: $0.date) },
                               (1...31).filter { $0 != missingDay })
                XCTAssertTrue(result.days.allSatisfy { $0.date >= interval.start && $0.date < interval.end })
                XCTAssertEqual(Set(result.days.map(\.date)).count, 30)
                XCTAssertEqual(Set(result.days.map(\.gridIndex)).count, 30)
                for day in result.days {
                    XCTAssertEqual(day.gridIndex % 7, (calendar.component(.weekday, from: day.date) - firstWeekday + 7) % 7)
                }
                for (day, next) in zip(result.days, result.days.dropFirst()) {
                    XCTAssertEqual(day.illuminationChange.end, next.illuminationChange.start, accuracy: 1e-12)
                }
                XCTAssertEqual(result.timeZone, calendar.timeZone)
            }
        }
    }

    func testNextFullMoonCrossesYearBoundary() throws {
        let calendar = calendar()
        let now = try date("2026-12-31T12:00:00Z")
        let result = try month("2026-12-31T12:00:00Z", calendar: calendar)
        XCTAssertGreaterThan(result.nextFullMoon, now)
        XCTAssertEqual(calendar.component(.year, from: result.nextFullMoon), 2027)
        XCTAssertTrue(result.events.allSatisfy { calendar.component(.month, from: $0.date) == 12 })
    }

    func testUnavailableEphemerisDoesNotFabricateCalendar() throws {
        let unsupported = try date("2700-01-01T12:00:00Z")
        XCTAssertNil(MoonCalendarMonth.calculate(containing: unsupported, calendar: calendar(), now: unsupported))
    }

    func testIlluminationChangePreservesWaxingAndWaningTimeOrder() throws {
        let calendar = calendar()
        for (timestamp, waxing) in [("2026-01-22T12:00:00Z", true), ("2026-01-14T12:00:00Z", false)] {
            let interval = try XCTUnwrap(calendar.dateInterval(of: .day, for: try date(timestamp)))
            let change = try XCTUnwrap(MoonManager.shared.illuminationChange(during: interval))
            let start = try XCTUnwrap(MoonManager.shared.info(at: interval.start)).illumination
            let end = try XCTUnwrap(MoonManager.shared.info(at: interval.end)).illumination
            XCTAssertEqual(change.start, start, accuracy: 1e-12)
            XCTAssertEqual(change.end, end, accuracy: 1e-12)
            XCTAssertEqual(change.end > change.start, waxing)
        }
    }

    @MainActor
    func testSeptemberFullMoonDayKeepsDescendingEndpointsAndMidnightContinuity() throws {
        let calendar = calendar("Asia/Singapore")
        let september = try month("2026-09-15T12:00:00Z", calendar: calendar)
        let waxing = september.days[25].illuminationChange
        let waning = september.days[26].illuminationChange
        XCTAssertGreaterThan(waxing.end, waxing.start)
        XCTAssertLessThan(waning.end, waning.start)
        XCTAssertEqual(waxing.end, waning.start, accuracy: 1e-12)
        let locale = Locale(identifier: "en_US")
        XCTAssertTrue(MoonCalendarViewController.illuminationText(waxing, locale: locale).contains("98.7% → 99.9%"))
        XCTAssertTrue(MoonCalendarViewController.illuminationText(waning, locale: locale).contains("99.9% → 98.8%"))
        for day in [september.days[25], september.days[26]] {
            let interval = try XCTUnwrap(calendar.dateInterval(of: .day, for: day.date))
            XCTAssertEqual(day.illuminationChange.start, try XCTUnwrap(MoonManager.shared.info(at: interval.start)).illumination)
            XCTAssertEqual(day.illuminationChange.end, try XCTUnwrap(MoonManager.shared.info(at: interval.end)).illumination)
        }
    }

    func testIlluminationChangeUsesLocalDayBoundariesAcrossDST() throws {
        let calendar = calendar("America/New_York")
        for (timestamp, hours) in [("2026-03-08T12:00:00Z", 23.0), ("2026-11-01T12:00:00Z", 25.0)] {
            let interval = try XCTUnwrap(calendar.dateInterval(of: .day, for: try date(timestamp)))
            XCTAssertEqual(interval.duration, hours * 3600)
            let change = try XCTUnwrap(MoonManager.shared.illuminationChange(during: interval))
            XCTAssertEqual(change.start, try XCTUnwrap(MoonManager.shared.info(at: interval.start)).illumination)
            XCTAssertEqual(change.end, try XCTUnwrap(MoonManager.shared.info(at: interval.end)).illumination)
        }
        let unsupported = try date("2700-01-01T00:00:00Z")
        XCTAssertNil(MoonManager.shared.illuminationChange(during: DateInterval(start: unsupported, duration: 86400)))
    }

    @MainActor
    func testIlluminationChangeAlwaysKeepsOneDecimalPlaceAndTimeOrder() {
        let locale = Locale(identifier: "en_US")
        XCTAssertTrue(MoonCalendarViewController.illuminationText(.init(start: 0.05, end: 1), locale: locale).contains("5.0% → 100.0%"))
        XCTAssertTrue(MoonCalendarViewController.illuminationText(.init(start: 1, end: 0.05), locale: locale).contains("100.0% → 5.0%"))
        XCTAssertTrue(MoonCalendarViewController.illuminationText(.init(start: 0, end: 0.056), locale: locale).contains("0.0% → 5.6%"))
        XCTAssertTrue(MoonCalendarViewController.illuminationText(.init(start: 0.05, end: 0.05), locale: locale).contains("5.0% → 5.0%"))
    }
}
