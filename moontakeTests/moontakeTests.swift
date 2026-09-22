import XCTest
@testable import moontake
@testable import MoreKit

final class moontakeTests: XCTestCase {
    @MainActor
    func testLaunchConfiguresExistingMembershipProductAndCache() {
        XCTAssertEqual(MoreKit.productID, "com.zizicici.moontake.iap.lifetime")
        XCTAssertEqual(MoreKit.membershipKey, UserDefaults.Custom.LifetimeMemberShip.rawValue)
        XCTAssertTrue(MoreKit.ownsStoreKit)
    }

    @MainActor
    func testFreeUserCannotSaveProOnlyOptions() {
        withMembership(false) {
            XCTAssertTrue(Settings.shared.save(option: Settings.SaveToAlbumOption.photoWithWatermark))
            XCTAssertFalse(Settings.shared.save(option: Settings.SaveToAlbumOption.photoWithoutWatermark))
            XCTAssertFalse(Settings.shared.save(option: Settings.SaveToAlbumOption.both))
            XCTAssertEqual(Settings.shared.getSaveToAlbumSettings(), .photoWithWatermark)
            XCTAssertTrue(Settings.shared.save(option: Settings.AppAlbumOption.enable))
            XCTAssertFalse(Settings.shared.save(option: Settings.AppAlbumOption.disable))
            XCTAssertEqual(Settings.shared.getAppAlbumSettings(), .enable)
        }
    }

    @MainActor
    func testProUserCanSaveOriginalsAndDisableAppAlbum() {
        withMembership(true) {
            XCTAssertTrue(Settings.shared.save(option: Settings.SaveToAlbumOption.photoWithoutWatermark))
            XCTAssertEqual(Settings.shared.getSaveToAlbumSettings(), .photoWithoutWatermark)
            XCTAssertTrue(Settings.shared.save(option: Settings.SaveToAlbumOption.both))
            XCTAssertEqual(Settings.shared.getSaveToAlbumSettings(), .both)
            XCTAssertTrue(Settings.shared.save(option: Settings.AppAlbumOption.disable))
            XCTAssertEqual(Settings.shared.getAppAlbumSettings(), .disable)
        }
    }

    @MainActor
    func testMissingEntitlementKeepsMembershipButRevocationClearsCache() {
        withMembership(true) {
            let key = UserDefaults.Custom.LifetimeMemberShip.rawValue
            XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
            Store.shared.applyReconciledOutcome(.missing)
            XCTAssertEqual(User.shared.proTier(), .lifetime)
            XCTAssertTrue(UserDefaults.standard.bool(forKey: key))
            Store.shared.applyReconciledOutcome(.revoked)
            XCTAssertEqual(User.shared.proTier(), .none)
            XCTAssertFalse(UserDefaults.standard.bool(forKey: key))
            XCTAssertFalse(Settings.shared.save(option: Settings.SaveToAlbumOption.photoWithoutWatermark))
        }
    }

    @MainActor
    func testAlbumReloadsOnBothMembershipGrantAndRevocation() {
        withMembership(false) {
            let album = ReloadTrackingAlbumViewController()
            album.loadViewIfNeeded()
            let initialCount = album.reloadCount
            Store.shared.applyReconciledOutcome(.owned)
            XCTAssertEqual(album.reloadCount, initialCount + 1)
            Store.shared.applyReconciledOutcome(.revoked)
            XCTAssertEqual(album.reloadCount, initialCount + 2)
        }
    }

    // Exercise MoreKit's deterministic state transition seam, without StoreKit purchases.
    @MainActor
    private func withMembership(_ active: Bool, body: () -> Void) {
        let originalMembership = Store.shared.hasValidMembership()
        let keys = [UserDefaults.Custom.AppAlbum.rawValue, UserDefaults.Custom.SaveToAlbum.rawValue]
        let savedValues = keys.map { UserDefaults.standard.object(forKey: $0) }
        defer {
            Store.shared.applyMembership(originalMembership)
            for (key, value) in zip(keys, savedValues) {
                if let value {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
        Store.shared.applyMembership(active)
        body()
    }
}

private final class ReloadTrackingAlbumViewController: AlbumViewController {
    var reloadCount = 0

    override func reloadData() {
        reloadCount += 1
    }
}
