import XCTest
import UIKit
import SkyKit
@testable import moontake

final class MoonAtlasTests: XCTestCase {
    private func fixture(blank: Bool = false) throws -> (ImageInfo, URL) {
        let info = ImageInfo(creationTime: 1_767_225_600_000, dataId: "atlas-test-\(UUID().uuidString)", fileType: .jpeg, width: 1600, height: 1200)
        let source = try XCTUnwrap(Bundle(for: MoonAtlasTests.self).url(forResource: "example-nasa", withExtension: "jpg"))
        let moon = try XCTUnwrap(UIImage(contentsOfFile: source.path))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200), format: format).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
            if !blank { moon.draw(in: CGRect(x: 930, y: 300, width: 320, height: 320)) }
        }
        let url = try XCTUnwrap(info.originURL)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try XCTUnwrap(image.jpegData(compressionQuality: 0.96)).write(to: url)
        return (info, url)
    }

    func testNativeEngineRecoversOffCenterMoonAndPreservesCaptureTime() async throws {
        let (info, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = MoonAtlasEngine()
        let photo = try await engine.load(info)
        let date = try XCTUnwrap(photo.captureDate)
        XCTAssertEqual(ISO8601DateFormatter().string(from: date), "2026-01-01T00:00:00Z")
        let result = try await engine.recognize(photo, at: date)
        XCTAssertEqual(result.fit.accepted, true)
        XCTAssertEqual(result.fit.x, 1090, accuracy: 4)
        XCTAssertEqual(result.fit.y, 460, accuracy: 4)
        XCTAssertEqual(result.fit.radius, 152, accuracy: 4)
        XCTAssertLessThan(min(result.fit.rotation, 360 - result.fit.rotation), 3)
        XCTAssertEqual(result.reference.size, CGSize(width: 640, height: 640))
        XCTAssertEqual(result.features.filter { $0.type == "mare" }.count, 15)
    }

    func testNativeEngineMatchesSoftFullMoonAndRejectsWrongMirror() async throws {
        let source = try XCTUnwrap(Bundle(for: MoonAtlasTests.self).url(forResource: "soft-full-moon", withExtension: "png"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: source.path))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-30T16:26:09Z"))
        let photo = MoonAtlasPhoto(image: image, captureDate: date, latitude: nil, longitude: nil)
        let engine = MoonAtlasEngine()
        let result = try await engine.recognize(photo, at: date)
        XCTAssertEqual(result.fit.accepted, true)
        XCTAssertEqual(result.fit.x, 64, accuracy: 3)
        XCTAssertEqual(result.fit.y, 64, accuracy: 3)
        XCTAssertEqual(result.fit.radius, 39, accuracy: 3)
        XCTAssertEqual(result.fit.rotation, 292, accuracy: 5)
        let mirrored = try await engine.recognize(photo, at: date, mirror: true)
        XCTAssertEqual(mirrored.fit.accepted, false)
    }

    @MainActor
    func testNativeEngineMatchesGibbousPhotosAndHidesUnlitFeatures() async throws {
        let fixtures: [(name: String, date: String, x: Double, y: Double, radius: Double, rotation: Double)] = [
            ("soft-gibbous-moon-may", "2026-05-25T11:31:40Z", 62.5, 64.3, 28.6, 344.5),
            ("soft-gibbous-moon-september", "2026-09-21T10:33:03Z", 62.8, 64.7, 31.4, 337.9)
        ]
        for fixture in fixtures {
            let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: fixture.name, withExtension: "png"))
            let image = try XCTUnwrap(UIImage(contentsOfFile: source.path))
            let date = try XCTUnwrap(ISO8601DateFormatter().date(from: fixture.date))
            let photo = MoonAtlasPhoto(image: image, captureDate: date, latitude: nil, longitude: nil)
            let engine = MoonAtlasEngine()
            let result = try await engine.recognize(photo, at: date)
            XCTAssertEqual(result.fit.accepted, true, fixture.name)
            XCTAssertEqual(result.fit.x, fixture.x, accuracy: 3)
            XCTAssertEqual(result.fit.y, fixture.y, accuracy: 3)
            XCTAssertEqual(result.fit.radius, fixture.radius, accuracy: 3)
            XCTAssertEqual(result.fit.rotation, fixture.rotation, accuracy: 5)
            let mirrored = try await engine.recognize(photo, at: date, mirror: true)
            XCTAssertEqual(mirrored.fit.accepted, false, fixture.name)

            let view = MoonAtlasPhotoView(frame: CGRect(x: 0, y: 0, width: 393, height: 650))
            view.setPhoto(image)
            view.setResult(result)
            view.focusOnMoon(animated: false)
            view.layoutIfNeeded()
            let visible = Set(descendants(UIButton.self, in: view).filter { !$0.isHidden && $0.alpha > 0 }
                .compactMap { $0.accessibilityIdentifier })
            XCTAssertGreaterThanOrEqual(view.visibleAnnotationCount, 5)
            var unlitCount = 0
            for feature in result.features {
                let coordinate = try XCTUnwrap(MoonSurfaceCoordinate(latitude: feature.latitude, longitude: feature.longitude))
                let point = try XCTUnwrap(result.surface.project(coordinate))
                if point.incidenceCosine <= 0.08 {
                    unlitCount += 1
                    XCTAssertFalse(visible.contains("atlas.feature.\(feature.id)"), "Unlit \(feature.name) should not be labeled")
                }
            }
            XCTAssertGreaterThan(unlitCount, 0)
        }
    }

    @MainActor
    func testNativeEngineFindsDaylightMoonAndRejectsTheCloudsAlone() async throws {
        let source = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "daylight-moon", withExtension: "jpg"))
        let image = try XCTUnwrap(UIImage(contentsOfFile: source.path))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-04-28T10:08:35Z"))
        let photo = MoonAtlasPhoto(image: image, captureDate: date, latitude: nil, longitude: nil)
        let engine = MoonAtlasEngine()
        let result = try await engine.recognize(photo, at: date)
        XCTAssertEqual(result.fit.accepted, true)
        XCTAssertEqual(result.fit.x, 554.6, accuracy: 3)
        XCTAssertEqual(result.fit.y, 738.8, accuracy: 3)
        XCTAssertEqual(result.fit.radius, 37.4, accuracy: 3)
        XCTAssertEqual(result.fit.rotation, 299.8, accuracy: 5)
        let mirrored = try await engine.recognize(photo, at: date, mirror: true)
        XCTAssertEqual(mirrored.fit.accepted, false)

        let skyPatch = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: 730, y: 678, width: 128, height: 128)))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let clouds = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
            UIImage(cgImage: skyPatch).draw(in: CGRect(x: 490, y: 678, width: 128, height: 128))
        }
        let cloudPhoto = MoonAtlasPhoto(image: clouds, captureDate: date, latitude: nil, longitude: nil)
        let cloudResult = try await engine.recognize(cloudPhoto, at: date)
        XCTAssertEqual(cloudResult.fit.accepted, false)
    }

    func testNativeEngineDoesNotAcceptBlankPhoto() async throws {
        let (info, url) = try fixture(blank: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = MoonAtlasEngine()
        let photo = try await engine.load(info)
        let result = try await engine.recognize(photo, at: try XCTUnwrap(photo.captureDate))
        XCTAssertEqual(result.fit.accepted, false)
        XCTAssertEqual(result.fit.reason, "disc")
    }

    func testLandmarkCatalogAndVisibilityForSmallOrUnlitFeatures() throws {
        let url = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("MoonAtlasResources/assets/features.json"))
        let features = try JSONDecoder().decode([MoonAtlasFeature].self, from: Data(contentsOf: url))
        let craters = features.filter { $0.type == "crater" }
        let mountains = features.filter { $0.type == "mountain" }
        XCTAssertEqual(Set(craters.map(\.id)), ["6163", "1296", "2990", "380", "4757"])
        XCTAssertEqual(Set(mountains.map(\.id)), ["4004", "4003"])
        XCTAssertEqual(Set((craters + mountains).map { $0.articleText(.naming) }).count, 7)
        for feature in craters + mountains {
            XCTAssertFalse(feature.articleText(.naming).hasPrefix("atlas."))
            XCTAssertTrue(feature.isVisible(moonRadius: 400, emission: 0.8, incidence: 0.4))
            XCTAssertFalse(feature.isVisible(moonRadius: 400, emission: -0.4, incidence: 0.4))
            XCTAssertFalse(feature.isVisible(moonRadius: 400, emission: 0.8, incidence: -0.3))
            XCTAssertFalse(feature.isVisible(moonRadius: 25, emission: 0.8, incidence: 0.4))
        }
        for mountain in mountains {
            XCTAssertFalse(mountain.isVisible(moonRadius: 400, emission: 0.8, incidence: 0.95))
        }
    }

    func testEveryFeatureHasDistinctCopyAndBundledReferenceImage() throws {
        let root = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("MoonAtlasResources/assets"))
        let features = try JSONDecoder().decode([MoonAtlasFeature].self, from: Data(contentsOf: root.appendingPathComponent("features.json")))
        XCTAssertEqual(features.count, 22)
        let languages = ["ar", "de", "en", "es", "es-419", "fr", "ja", "pt-BR", "pt-PT", "ru", "uk", "zh-Hans", "zh-Hant", "zh-HK"]
        for language in languages {
            let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            for section in MoonAtlasArticleSection.allCases {
                let copy = features.map { $0.articleText(section, bundle: bundle) }
                XCTAssertEqual(Set(copy).count, features.count, "\(language): every \(section) should be individual")
                for text in copy {
                    XCTAssertFalse(text.hasPrefix("atlas."), "\(language) must have bundled translations")
                    XCTAssertFalse(text.isEmpty)
                    XCTAssertFalse(text.contains("·"))
                }
            }
            for feature in features {
                for source in feature.readingSources {
                    XCTAssertNotEqual(bundle.localizedString(forKey: source.titleKey, value: nil, table: nil), source.titleKey)
                }
            }
        }
        for feature in features {
            XCTAssertGreaterThanOrEqual(feature.readingSources.count, 2)
            let image = try XCTUnwrap(UIImage(contentsOfFile: root.appendingPathComponent("details/\(feature.id).jpg").path))
            XCTAssertGreaterThanOrEqual(image.size.width, 640)
            XCTAssertGreaterThanOrEqual(image.size.height, 512)
            let reference = try XCTUnwrap(feature.reference)
            XCTAssertEqual(reference.source.scheme, "https")
            XCTAssertTrue(["svs.gsfc.nasa.gov", "data.lroc.im-ldi.com"].contains(reference.source.host ?? ""))
            XCTAssertTrue(reference.credit.contains("NASA"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("example-nasa.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("index.html").path))
    }

    func testLeaderLayoutAvoidsCrossingsDuringRotationMirrorZoomAndPan() async throws {
        let (info, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = MoonAtlasEngine()
        let photo = try await engine.load(info)
        let result = try await engine.recognize(photo, at: try XCTUnwrap(photo.captureDate))
        let coordinates = result.features.compactMap {
            MoonSurfaceCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }
        for size in [CGSize(width: 320, height: 500), CGSize(width: 393, height: 680), CGSize(width: 844, height: 200)] {
            let bounds = CGRect(origin: .zero, size: size)
            for rotation in stride(from: 0.0, to: 360, by: 15) {
                for mirror in [-1.0, 1.0] {
                    for zoom in [0.65, 1.0, 1.8] {
                        for pan in [-35.0, 0, 35.0] {
                            let points = coordinates.compactMap { coordinate -> CGPoint? in
                                guard let projected = result.surface.project(coordinate, rotation: rotation),
                                      projected.emissionCosine > 0.1, projected.incidenceCosine > 0.08 else { return nil }
                                let radius = size.width * 0.38 * zoom
                                let point = CGPoint(x: bounds.midX + projected.point.x * mirror * radius + pan,
                                                    y: bounds.midY + projected.point.y * radius - pan)
                                return bounds.insetBy(dx: 4, dy: 4).contains(point) ? point : nil
                            }
                            for width in [62.0, 116.0] {
                                let labels = MoonAtlasLabelLayout.arrange(points, in: bounds, labelSize: CGSize(width: width, height: 44))
                                XCTAssertEqual(Set(labels.map(\.index)).count, labels.count)
                                for (index, label) in labels.enumerated() {
                                    XCTAssertTrue(bounds.contains(label.frame))
                                    for other in labels.dropFirst(index + 1) {
                                        XCTAssertTrue(label.frame.intersection(other.frame).isEmpty)
                                        XCTAssertFalse(crosses(label.anchor, label.endpoint, other.anchor, other.endpoint),
                                                       "Crossed leaders at rotation \(rotation), mirror \(mirror), zoom \(zoom), pan \(pan)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func crosses(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat {
            (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
        }
        return side(a, b, c) * side(a, b, d) < -0.001 && side(c, d, a) * side(c, d, b) < -0.001
    }

    @MainActor
    private func descendants<T: UIView>(_ type: T.Type, in root: UIView) -> [T] {
        ((root as? T).map { [$0] } ?? []) + root.subviews.flatMap { descendants(type, in: $0) }
    }

    @MainActor
    func testLongArticlesRemainReadableAndSourcesAreReachable() async throws {
        let data = try Data(contentsOf: XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("MoonAtlasResources/assets/features.json")))
        let features = try JSONDecoder().decode([MoonAtlasFeature].self, from: data)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 568)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for id in ["3670", "3680", "3665"] {
            let feature = try XCTUnwrap(features.first { $0.id == id })
            let controller = MoonAtlasFeatureViewController(feature: feature)
            let navigation = moonAtlasSheet(controller)
            navigation.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .extraLarge), forChild: controller)
            window.rootViewController = navigation
            window.makeKeyAndVisible()
            try await Task.sleep(nanoseconds: 100_000_000)
            controller.view.layoutIfNeeded()
            let scroll = try XCTUnwrap(descendants(UIScrollView.self, in: controller.view).first)
            XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
            for section in MoonAtlasArticleSection.allCases {
                let label = try XCTUnwrap(descendants(UILabel.self, in: controller.view).first { $0.accessibilityIdentifier == "atlas.article.\(section.rawValue)" })
                XCTAssertEqual(label.text, feature.articleText(section))
                let required = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude))
                XCTAssertGreaterThanOrEqual(label.bounds.height + 1, required.height, "\(id): article text must not be clipped")
            }
            let sources = try XCTUnwrap(descendants(UIButton.self, in: controller.view).first { $0.accessibilityIdentifier == "atlas.articleSources" })
            XCTAssertEqual(sources.menu?.children.count, feature.readingSources.count + 1)
            let frame = sources.convert(sources.bounds, to: scroll)
            scroll.scrollRectToVisible(frame, animated: false)
            controller.view.layoutIfNeeded()
            XCTAssertTrue(scroll.bounds.intersects(frame), "References must remain reachable by scrolling")
            if id == "3670" { attach(window, name: "Long article scrolled to reading sources") }
        }
    }

    @MainActor
    func testPhotoButtonZoomsToMoonWithQuietControlsAndOnDemandDetails() async throws {
        let (info, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let detail = ImageDetailViewController(imageInfo: info)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        await withCheckedContinuation { continuation in
            host.present(detail, animated: false) { continuation.resume() }
        }
        detail.loadViewIfNeeded()
        var entry: UIButton?
        for _ in 0..<50 {
            entry = descendants(UIButton.self, in: detail.view).first { $0.accessibilityIdentifier == "photo.moonAtlas" }
            if entry != nil, descendants(ImageDetailCell.self, in: detail.view).first?.imageView?.image != nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        attach(window, name: "Existing photo before entering the atlas")
        try XCTUnwrap(entry).sendActions(for: .touchUpInside)
        for _ in 0..<20 {
            if detail.presentedViewController != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let navigation = try XCTUnwrap(detail.presentedViewController as? UINavigationController)
        XCTAssertEqual(navigation.modalPresentationStyle, .fullScreen)
        XCTAssertTrue(navigation.transitioningDelegate is MoonAtlasTransition)
        let controller = try XCTUnwrap(navigation.topViewController as? MoonAtlasViewController)
        XCTAssertEqual(controller.entrancePhase, .expanding)
        var phases: [MoonAtlasViewController.EntrancePhase] = []
        var revealCounts: Set<Int> = []
        var captured: Set<String> = []
        var sawMovingPhoto = false
        for _ in 0..<500 {
            let phase = controller.entrancePhase
            if phases.last != phase { phases.append(phase) }
            switch phase {
            case .expanding, .fullPhoto, .focusing:
                XCTAssertEqual(controller.photoView.visibleAnnotationCount, 0)
                if phase == .expanding {
                    sawMovingPhoto = sawMovingPhoto || descendants(UIView.self, in: window).contains { $0.accessibilityIdentifier == "atlas.transitionPhoto" }
                }
                if phase == .fullPhoto, captured.insert("fullPhoto").inserted { attach(window, name: "Full photo before lunar zoom") }
                if phase == .focusing, captured.insert("focusing").inserted {
                    try await Task.sleep(nanoseconds: 200_000_000)
                    attach(window, name: "Moon enlarges without annotations")
                }
            case .revealing: revealCounts.insert(controller.photoView.visibleAnnotationCount)
            default: break
            }
            if phase == .ready { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(phases, [.expanding, .fullPhoto, .focusing, .revealing, .ready])
        XCTAssertTrue(sawMovingPhoto, "The existing photo should move into the full-screen viewer")
        XCTAssertGreaterThan(revealCounts.count, 2, "Annotations should appear in successive steps")
        XCTAssertEqual(controller.recognitionState, .ready)
        try await Task.sleep(nanoseconds: 250_000_000)
        controller.view.layoutIfNeeded()
        XCTAssertGreaterThan(controller.photoView.scrollView.zoomScale, controller.photoView.scrollView.minimumZoomScale * 1.5)
        XCTAssertFalse(controller.photoView.showsReference)
        assertMoonPixelsVisible(in: controller.photoView)
        XCTAssertNil(controller.presentedViewController)
        XCTAssertFalse(descendants(UIView.self, in: controller.view).contains { String(describing: type(of: $0)).contains("WKWebView") })
        let features = descendants(UIButton.self, in: controller.photoView).filter { $0.accessibilityIdentifier?.hasPrefix("atlas.feature.") == true && !$0.isHidden }
        XCTAssertGreaterThanOrEqual(features.count, 5)
        let reference = try XCTUnwrap(descendants(UIButton.self, in: controller.view).first { $0.accessibilityIdentifier == "atlas.reference" })
        let adjust = try XCTUnwrap(descendants(UIButton.self, in: controller.view).first { $0.accessibilityIdentifier == "atlas.adjust" })
        let panel = try XCTUnwrap(descendants(UIStackView.self, in: controller.view).first { $0.accessibilityIdentifier == "atlas.adjustmentPanel" })
        XCTAssertTrue(panel.isHidden)
        reference.sendActions(for: .touchUpInside)
        XCTAssertTrue(controller.photoView.showsReference)
        reference.sendActions(for: .touchUpInside)
        attach(window, name: "Native photo with tappable maria")

        let feature = try XCTUnwrap(features.first { $0.accessibilityIdentifier == "atlas.feature.6163" })
        let selectedID = try XCTUnwrap(feature.accessibilityIdentifier).replacingOccurrences(of: "atlas.feature.", with: "")
        feature.sendActions(for: .touchUpInside)
        try await Task.sleep(nanoseconds: 500_000_000)
        let sheet = try XCTUnwrap(controller.presentedViewController as? UINavigationController)
        let featureController = try XCTUnwrap(sheet.topViewController as? MoonAtlasFeatureViewController)
        XCTAssertEqual(featureController.feature.id, selectedID)
        XCTAssertEqual(featureController.feature.type, "crater")
        let naming = try XCTUnwrap(descendants(UILabel.self, in: featureController.view).first { $0.accessibilityIdentifier == "atlas.article.naming" })
        let story = try XCTUnwrap(descendants(UILabel.self, in: featureController.view).first { $0.accessibilityIdentifier == "atlas.article.story" })
        XCTAssertEqual(naming.text, featureController.feature.articleText(.naming))
        XCTAssertEqual(story.text, featureController.feature.articleText(.story))
        let referenceImage = try XCTUnwrap(descendants(UIImageView.self, in: featureController.view).first { $0.accessibilityIdentifier == "atlas.featureReference" })
        XCTAssertNotNil(referenceImage.image)
        XCTAssertGreaterThan(referenceImage.frame.height, 150)
        XCTAssertLessThanOrEqual(naming.frame.maxY, referenceImage.frame.minY, "Naming history comes before the reference image")
        XCTAssertLessThanOrEqual(referenceImage.frame.maxY, story.frame.minY, "The reading surface must not overlap the reference image")
        XCTAssertEqual(sheet.sheetPresentationController?.selectedDetentIdentifier, .large)
        XCTAssertEqual(sheet.traitCollection.userInterfaceStyle, .dark)
        attach(window, name: "Tycho naming history and reference image")
        let close = try XCTUnwrap(featureController.navigationItem.rightBarButtonItem)
        UIApplication.shared.sendAction(try XCTUnwrap(close.action), to: close.target, from: close, for: nil)
        for _ in 0..<30 {
            if controller.presentedViewController == nil { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNil(controller.presentedViewController)
        try await Task.sleep(nanoseconds: 300_000_000)

        adjust.sendActions(for: .touchUpInside)
        XCTAssertFalse(panel.isHidden)
        XCTAssertTrue(controller.photoView.isAdjusting)
        XCTAssertTrue(controller.photoView.showsReference)
        let slider = try XCTUnwrap(descendants(UISlider.self, in: panel).first)
        slider.value += 20; slider.sendActions(for: .valueChanged)
        try await Task.sleep(nanoseconds: 300_000_000)
        attach(window, name: "Compact native adjustment controls")
        let cancel = try XCTUnwrap(descendants(UIButton.self, in: panel).first { $0.accessibilityIdentifier == "atlas.cancelAdjustment" })
        cancel.sendActions(for: .touchUpInside)
        XCTAssertTrue(panel.isHidden)
        XCTAssertFalse(controller.photoView.isAdjusting)
        XCTAssertFalse(controller.photoView.showsReference)
        XCTAssertEqual(controller.recognitionState, .ready)

        let atlasClose = try XCTUnwrap(controller.navigationItem.leftBarButtonItem)
        UIApplication.shared.sendAction(try XCTUnwrap(atlasClose.action), to: atlasClose.target, from: atlasClose, for: nil)
        try await Task.sleep(nanoseconds: 650_000_000)
        XCTAssertNil(detail.presentedViewController)
        XCTAssertEqual(controller.entrancePhase, .closed)
        XCTAssertFalse(descendants(UIView.self, in: window).contains { $0.accessibilityIdentifier == "atlas.transitionPhoto" })
        XCTAssertFalse(try XCTUnwrap(descendants(ImageDetailCell.self, in: detail.view).first?.imageView).isHidden)
    }

    @MainActor
    func testPhotoTransitionPreservesZoomedSourceCrop() throws {
        let canvas = UIView(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        let crop = UIView(frame: CGRect(x: 0, y: 120, width: 393, height: 300)); crop.clipsToBounds = true
        canvas.addSubview(crop)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600), format: format).image { $0.fill(CGRect(x: 0, y: 0, width: 800, height: 600)) }
        let photo = UIImageView(image: image); photo.contentMode = .scaleAspectFit
        photo.frame = CGRect(x: -200, y: -70, width: 800, height: 600)
        crop.addSubview(photo)
        XCTAssertEqual(MoonAtlasPhotoGeometry.imageFrame(photo, in: canvas), CGRect(x: -200, y: 50, width: 800, height: 600))
        XCTAssertEqual(MoonAtlasPhotoGeometry.visibleFrame(photo, in: canvas), CGRect(x: 0, y: 120, width: 393, height: 300))
    }

    @MainActor
    func testCancelledRevealDoesNotShowDelayedAnnotations() async throws {
        let root = try XCTUnwrap(Bundle.main.resourceURL?.appendingPathComponent("MoonAtlasResources/assets/features.json"))
        let features = try JSONDecoder().decode([MoonAtlasFeature].self, from: Data(contentsOf: root))
        let labels = MoonAtlasLabelsView(frame: CGRect(x: 0, y: 0, width: 393, height: 680))
        labels.prepareReveal()
        labels.update(Array(features.prefix(10)).enumerated().map { ($0.element, CGPoint(x: 120, y: 100 + $0.offset * 30)) }, selected: nil)
        var finished = false
        labels.reveal(animated: true) { finished = true }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertGreaterThan(labels.visibleAnnotationCount, 0)
        XCTAssertLessThan(labels.visibleAnnotationCount, 10)
        labels.cancelReveal()
        labels.update([], selected: nil)
        try await Task.sleep(nanoseconds: 900_000_000)
        XCTAssertFalse(finished)
        XCTAssertEqual(labels.visibleAnnotationCount, 0)
    }

    @MainActor
    func testInterruptingZoomPreservesPositionAndReducedMotionCompletesImmediately() async throws {
        let (info, url) = try fixture()
        defer { try? FileManager.default.removeItem(at: url) }
        let engine = MoonAtlasEngine()
        let photo = try await engine.load(info)
        let result = try await engine.recognize(photo, at: try XCTUnwrap(photo.captureDate))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let host = UIViewController(); window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let viewer = MoonAtlasPhotoView(frame: host.view.bounds)
        host.view.addSubview(viewer)
        viewer.setPhoto(photo.image)
        let previewFrame = try XCTUnwrap(viewer.displayedImageFrame(in: viewer))
        viewer.setPhoto(photo.image)
        XCTAssertEqual(viewer.displayedImageFrame(in: viewer), previewFrame, "Replacing a zoomed preview must preserve the full-photo geometry")
        viewer.setResult(result, showLabels: false)
        var completed: Bool?
        viewer.focusForEntrance(animated: true) { completed = $0 }
        try await Task.sleep(nanoseconds: 250_000_000)
        let moving = try XCTUnwrap(descendants(UIImageView.self, in: viewer).first { $0.accessibilityIdentifier == "atlas.focusingPhoto" })
        let frame = try XCTUnwrap(moving.layer.presentation()?.frame)
        viewer.cancelEntrance()
        let current = try XCTUnwrap(viewer.displayedImageFrame(in: viewer))
        XCTAssertEqual(current.minX, frame.minX, accuracy: 1)
        XCTAssertEqual(current.minY, frame.minY, accuracy: 1)
        XCTAssertEqual(current.width, frame.width, accuracy: 1)
        XCTAssertEqual(completed, false)
        XCTAssertFalse(viewer.scrollView.isHidden)
        viewer.focusForEntrance(animated: false) { completed = $0 }
        XCTAssertEqual(completed, true)
        var revealed = false
        viewer.revealAnnotations(animated: false) { revealed = true }
        XCTAssertTrue(revealed)
        XCTAssertGreaterThan(viewer.visibleAnnotationCount, 0)
        assertMoonPixelsVisible(in: viewer)
    }

    @MainActor
    private func assertMoonPixelsVisible(in viewer: MoonAtlasPhotoView, file: StaticString = #filePath, line: UInt = #line) {
        let image = UIGraphicsImageRenderer(bounds: viewer.bounds).image { _ in
            viewer.drawHierarchy(in: viewer.bounds, afterScreenUpdates: true)
        }
        let rect = CGRect(x: (viewer.bounds.midX - 32) * image.scale, y: (viewer.bounds.midY - 32) * image.scale,
                          width: 64 * image.scale, height: 64 * image.scale)
        guard let crop = image.cgImage?.cropping(to: rect) else { XCTFail("Missing rendered photo", file: file, line: line); return }
        var gray = [UInt8](repeating: 0, count: 32 * 32)
        gray.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 32,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        XCTAssertGreaterThan(gray.filter { $0 > 25 }.count, 700, "The enlarged Moon must remain visible beneath the annotations", file: file, line: line)
    }

    @MainActor
    private func attach(_ window: UIWindow, name: String) {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
