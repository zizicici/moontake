import Photos
import GRDB
import UIKit
import XCTest
@testable import moontake

final class CaptureSavingTests: XCTestCase {
    private func photo(color: UIColor = .darkGray, movieURL: URL? = nil, resources: LivePhotoResources? = nil) throws -> CapturedPhoto {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let data = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200), format: format).jpegData(withCompressionQuality: 0.8) { context in
            color.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        }
        return CapturedPhoto(data: data, fileType: .jpeg, width: 1600, height: 1200,
                             date: Date(timeIntervalSince1970: 1792713600), location: nil, locationName: nil,
                             targets: [.watermark], movieURL: movieURL, resources: resources)
    }

    func testDestinationsAreIndependentForStillAndLivePhotos() async throws {
        let resources = try LivePhotoResources()
        let background = LivePhotoBackgroundTask(begin: { _ in .invalid }, end: { _ in })
        try Data([1, 2, 3]).write(to: resources.movieURL)
        for live in [false, true] {
            let capture = try photo(movieURL: live ? resources.movieURL : nil, resources: live ? resources : nil)
            for status: PHAuthorizationStatus in [.denied, .restricted, .notDetermined, .authorized, .limited] {
                for localEnabled in [false, true] {
                    for localWorks in [false, true] {
                        for photosWorks in [false, true] {
                            var localCalls = 0, photoCalls = 0
                            let saver = CapturePhotoSaver(authorization: { status }, saveLocal: { saved in
                                localCalls += 1
                                XCTAssertEqual(saved.data, capture.data)
                                XCTAssertEqual(saved.movieURL, capture.movieURL)
                                return localWorks
                            }, savePhotos: { saved, inheritedBackground in
                                photoCalls += 1
                                XCTAssertTrue(inheritedBackground === background)
                                XCTAssertEqual(localCalls, localEnabled ? 1 : 0, "Local save precedes Photos")
                                XCTAssertEqual(saved.movieURL, capture.movieURL)
                                if !photosWorks { throw CocoaError(.fileWriteOutOfSpace) }
                            })
                            let result = await saver.save(capture, toLocalAlbum: localEnabled, backgroundTask: background)
                            let allowed = status == .authorized || status == .limited
                            XCTAssertEqual(localCalls, localEnabled ? 1 : 0)
                            XCTAssertEqual(photoCalls, allowed ? 1 : 0)
                            XCTAssertEqual(result.localSaved, localEnabled && localWorks)
                            XCTAssertEqual(result.photosSaved, allowed && photosWorks)
                            XCTAssertEqual(result.needsTemporaryDetail, !(localEnabled && localWorks) && !(allowed && photosWorks))
                        }
                    }
                }
            }
        }
    }

    func testTemporaryShareUsesFinishedWatermarkedPhoto() async throws {
        let source = try photo()
        let exported = try await TemporaryPhotoExport.prepare(source, target: .watermark, cancellation: LivePhotoCancellation())
        let image = try XCTUnwrap(UIImage(data: exported.data))
        XCTAssertEqual(image.size.height, 1560)
        XCTAssertEqual(image.size.width, 1600)
        XCTAssertNotEqual(exported.data, source.data)
        let providers = exported.itemProviders()
        XCTAssertEqual(providers.count, 1)
        let received: Data = try await withCheckedThrowingContinuation { continuation in
            providers[0].loadDataRepresentation(forTypeIdentifier: exported.fileType.system.rawValue) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown)) }
            }
        }
        XCTAssertEqual(received, exported.data)
    }

    func testDeniedPhotosStillWritesTheLocalAlbumForStillAndLive() async throws {
        let reader = try XCTUnwrap(AppDatabase.shared.reader)
        let resources = try LivePhotoResources()
        try Data([4, 5, 6]).write(to: resources.movieURL)
        for live in [false, true] {
            let before = try await reader.read { try Set(ImageInfo.fetchAll($0).map(\.dataId)) }
            let capture = try photo(movieURL: live ? resources.movieURL : nil, resources: live ? resources : nil)
            let saver = CapturePhotoSaver(authorization: { .denied }, savePhotos: { _, _ in
                XCTFail("Denied access must not start a system-library save")
            })
            let result = await saver.save(capture, toLocalAlbum: true)
            let inserted = try await reader.read { try ImageInfo.fetchAll($0).filter { !before.contains($0.dataId) } }
            defer {
                for info in inserted {
                    _ = AppDatabase.shared.delete(imageInfo: info)
                    for url in [info.originURL, info.thumbnailURL, info.pairedVideoURL].compactMap({ $0 }) {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
            XCTAssertTrue(result.localSaved)
            XCTAssertFalse(result.needsTemporaryDetail)
            XCTAssertEqual(inserted.count, 1)
            let saved = try XCTUnwrap(inserted.first)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(saved.originURL)), capture.data)
            XCTAssertEqual(saved.creationTime, capture.date.nanoSecondSince1970)
            XCTAssertEqual(saved.hasLivePhoto, live)
            if live { XCTAssertEqual(try Data(contentsOf: XCTUnwrap(saved.pairedVideoURL)), Data([4, 5, 6])) }
        }
    }

    @MainActor
    func testDeniedPhotoPermissionDoesNotCoverCameraAndTemporaryShareCanBeCancelled() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let suite = "capture-fallback-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let progress = CameraTutorialProgress(defaults: defaults)
        progress.complete()
        CameraTutorialStep.tips.forEach { progress.recordTipShown($0) }
        let camera = CaptureTestCamera(tutorialProgress: progress)
        window.rootViewController = camera
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
            defaults.removePersistentDomain(forName: suite)
        }
        await waitUntil { camera.view.window != nil }
        let permission = try XCTUnwrap(camera.view.subviews.first { $0 is PermissionView })
        XCTAssertTrue(permission.isHidden, "Denied Photos access must not cover the camera")
        camera.presentTemporaryPhoto(try photo())
        await waitUntil { camera.presentedViewController is ImageDetailViewController }
        let detail = try XCTUnwrap(camera.presentedViewController as? ImageDetailViewController)
        await waitUntil { self.find("photo.temporary.share", in: detail.view) != nil }
        let share = try XCTUnwrap(find("photo.temporary.share", in: detail.view) as? UIButton)
        XCTAssertEqual(share.accessibilityLabel, String(localized: "photo.share.title"))
        XCTAssertEqual(share.menu?.children.count, 2)
        await waitUntil { self.imageCell(in: detail.view)?.imageView?.image != nil }
        let preview = try XCTUnwrap(imageCell(in: detail.view)?.imageView?.image)
        XCTAssertEqual(preview.size, CGSize(width: 1600, height: 1200), "Detail must show the original without a watermark")
        try saveSnapshot(window)
        detail.shareTemporaryPhoto(target: .watermark)
        await waitUntil { detail.presentedViewController is UIActivityViewController }
        XCTAssertTrue(detail.presentedViewController is UIActivityViewController)
        detail.dismiss(animated: false)
        await waitUntil { detail.presentedViewController == nil }
        XCTAssertTrue(camera.presentedViewController === detail, "Cancelling share must retain the photo")
        XCTAssertTrue(share.isEnabled)
        let close = try XCTUnwrap(find("photo.temporary.close", in: detail.view) as? UIButton)
        close.sendActions(for: .touchUpInside)
        await waitUntil { detail.presentedViewController is UIAlertController }
        let alert = try XCTUnwrap(detail.presentedViewController as? UIAlertController)
        XCTAssertEqual(alert.actions.map(\.style), [.cancel, .destructive])
        XCTAssertTrue(detail.isModalInPresentation)
        try saveSnapshot(window)
        camera.dismiss(animated: false)
    }

    @MainActor
    func testSavedRecognizableCaptureOpensShareDetailOnceWithoutUnsavedWarning() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let suite = "monthly-camera-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let tutorial = CameraTutorialProgress(defaults: defaults)
        tutorial.complete(); CameraTutorialStep.tips.forEach { tutorial.recordTipShown($0) }
        var assessments = 0
        let prompt = MonthlyMoonSharePrompt(defaults: defaults, isEnabled: { true }) { _, _, _, _ in
            assessments += 1; return true
        }
        let camera = CaptureTestCamera(tutorialProgress: tutorial, moonSharePrompt: prompt)
        window.rootViewController = camera; window.makeKeyAndVisible()
        defer {
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
            defaults.removePersistentDomain(forName: suite)
        }
        await waitUntil { camera.view.window != nil }
        let capture = try photo()
        camera.handleSavedCapture(capture, outcome: CaptureSaveOutcome(localSaved: true, photosSaved: false))
        await waitUntil { prompt.hasPresented(in: capture.date) }
        let detail = try XCTUnwrap(camera.presentedViewController as? ImageDetailViewController)
        XCTAssertEqual(detail.view.accessibilityIdentifier, "photo.sharePreview")
        XCTAssertFalse(detail.isModalInPresentation)
        await waitUntil { self.find("photo.temporary.close", in: detail.view) != nil }
        let close = try XCTUnwrap(find("photo.temporary.close", in: detail.view) as? UIButton)
        try saveSnapshot(window)
        close.sendActions(for: .touchUpInside)
        await waitUntil { camera.presentedViewController == nil }
        camera.handleSavedCapture(capture, outcome: CaptureSaveOutcome(localSaved: false, photosSaved: true))
        XCTAssertEqual(assessments, 1)
        XCTAssertNil(camera.presentedViewController)
    }

    @MainActor
    func testBlackCaptureDoesNotPresentAnEarlierReadyCandidate() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let suite = "monthly-camera-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let tutorial = CameraTutorialProgress(defaults: defaults)
        tutorial.complete(); CameraTutorialStep.tips.forEach { tutorial.recordTipShown($0) }
        let older = try photo(), black = try photo(color: .black)
        var assessed: [Data] = []
        let prompt = MonthlyMoonSharePrompt(defaults: defaults, isEnabled: { true }) { data, _, _, _ in
            assessed.append(data)
            return data == older.data
        }
        let camera = CaptureTestCamera(tutorialProgress: tutorial, moonSharePrompt: prompt)
        defer {
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
            defaults.removePersistentDomain(forName: suite)
        }
        // Let recognition finish while the camera is off screen, so only the
        // pending presentation remains when the newer black capture is delivered.
        prompt.consider(older)
        await waitUntil { prompt.pendingPhoto != nil }
        let saved = CaptureSaveOutcome(localSaved: true, photosSaved: true)
        camera.handleSavedCapture(black, outcome: saved)
        window.rootViewController = camera; window.makeKeyAndVisible()
        await waitUntil { assessed.count == 2 && camera.view.window != nil }
        XCTAssertEqual(assessed, [older.data, black.data])
        XCTAssertNil(prompt.pendingPhoto)
        XCTAssertNil(camera.presentedViewController, "Returning to the camera must not reveal the earlier photo")
        XCTAssertFalse(prompt.hasPresented(in: black.date))

        camera.handleSavedCapture(older, outcome: saved)
        await waitUntil { prompt.hasPresented(in: older.date) }
        XCTAssertEqual(assessed.count, 3)
        XCTAssertTrue(camera.presentedViewController is ImageDetailViewController)
        camera.dismiss(animated: false)
    }

    @MainActor private func find(_ identifier: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == identifier { return view }
        return view.subviews.compactMap { find(identifier, in: $0) }.first
    }
    @MainActor private func imageCell(in view: UIView) -> ImageDetailCell? {
        if let cell = view as? ImageDetailCell { return cell }
        return view.subviews.compactMap { imageCell(in: $0) }.first
    }

    @MainActor private func waitUntil(_ predicate: () -> Bool) async {
        for _ in 0..<150 {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Timed out waiting for UI")
    }
    @MainActor private func saveSnapshot(_ window: UIWindow) throws {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Shared photo detail"; attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor private final class CaptureTestCamera: CameraViewController {
    override func checkCameraPermissions() { cameraPermissionAuthorized = .authorized }
    override func checkPhotoPremissions() { addPhotoPermissionAuthorized = .denied }
    override func setupAndStartCaptureSession() {}
    override func initializeMotionManager() {}
}
