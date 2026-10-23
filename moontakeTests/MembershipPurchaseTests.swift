import UIKit
import XCTest
import StoreKit
import StoreKitTest
@testable import MoreKit
@testable import moontake

@available(iOS 17.0, *)
@MainActor
final class MembershipPurchaseTests: XCTestCase {
    private var session: SKTestSession!
    private var savedLifetime = false
    private var savedSubscriptions: [SubscriptionMembership] = []
    private var preferences: [String: Any] = [:]
    private let preferenceKeys = [UserDefaults.Custom.AppAlbum.rawValue, UserDefaults.Custom.SaveToAlbum.rawValue]

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["MOONTAKE_STOREKIT_TESTS"] == "1" else {
            throw XCTSkip("Run the moontake StoreKit scheme to use local test products.")
        }
        savedLifetime = Store.shared.proTier() == .lifetime
        savedSubscriptions = Store.shared.activeSubscriptions()
        for key in preferenceKeys { preferences[key] = UserDefaults.standard.object(forKey: key) }
        session = try SKTestSession(contentsOf: XCTUnwrap(Bundle(for: Self.self).url(forResource: "Memberships", withExtension: "storekit")))
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        session.askToBuyEnabled = false
        Store.shared.applyMembership(false)
        clearSubscriptions()
    }

    override func tearDownWithError() throws {
        guard session != nil else { return }
        session.clearTransactions()
        session.resetToDefaultState()
        clearSubscriptions()
        Store.shared.applyMembership(savedLifetime)
        Store.shared.applySubscriptionOutcomes(Dictionary(uniqueKeysWithValues: savedSubscriptions.map { ($0.productID, .active($0)) }))
        for key in preferenceKeys { UserDefaults.standard.set(preferences[key], forKey: key) }
    }

    func testMonthlyPurchaseRestoreAndCancellationKeepsAccess() async throws {
        try await loadProducts()
        guard case .success = try await Store.shared.purchase(productID: ProStatus.monthlyProductID) else {
            return XCTFail("Monthly purchase failed")
        }
        XCTAssertTrue(ProStatus.isPro)
        XCTAssertEqual(Store.shared.proTier(), .subscription)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: UserDefaults.Custom.LifetimeMemberShip.rawValue))
        XCTAssertTrue(Settings.shared.save(option: Settings.SaveToAlbumOption.both))
        XCTAssertTrue(Settings.shared.save(option: Settings.AppAlbumOption.disable))
        XCTAssertEqual(Settings.shared.getSaveToAlbumSettings(), .both)
        XCTAssertEqual(Settings.shared.getAppAlbumSettings(), .disable)
        XCTAssertFalse(HintInfo.normal(.subscription).shouldShowPurchaseEntry)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
        for _ in 0..<50 {
            await Store.shared.updateCustomerProductStatus()
            if Store.shared.activeSubscriptions().first?.willAutoRenew == false { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(ProStatus.isPro)
        XCTAssertEqual(Store.shared.activeSubscriptions().first?.willAutoRenew, false)
        clearSubscriptions()
        let restored = try await Store.shared.syncMembershipStatus()
        XCTAssertTrue(restored)
        XCTAssertTrue(ProStatus.isPro)
    }

    func testExpiryFallsBackWithoutErasingPreferences() async throws {
        session.timeRate = .oneRenewalEveryTwoSeconds
        try await loadProducts()
        _ = try await Store.shared.purchase(productID: ProStatus.monthlyProductID)
        XCTAssertTrue(Settings.shared.save(option: Settings.SaveToAlbumOption.both))
        XCTAssertTrue(Settings.shared.save(option: Settings.AppAlbumOption.disable))
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
        for _ in 0..<100 {
            await Store.shared.updateCustomerProductStatus()
            if !ProStatus.isPro { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(ProStatus.isPro)
        XCTAssertEqual(Settings.shared.getSaveToAlbumSettings(), .photoWithWatermark)
        XCTAssertEqual(Settings.shared.getAppAlbumSettings(), .enable)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: preferenceKeys[0]), Settings.AppAlbumOption.disable.rawValue)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: preferenceKeys[1]), Settings.SaveToAlbumOption.both.rawValue)
    }

    func testLifetimeUpgradeSurvivesSubscriptionRefundAndPreventsRepurchase() async throws {
        try await loadProducts()
        _ = try await Store.shared.purchase(productID: ProStatus.monthlyProductID)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        _ = try await Store.shared.purchaseLifetimeMembership()
        try session.refundTransaction(identifier: transaction.identifier)
        await Store.shared.updateCustomerProductStatus()
        XCTAssertEqual(Store.shared.proTier(), .lifetime)
        for id in ProStatus.displayProductIDs {
            guard case .alreadyOwned = try await Store.shared.purchase(productID: id) else { return XCTFail("Duplicate purchase") }
        }
        let page = makePaywall()
        XCTAssertNil(find("paywall.plans", in: page.view))
        XCTAssertEqual(find("paywall.purchase", in: page.view)?.isEnabled, true)
    }

    func testExistingLifetimeRestoresUsingOriginalIdentifier() async throws {
        try await loadProducts()
        _ = try await session.buyProduct(identifier: "com.zizicici.moontake.iap.lifetime", options: [.purchaseDate(Date().addingTimeInterval(-90 * 86400))])
        Store.shared.applyMembership(false)
        let restored = try await Store.shared.syncMembershipStatus()
        XCTAssertTrue(restored)
        XCTAssertEqual(Store.shared.proTier(), .lifetime)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "com.zizicici.moontake.store.purchase.lifetime"))
    }

    func testPendingDoesNotUnlockUntilApproved() async throws {
        try await loadProducts()
        session.askToBuyEnabled = true
        guard case .pending = try await Store.shared.purchase(productID: ProStatus.monthlyProductID) else { return XCTFail("Expected pending") }
        XCTAssertFalse(ProStatus.isPro)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: transaction.identifier)
        for _ in 0..<50 {
            await Store.shared.updateCustomerProductStatus()
            if ProStatus.isPro { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(ProStatus.isPro)
    }

    func testPaywallDefaultsToYearlyAndUsesStorePrices() async throws {
        try await loadProducts()
        let page = makePaywall()
        XCTAssertEqual(page.selectedProductID, ProStatus.yearlyProductID)
        for product in Store.shared.memberships {
            let card = try XCTUnwrap(find("paywall.product." + product.id, in: page.view))
            XCTAssertTrue(card.accessibilityLabel?.contains(product.displayPrice) == true)
            if product.id != ProStatus.yearlyProductID { XCTAssertNil(product.subscription?.introductoryOffer) }
        }
        let monthly = try XCTUnwrap(find("paywall.product." + ProStatus.monthlyProductID, in: page.view))
        monthly.sendActions(for: .touchUpInside)
        XCTAssertEqual(page.selectedProductID, ProStatus.monthlyProductID)
        let text = try XCTUnwrap(allViews(page.view).first { $0.accessibilityIdentifier == "paywall.disclosure" } as? UILabel)
        XCTAssertTrue(text.text?.contains(try XCTUnwrap(Store.shared.memberships.first { $0.id == ProStatus.monthlyProductID }).displayPrice) == true)
        XCTAssertNotNil(find("paywall.restore", in: page.view))
        let lifetime = try XCTUnwrap(find("paywall.product." + ProStatus.productID, in: page.view))
        lifetime.sendActions(for: .touchUpInside)
        XCTAssertEqual(page.selectedProductID, ProStatus.productID)
        for width in [320.0, 393.0, 852.0] {
            page.view.frame = CGRect(x: 0, y: 0, width: width, height: 852)
            page.view.layoutIfNeeded()
            let purchase = try XCTUnwrap(find("paywall.purchase", in: page.view))
            XCTAssertGreaterThan(purchase.bounds.width, 0)
            XCTAssertLessThanOrEqual(purchase.convert(purchase.bounds, to: page.view).maxX, width)
            let cards = ProStatus.displayProductIDs.compactMap { find("paywall.product." + $0, in: page.view) }
            XCTAssertEqual(cards.count, 3)
            let frames = cards.map { $0.convert($0.bounds, to: page.view) }
            XCTAssertEqual(Set(frames.map(\.minY)).count, 1, "All plans must share one row")
            XCTAssertLessThan(frames[0].minX, frames[1].minX)
            XCTAssertLessThan(frames[1].minX, frames[2].minX)
            XCTAssertTrue(frames.allSatisfy { $0.width > 0 && $0.maxX <= width && $0.minX >= 0 })
        }
    }

    func testYearlyTrialEligibilityPurchaseRestoreAndExpiry() async throws {
        // Let the signed trial transaction expire naturally. force-expire changes
        // StoreKit Test's renewal status but can leave its signed date in the future.
        session.timeRate = .monthlyRenewalEveryThirtySeconds
        try await loadProducts()
        let yearly = try XCTUnwrap(Store.shared.memberships.first { $0.id == ProStatus.yearlyProductID })
        let subscription = try XCTUnwrap(yearly.subscription)
        XCTAssertEqual(subscription.subscriptionPeriod.unit, .year)
        XCTAssertEqual(subscription.subscriptionPeriod.value, 1)
        let offer = try XCTUnwrap(subscription.introductoryOffer)
        XCTAssertEqual(offer.paymentMode, .freeTrial)
        XCTAssertEqual(offer.period.unit, .day)
        XCTAssertEqual(offer.period.value, 3)
        let page = makePaywall()
        await page.refreshIntroEligibility()
        find("paywall.product." + ProStatus.yearlyProductID, in: page.view)?.sendActions(for: .touchUpInside)
        let purchase = try XCTUnwrap(find("paywall.purchase", in: page.view) as? UIButton)
        XCTAssertEqual(purchase.configuration?.title, String(localized: "paywall.trial.start"))
        let disclosure = try XCTUnwrap(allViews(page.view).first { $0.accessibilityIdentifier == "paywall.disclosure" } as? UILabel)
        XCTAssertTrue(disclosure.text?.contains(yearly.displayPrice) == true)
        guard case .success = try await Store.shared.purchase(productID: yearly.id) else { return XCTFail("Yearly trial failed") }
        XCTAssertTrue(ProStatus.isPro)
        let transaction = try XCTUnwrap(session.allTransactions().first)
        try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
        clearSubscriptions()
        let restored = try await Store.shared.syncMembershipStatus()
        XCTAssertTrue(restored)
        for _ in 0..<150 {
            await Store.shared.updateCustomerProductStatus()
            if !ProStatus.isPro { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(ProStatus.isPro)
        await page.refreshIntroEligibility()
        XCTAssertEqual(purchase.configuration?.title, String(localized: "paywall.subscribe"), "A used trial must not be offered again")
    }

    func testSubscribedUserCanSeeManageAndLifetimeUpgradeWarning() async throws {
        try await loadProducts()
        _ = try await Store.shared.purchase(productID: ProStatus.monthlyProductID)
        let page = makePaywall()
        XCTAssertEqual(page.selectedProductID, ProStatus.yearlyProductID)
        XCTAssertNotNil(find("paywall.manage", in: page.view))
        find("paywall.product." + ProStatus.productID, in: page.view)?.sendActions(for: .touchUpInside)
        let disclosure = try XCTUnwrap(allViews(page.view).first { $0.accessibilityIdentifier == "paywall.disclosure" } as? UILabel)
        XCTAssertTrue(disclosure.text?.contains(String(localized: "paywall.lifetimeWhileSubscribed")) == true)
        find("paywall.product." + ProStatus.monthlyProductID, in: page.view)?.sendActions(for: .touchUpInside)
        XCTAssertEqual(find("paywall.purchase", in: page.view)?.isEnabled, false)
    }

    func testPaywallVisualSnapshots() async throws {
        try await loadProducts()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let previous = scene.keyWindow
        let page = makePaywall()
        window.rootViewController = page
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(400))
        await page.refreshIntroEligibility()
        for style in [UIUserInterfaceStyle.light, .dark] {
            window.overrideUserInterfaceStyle = style
            try await Task.sleep(for: .milliseconds(300))
            page.view.layoutIfNeeded()
            let comparison = try XCTUnwrap(allViews(page.view).first { $0.accessibilityIdentifier == "paywall.comparison" })
            let plans = try XCTUnwrap(allViews(page.view).first { $0.accessibilityIdentifier == "paywall.plans" })
            XCTAssertLessThan(comparison.convert(comparison.bounds, to: window).maxY, plans.convert(plans.bounds, to: window).minY)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let name = style == .dark ? "paywall-dark" : "paywall-light"
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name + ".png")
            try image.pngData()?.write(to: file)
        }
        let scroll = try XCTUnwrap(allViews(page.view).first { $0.accessibilityIdentifier == "paywall.scroll" } as? UIScrollView)
        let card = try XCTUnwrap(find("paywall.product." + ProStatus.monthlyProductID, in: page.view))
        scroll.scrollRectToVisible(card.convert(card.bounds, to: scroll), animated: false)
        card.sendActions(for: .touchUpInside)
        page.view.layoutIfNeeded()
        let dock = try XCTUnwrap(allViews(page.view).first { $0.accessibilityIdentifier == "paywall.dock" })
        let cardFrame = card.convert(card.bounds, to: window)
        XCTAssertGreaterThanOrEqual(cardFrame.minY, window.safeAreaInsets.top)
        XCTAssertLessThanOrEqual(cardFrame.maxY, dock.convert(dock.bounds, to: window).minY, "Every plan must be reachable above the purchase dock by scrolling")
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try image.pngData()?.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("paywall-monthly.png"))
        find("paywall.product." + ProStatus.yearlyProductID, in: page.view)?.sendActions(for: .touchUpInside)
        page.view.layoutIfNeeded()
        let annual = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try annual.pngData()?.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("paywall-yearly.png"))
    }

    func testMissingProductsDisablesUnpricedPurchase() {
        let store = Store()
        let page = MoontakePaywallViewController(configuration: .init(
            title: MoontakeProBenefits.title, features: MoontakeProBenefits.features,
            productIDs: ProStatus.displayProductIDs, privacyPolicyURL: URL(string: "https://example.com/privacy")!
        ), store: store)
        page.loadViewIfNeeded()
        XCTAssertEqual(page.selectedProductID, ProStatus.yearlyProductID)
        XCTAssertEqual(find("paywall.purchase", in: page.view)?.isEnabled, false)
        XCTAssertNotNil(find("paywall.restore", in: page.view))
        XCTAssertNil(find("paywall.product." + ProStatus.monthlyProductID, in: page.view))
    }

    func testMoreEntryPresentsFullScreenPaywall() async throws {
        try await loadProducts()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let more = makeMorePageViewController()
        window.rootViewController = UINavigationController(rootViewController: more)
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(250))
        more.view.layoutIfNeeded()
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try screenshot.pngData()?.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("paywall-entry.png"))
        let entry = try XCTUnwrap(find("settings.proEntry.open", in: more.view))
        entry.sendActions(for: .touchUpInside)
        try await Task.sleep(for: .milliseconds(400))
        let paywall = try XCTUnwrap(more.presentedViewController as? MoontakePaywallViewController)
        XCTAssertEqual(paywall.modalPresentationStyle, .fullScreen)
        XCTAssertEqual(paywall.selectedProductID, ProStatus.yearlyProductID)
        XCTAssertNotNil(find("paywall.product." + ProStatus.monthlyProductID, in: paywall.view))
        paywall.dismiss(animated: false)
    }

    private func loadProducts() async throws {
        for _ in 0..<30 {
            await Store.shared.requestProducts()
            if Set(Store.shared.memberships.map(\.id)) == Set(ProStatus.displayProductIDs) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "MembershipTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local StoreKit catalog did not load. Configured: \(MoreKit.membershipProductIDs); loaded: \(Store.shared.memberships.map(\.id)); loading: \(Store.shared.isLoadingProducts); error: \(String(describing: Store.shared.productsError))"])
    }

    private func clearSubscriptions() {
        Store.shared.applySubscriptionOutcomes(Dictionary(uniqueKeysWithValues: ProStatus.subscriptionProductIDs.map { ($0, .inactive) }))
    }

    private func makePaywall() -> MoontakePaywallViewController {
        let page = MoontakePaywallViewController(configuration: .init(title: MoontakeProBenefits.title,
            features: MoontakeProBenefits.features, productIDs: ProStatus.displayProductIDs,
            privacyPolicyURL: URL(string: "https://zizicici.medium.com/policy-of-privacy-for-moontake-afc746183ab7")!))
        page.loadViewIfNeeded()
        page.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        page.view.layoutIfNeeded()
        return page
    }

    private func allViews(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(allViews) }
    private func find(_ id: String, in view: UIView) -> UIControl? {
        allViews(view).first { $0.accessibilityIdentifier == id } as? UIControl
    }
}
