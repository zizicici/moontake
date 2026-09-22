import XCTest
import SkyKit
@testable import moontake

final class MoonPhaseTests: XCTestCase {
    private func info(at date: Date) throws -> MoonManager.Info {
        try XCTUnwrap(MoonManager.shared.info(at: date))
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    func testUnavailableDataDoesNotProduceAPhaseOrDirection() throws {
        let unsupported = try date("2700-01-01T00:00:00Z")
        XCTAssertNil(MoonManager.shared.info(at: unsupported))
        XCTAssertNil(MoonManager.shared.nextOccurrence(of: .fullMoon, after: unsupported))
    }

    func testIlluminationAgainstIndependentEphemeris() throws {
        // PyEphem 4.2.1, geocentric apparent illuminated fraction, UTC.
        let fixtures: [(String, Double)] = [
            ("2000-01-01T12:00:00Z", 0.230030193329),
            ("2010-06-15T00:00:00Z", 0.085176811218),
            ("2026-01-03T10:03:00Z", 0.998610687256),
            ("2026-01-10T15:48:00Z", 0.501303710938),
            ("2026-01-18T19:52:00Z", 0.000867825449),
            ("2026-01-22T12:00:00Z", 0.137502222061),
            ("2026-01-26T04:47:00Z", 0.501242866516),
            ("2026-01-29T12:00:00Z", 0.846721954346),
            ("2040-12-31T23:59:00Z", 0.046775469780)
        ]
        for (timestamp, expected) in fixtures {
            let info = try self.info(at: try date(timestamp))
            XCTAssertEqual(info.illumination, expected, accuracy: 0.0002, timestamp)
            XCTAssertTrue((0...1).contains(info.displayIllumination))
            XCTAssertTrue((0..<360).contains(info.angle))
        }
    }

    func testQuarterTimesAgainstUSNO() throws {
        // Universal Time, rounded to minutes; allow two minutes for model/rounding.
        // https://aa.usno.navy.mil/calculated/moon/phases?year=2026
        let fixtures: [(MoonManager.Quarter, String)] = [
            (.fullMoon, "2026-01-03T10:03:00Z"),
            (.lastQuarter, "2026-01-10T15:48:00Z"),
            (.newMoon, "2026-01-18T19:52:00Z"),
            (.firstQuarter, "2026-01-26T04:47:00Z"),
            (.newMoon, "2026-09-11T03:27:00Z"),
            (.firstQuarter, "2026-09-18T20:44:00Z"),
            (.fullMoon, "2026-09-26T16:49:00Z"),
            (.lastQuarter, "2026-10-03T13:25:00Z")
        ]
        for (quarter, timestamp) in fixtures {
            let expected = try date(timestamp)
            let result = try XCTUnwrap(MoonManager.shared.nextOccurrence(of: quarter,
                after: expected.addingTimeInterval(-5 * 86400)))
            XCTAssertEqual(result.timeIntervalSince(expected), 0, accuracy: 120, timestamp)
        }
    }

    func testAllEightLocalizedPhaseNames() throws {
        let fixtures = [
            ("2026-01-19T00:00:00Z", "moon.phase.new"),
            ("2026-01-22T12:00:00Z", "moon.phase.waxing.crescent"),
            ("2026-01-26T04:47:00Z", "moon.phase.waxing.first_quarter"),
            ("2026-01-29T12:00:00Z", "moon.phase.waxing.gibbous"),
            ("2026-01-03T12:00:00Z", "moon.phase.full"),
            ("2026-01-07T12:00:00Z", "moon.phase.waning.gibbous"),
            ("2026-01-10T15:48:00Z", "moon.phase.waning.last_quarter"),
            ("2026-01-14T12:00:00Z", "moon.phase.waning.crescent")
        ]
        for (timestamp, key) in fixtures {
            let info = try self.info(at: try date(timestamp))
            XCTAssertEqual(info.name, NSLocalizedString(key, bundle: Bundle(for: MoonManager.self), comment: ""), timestamp)
        }
    }

    func testTwoHourDisplayRoundingWorksWithoutLoadingAYear() throws {
        for start in ["2000-12-15T00:00:00Z", "2026-12-15T00:00:00Z", "2040-12-15T00:00:00Z"] {
            for quarter in [MoonManager.Quarter.newMoon, .fullMoon] {
                let event = try XCTUnwrap(MoonManager.shared.nextOccurrence(of: quarter, after: try date(start)))
                for offset in [-119.0, 0, 119] {
                    let info = try self.info(at: event.addingTimeInterval(offset * 60))
                    XCTAssertEqual(info.displayIllumination, quarter == .newMoon ? 0 : 1)
                }
                for offset in [-121.0, 121] {
                    let info = try self.info(at: event.addingTimeInterval(offset * 60))
                    XCTAssertEqual(info.displayIllumination, info.illumination)
                }
            }
        }
    }

    func testWaxingWaningAndYearBoundary() throws {
        let midnight = try date("2027-01-01T00:00:00Z")
        let before = try self.info(at: midnight.addingTimeInterval(-1))
        let after = try self.info(at: midnight.addingTimeInterval(1))
        XCTAssertEqual(before.illumination, after.illumination, accuracy: 0.00001)
        XCTAssertEqual(before.phase, after.phase)
        let waxing = try self.info(at: try date("2026-01-22T12:00:00Z"))
        let waning = try self.info(at: try date("2026-01-14T12:00:00Z"))
        XCTAssertEqual(waxing.phase, .waxingMoon)
        XCTAssertEqual(waning.phase, .waningMoon)
        XCTAssertLessThan(waxing.angle, 180)
        XCTAssertGreaterThan(waning.angle, 180)
    }

    func testPhotoAndFinderCalculationsCanRunConcurrently() throws {
        let instant = try date("2026-09-22T12:00:00Z")
        let expectedPhase = try self.info(at: instant)
        let expectedPosition = try XCTUnwrap(Moon.position(at: instant, latitude: 1.3521, longitude: 103.8198))
        let resultLock = NSLock()
        var mismatches = 0
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            let phase = MoonManager.shared.info(at: instant)
            let position = Moon.position(at: instant, latitude: 1.3521, longitude: 103.8198)
            if phase?.illumination != expectedPhase.illumination || position?.azimuth != expectedPosition.azimuth {
                resultLock.lock()
                mismatches += 1
                resultLock.unlock()
            }
        }
        XCTAssertEqual(mismatches, 0)
    }
}
