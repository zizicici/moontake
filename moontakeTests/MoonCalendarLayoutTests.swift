import XCTest
import UIKit
import MoreKit
@testable import moontake

@MainActor
final class MoonCalendarLayoutTests: XCTestCase {
    private func element(_ identifier: String, in root: UIView) -> UIView? {
        if root.accessibilityIdentifier == identifier { return root }
        return root.subviews.lazy.compactMap { self.element(identifier, in: $0) }.first
    }

    private func scrollView(containing view: UIView) throws -> UIScrollView {
        var ancestor = view.superview
        while let candidate = ancestor {
            if let scroll = candidate as? UIScrollView { return scroll }
            ancestor = candidate.superview
        }
        return try XCTUnwrap(ancestor as? UIScrollView, "Calendar scroll view is missing")
    }

    private func loadedController(date: Date = Date(), calendar: Calendar? = nil,
                                  hasAccess: @escaping () -> Bool = { true }) async throws -> MoonCalendarViewController {
        let controller = MoonCalendarViewController(date: date, calendar: calendar, hasFullCalendarAccess: hasAccess)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 640)
        controller.view.layoutIfNeeded()
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            self?.element("moonCalendar.day.1", in: controller.view) != nil
        }, object: nil)
        await fulfillment(of: [loaded], timeout: 10)
        controller.view.layoutIfNeeded()
        return controller
    }

    private func tapToday(_ controller: MoonCalendarViewController) throws {
        let item = try XCTUnwrap(controller.navigationItem.leftBarButtonItem)
        UIApplication.shared.sendAction(try XCTUnwrap(item.action), to: item.target, from: item, for: nil)
    }

    func testMonthChangeKeepsVisibleContentAndScrollPositionWhileLoading() async throws {
        let controller = try await loadedController()
        let grid = try XCTUnwrap(element("moonCalendar.grid", in: controller.view))
        let month = try XCTUnwrap(element("moonCalendar.month", in: controller.view) as? UILabel)
        let scrollView = try scrollView(containing: grid)
        scrollView.setContentOffset(CGPoint(x: 0, y: 100), animated: false)
        controller.view.layoutIfNeeded()
        let oldGridFrame = grid.convert(grid.bounds, to: controller.view)
        let oldContentSize = scrollView.contentSize
        let oldMonth = month.text
        let next = try XCTUnwrap(element("moonCalendar.next", in: controller.view) as? UIButton)
        next.sendActions(for: .touchUpInside)
        // Do not yield the main actor: inspect the pending state before completion.
        controller.view.layoutIfNeeded()
        XCTAssertFalse(grid.isHidden)
        XCTAssertEqual(grid.convert(grid.bounds, to: controller.view), oldGridFrame)
        XCTAssertEqual(scrollView.contentSize, oldContentSize)
        XCTAssertEqual(scrollView.contentOffset.y, 100, accuracy: 0.5)
        XCTAssertEqual(month.text, oldMonth, "Keep the heading and old days in the same month until replacement")
        XCTAssertFalse(grid.isUserInteractionEnabled)
        let updated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in month.text != oldMonth }, object: nil)
        await fulfillment(of: [updated], timeout: 10)
        XCTAssertTrue(grid.isUserInteractionEnabled)
        XCTAssertFalse(grid.isHidden)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(scrollView.contentSize.width, scrollView.bounds.width, accuracy: 0.5)
    }

    func testTodayReusesCurrentMonthAndCancelsPendingMonthChange() async throws {
        let controller = try await loadedController()
        let grid = try XCTUnwrap(element("moonCalendar.grid", in: controller.view))
        let firstDay = try XCTUnwrap(element("moonCalendar.day.1", in: controller.view) as? UIButton)
        let month = try XCTUnwrap(element("moonCalendar.month", in: controller.view) as? UILabel)
        let oldMonth = month.text
        firstDay.sendActions(for: .touchUpInside)
        try tapToday(controller)
        controller.view.layoutIfNeeded()
        XCTAssertFalse(grid.isHidden)
        XCTAssertTrue(element("moonCalendar.day.1", in: controller.view) === firstDay)
        let today = Calendar.current.component(.day, from: Date())
        XCTAssertTrue(try XCTUnwrap(element("moonCalendar.day.\(today)", in: controller.view) as? UIButton)
            .accessibilityTraits.contains(.selected))
        let next = try XCTUnwrap(element("moonCalendar.next", in: controller.view) as? UIButton)
        next.sendActions(for: .touchUpInside)
        next.sendActions(for: .touchUpInside)
        try tapToday(controller)
        // Let cancelled tasks finish; they must not replace the restored month.
        let settled = expectation(description: "Cancelled loads settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settled.fulfill() }
        await fulfillment(of: [settled], timeout: 2)
        XCTAssertEqual(month.text, oldMonth)
        XCTAssertFalse(grid.isHidden)
        XCTAssertTrue(grid.isUserInteractionEnabled)
        XCTAssertTrue(element("moonCalendar.day.1", in: controller.view) === firstDay)
    }

    func testMembershipChangesCoverAndRevealSelectedMonthInPlace() async throws {
        var isMember = true
        let controller = try await loadedController(hasAccess: { isMember })
        let month = try XCTUnwrap(element("moonCalendar.month", in: controller.view) as? UILabel)
        let information = try XCTUnwrap(element("moonCalendar.information", in: controller.view))
        let overlay = try XCTUnwrap(element("moonCalendar.lock", in: controller.view))
        let originalMonth = month.text
        let next = try XCTUnwrap(element("moonCalendar.next", in: controller.view) as? UIButton)
        next.sendActions(for: .touchUpInside)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in month.text != originalMonth }, object: nil)
        await fulfillment(of: [advanced], timeout: 10)
        let selectedMonth = month.text
        let selectedDate = try XCTUnwrap(element("moonCalendar.selectedDate", in: controller.view) as? UILabel)
        let day = try XCTUnwrap(element("moonCalendar.day.15", in: controller.view) as? UIButton)
        day.sendActions(for: .touchUpInside)
        let selection = selectedDate.text
        XCTAssertTrue(overlay.isHidden)
        isMember = false
        NotificationCenter.default.post(name: .StoreInfoLoaded, object: nil)
        XCTAssertEqual(month.text, selectedMonth)
        XCTAssertFalse(overlay.isHidden)
        XCTAssertFalse(information.isUserInteractionEnabled)
        XCTAssertTrue(information.accessibilityElementsHidden)
        let otherDay = try XCTUnwrap(element("moonCalendar.day.1", in: controller.view) as? UIButton)
        otherDay.sendActions(for: .touchUpInside)
        XCTAssertEqual(selectedDate.text, selection)
        isMember = true
        NotificationCenter.default.post(name: .StoreInfoLoaded, object: nil)
        XCTAssertTrue(overlay.isHidden)
        XCTAssertTrue(information.isUserInteractionEnabled)
        XCTAssertFalse(information.accessibilityElementsHidden)
        XCTAssertEqual(month.text, selectedMonth)
        XCTAssertTrue(element("moonCalendar.day.15", in: controller.view) === day)
        XCTAssertTrue(day.accessibilityTraits.contains(.selected))
    }

    func testFreeMonthNavigationCoversPendingContentUntilCurrentMonthIsReady() async throws {
        let controller = try await loadedController(hasAccess: { false })
        let information = try XCTUnwrap(element("moonCalendar.information", in: controller.view))
        let overlay = try XCTUnwrap(element("moonCalendar.lock", in: controller.view))
        let month = try XCTUnwrap(element("moonCalendar.month", in: controller.view) as? UILabel)
        let currentMonth = month.text
        let next = try XCTUnwrap(element("moonCalendar.next", in: controller.view) as? UIButton)
        XCTAssertTrue(overlay.isHidden)
        next.sendActions(for: .touchUpInside)
        XCTAssertFalse(overlay.isHidden, "Cover content before the asynchronous month calculation")
        XCTAssertTrue(information.accessibilityElementsHidden)
        XCTAssertNil(controller.presentedViewController)
        let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in month.text != currentMonth }, object: nil)
        await fulfillment(of: [advanced], timeout: 10)
        XCTAssertFalse(overlay.isHidden)
        try tapToday(controller)
        XCTAssertFalse(overlay.isHidden, "Do not expose the previous paid snapshot during loading")
        let returned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in month.text == currentMonth && overlay.isHidden }, object: nil)
        await fulfillment(of: [returned], timeout: 10)
        XCTAssertTrue(information.isUserInteractionEnabled)
        XCTAssertFalse(information.accessibilityElementsHidden)
    }

    func testTimeZoneChangesKeepTheBrowsedMonthAndSelectedCivilDay() async throws {
        for (from, to) in [("Asia/Singapore", "America/Los_Angeles"), ("America/Los_Angeles", "Asia/Singapore")] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "en_US")
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: from))
            let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12)))
            let controller = try await loadedController(date: date, calendar: calendar)
            let month = try XCTUnwrap(element("moonCalendar.month", in: controller.view) as? UILabel)
            let grid = try XCTUnwrap(element("moonCalendar.grid", in: controller.view))
            let initialMonth = month.text
            let next = try XCTUnwrap(element("moonCalendar.next", in: controller.view) as? UIButton)
            next.sendActions(for: .touchUpInside)
            let advanced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in month.text != initialMonth }, object: nil)
            await fulfillment(of: [advanced], timeout: 10)
            let selectedDay = try XCTUnwrap(element("moonCalendar.day.15", in: controller.view) as? UIButton)
            selectedDay.sendActions(for: .touchUpInside)
            let dateLabel = try XCTUnwrap(element("moonCalendar.selectedDate", in: controller.view) as? UILabel)
            let illumination = try XCTUnwrap(element("moonCalendar.illumination", in: controller.view) as? UILabel)
            let expectedMonth = month.text
            let expectedDate = dateLabel.text
            calendar.timeZone = try XCTUnwrap(TimeZone(identifier: to))
            let selected = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12)))
            let interval = try XCTUnwrap(calendar.dateInterval(of: .day, for: selected))
            let change = try XCTUnwrap(MoonManager.shared.illuminationChange(during: interval))
            let expectedIllumination = MoonCalendarViewController.illuminationText(change, locale: calendar.locale!)
            controller.refreshCalendar(timeZone: calendar.timeZone)
            let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                grid.isUserInteractionEnabled && illumination.text == expectedIllumination
            }, object: nil)
            await fulfillment(of: [refreshed], timeout: 10)
            XCTAssertEqual(month.text, expectedMonth)
            XCTAssertEqual(dateLabel.text, expectedDate)
            XCTAssertTrue(try XCTUnwrap(element("moonCalendar.day.15", in: controller.view) as? UIButton)
                .accessibilityTraits.contains(.selected))
        }
    }

    func testTodayDoesNotReuseSnapshotFromPreviousTimeZone() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Singapore"))
        let controller = try await loadedController(calendar: calendar)
        let firstDay = try XCTUnwrap(element("moonCalendar.day.1", in: controller.view))
        let grid = try XCTUnwrap(element("moonCalendar.grid", in: controller.view))
        controller.refreshCalendar(timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo")))
        try tapToday(controller)
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            guard let day = self?.element("moonCalendar.day.1", in: controller.view) else { return false }
            return day !== firstDay && grid.isUserInteractionEnabled
        }, object: nil)
        await fulfillment(of: [refreshed], timeout: 10)
    }

    func testSkippedDateHasNoButtonAndFollowingDayKeepsItsWeekday() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 1
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2011, month: 12, day: 30, hour: 12)))
        let controller = try await loadedController(date: date, calendar: calendar)
        let grid = try XCTUnwrap(element("moonCalendar.grid", in: controller.view) as? UIStackView)
        controller.refreshCalendar(timeZone: try XCTUnwrap(TimeZone(identifier: "Pacific/Apia")))
        let refreshed = XCTNSPredicateExpectation(predicate: NSPredicate { [weak self] _, _ in
            grid.isUserInteractionEnabled && self?.element("moonCalendar.day.30", in: controller.view) == nil
        }, object: nil)
        await fulfillment(of: [refreshed], timeout: 10)
        let lastDay = try XCTUnwrap(element("moonCalendar.day.31", in: controller.view) as? UIButton)
        let row = try XCTUnwrap(lastDay.superview as? UIStackView)
        XCTAssertEqual(row.arrangedSubviews.firstIndex(of: lastDay), 6, "December 31 is Saturday")
        XCTAssertFalse(row.arrangedSubviews[5] is UIButton, "The skipped Friday must stay empty")
        XCTAssertTrue(lastDay.accessibilityTraits.contains(.selected))
        let rows = grid.arrangedSubviews.compactMap { $0 as? UIStackView }
        XCTAssertEqual(rows.flatMap(\.arrangedSubviews).filter { $0 is UIButton }.count, 30)
        XCTAssertTrue(try XCTUnwrap(element("moonCalendar.selectedDate", in: controller.view) as? UILabel).text?.contains("31") == true)
    }
}
