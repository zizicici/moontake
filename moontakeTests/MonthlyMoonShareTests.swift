import UIKit
import XCTest
@testable import moontake

@MainActor
final class MonthlyMoonShareTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func capture(_ id: UInt8 = 1, at date: Date) -> CapturedPhoto {
        CapturedPhoto(data: Data([id]), fileType: .jpeg, width: 1600, height: 1200,
                      date: date, location: nil, locationName: nil, targets: [.watermark], movieURL: nil, resources: nil)
    }

    func testUnclearPhotosDoNotConsumeMonthAndShownMonthsSurviveRelaunch() async throws {
        let suite = "monthly-share-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var calls = 0
        let prompt = MonthlyMoonSharePrompt(defaults: defaults, timeZone: TimeZone(secondsFromGMT: 8 * 3600)!, isEnabled: { true }) { data, _, _, _ in
            calls += 1; return data == Data([2])
        }
        // The month boundary follows the user's local calendar, including a new year.
        let december = date("2026-12-31T15:59:59Z"), january = date("2026-12-31T16:00:00Z")
        prompt.consider(capture(at: december))
        try await wait { calls == 1 }
        XCTAssertFalse(prompt.hasPresented(in: december))
        prompt.consider(capture(2, at: december))
        try await wait { prompt.pendingPhoto != nil }
        XCTAssertFalse(prompt.hasPresented(in: december), "Recognition alone must not consume the month")
        prompt.markPresented()
        XCTAssertTrue(prompt.hasPresented(in: december))
        prompt.consider(capture(2, at: december))
        XCTAssertEqual(calls, 2)
        let relaunched = MonthlyMoonSharePrompt(defaults: defaults, timeZone: TimeZone(secondsFromGMT: 8 * 3600)!, isEnabled: { true }) { _, _, _, _ in true }
        XCTAssertTrue(relaunched.hasPresented(in: december))
        XCTAssertFalse(relaunched.hasPresented(in: january))
        relaunched.consider(capture(2, at: january))
        try await wait { relaunched.pendingPhoto != nil }
        relaunched.markPresented()
        XCTAssertTrue(relaunched.hasPresented(in: january))
        XCTAssertTrue(relaunched.hasPresented(in: december))
    }

    func testAnalysisIsBoundedAndDisablingDiscardsAnInFlightResult() async throws {
        let suite = "monthly-share-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var enabled = true, calls: [Data] = []
        var completion: CheckedContinuation<Bool, Never>?
        let prompt = MonthlyMoonSharePrompt(defaults: defaults, isEnabled: { enabled }) { data, _, _, _ in
            calls.append(data)
            return await withCheckedContinuation { completion = $0 }
        }
        let now = Date()
        prompt.consider(capture(1, at: now))
        try await wait { completion != nil }
        prompt.consider(capture(2, at: now)); prompt.consider(capture(3, at: now))
        XCTAssertEqual(calls, [Data([1])])
        completion?.resume(returning: true); completion = nil
        try await wait { calls.count == 2 && completion != nil }
        XCTAssertEqual(calls.last, Data([3]), "At most one latest capture waits for analysis")
        XCTAssertNil(prompt.pendingPhoto, "An older positive result must not replace the latest waiting capture")
        enabled = false; prompt.refreshPreferences()
        enabled = true // Re-enabling must not resurrect an old result.
        completion?.resume(returning: true); completion = nil
        await Task.yield(); await Task.yield()
        XCTAssertNil(prompt.pendingPhoto)
        XCTAssertFalse(prompt.hasPresented(in: now))
        enabled = false
        prompt.consider(capture(4, at: now))
        XCTAssertEqual(calls.count, 2)
    }

    func testNewPhotoDiscardsAnAlreadyRecognizedUnpresentedCandidate() async throws {
        let suite = "monthly-share-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var assessed: [Data] = []
        let prompt = MonthlyMoonSharePrompt(defaults: defaults, isEnabled: { true }) { data, _, _, _ in
            assessed.append(data)
            return data == Data([1])
        }
        let now = Date()
        prompt.consider(capture(1, at: now))
        // Recognition has already finished. Presentation alone was blocked,
        // for example by another page or a tutorial; this is not slow analysis.
        try await wait { prompt.pendingPhoto != nil }
        XCTAssertEqual(assessed, [Data([1])])
        prompt.consider(capture(2, at: now))
        XCTAssertNil(prompt.pendingPhoto, "A new photo must not expose an older pending candidate")
        try await wait { assessed.count == 2 }
        XCTAssertNil(prompt.pendingPhoto)
        XCTAssertFalse(prompt.hasPresented(in: now))
    }

    func testNewShutterDiscardsReadyCandidateWithoutConsumingMonth() async throws {
        let suite = "monthly-share-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prompt = MonthlyMoonSharePrompt(defaults: defaults, isEnabled: { true }) { _, _, _, _ in true }
        let now = Date()
        prompt.consider(capture(1, at: now))
        try await wait { prompt.pendingPhoto != nil }
        prompt.discardPreviousCapture()
        XCTAssertNil(prompt.pendingPhoto, "Discard at shutter time, before any new photo is delivered")
        prompt.markPresented()
        XCTAssertFalse(prompt.hasPresented(in: now))
        prompt.consider(capture(2, at: now))
        try await wait { prompt.pendingPhoto != nil }
        XCTAssertEqual(prompt.pendingPhoto?.data, Data([2]))
        prompt.markPresented()
        XCTAssertTrue(prompt.hasPresented(in: now), "The next qualifying capture can still use this month")
    }

    func testNewShutterInvalidatesRunningAndQueuedCapturesBeforeItsResultArrives() async throws {
        let suite = "monthly-share-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var completion: CheckedContinuation<Bool, Never>?
        var calls: [Data] = [], completed = false, offers = 0
        let prompt = MonthlyMoonSharePrompt(defaults: defaults, isEnabled: { true }) { data, _, _, _ in
            calls.append(data)
            if data != Data([1]) { return false }
            let qualifies = await withCheckedContinuation { completion = $0 }
            completed = true
            return qualifies
        }
        prompt.onReady = { offers += 1 }
        let now = Date()
        prompt.consider(capture(1, at: now))
        try await wait { completion != nil }
        prompt.consider(capture(2, at: now))
        prompt.discardPreviousCapture()
        completion?.resume(returning: true); completion = nil
        try await wait { completed }
        XCTAssertNil(prompt.pendingPhoto)
        XCTAssertEqual(offers, 0)
        XCTAssertEqual(calls, [Data([1])], "The superseded queued capture must also be discarded")
        prompt.consider(capture(3, at: now))
        try await wait { calls.count == 2 }
        XCTAssertEqual(calls, [Data([1]), Data([3])])
        XCTAssertNil(prompt.pendingPhoto)
        XCTAssertEqual(offers, 0)
        XCTAssertFalse(prompt.hasPresented(in: now))
    }

    func testRecognizableMariaUsesRealPhotoStructureAndKeepsMainActorResponsive() async throws {
        let fixtures = [
            ("soft-full-moon", "png", "2026-06-30T16:26:09Z"),
            ("soft-gibbous-moon-may", "png", "2026-05-25T11:31:40Z"),
            ("soft-gibbous-moon-september", "png", "2026-09-21T10:33:03Z"),
            ("daylight-moon", "jpg", "2026-04-28T10:08:35Z")
        ]
        var pulses = 0
        let heartbeat = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000)
                pulses += 1
            }
        }
        defer { heartbeat.cancel() }
        let engine = MoonAtlasEngine()
        for (name, suffix, time) in fixtures {
            let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: suffix))
            let data = try Data(contentsOf: url)
            let start = Date()
            let accepted = try await engine.hasRecognizableMaria(in: data, at: date(time), latitude: nil, longitude: nil)
            XCTAssertTrue(accepted, name)
            print("MONTHLY_SHARE_ANALYSIS \(name) seconds=\(Date().timeIntervalSince(start))")
        }
        XCTAssertGreaterThan(pulses, 0, "Analysis must leave the main actor responsive")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        for blank in [true, false] {
            let data = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600), format: format).jpegData(withCompressionQuality: 0.9) { context in
                UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
                if !blank { UIColor.white.setFill(); context.cgContext.fillEllipse(in: CGRect(x: 220, y: 130, width: 320, height: 320)) }
            }
            let accepted = try await engine.hasRecognizableMaria(in: data, at: Date(), latitude: nil, longitude: nil)
            XCTAssertFalse(accepted, "A blank image or featureless bright disc must not trigger sharing")
        }
    }

    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for monthly sharing")
    }
}
