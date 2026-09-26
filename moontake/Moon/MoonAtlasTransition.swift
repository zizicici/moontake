import UIKit

/// Moves the displayed photograph, including its current crop, between viewers.
/// The source is weak so closing can fall back gracefully if its cell is gone.
final class MoonAtlasTransition: NSObject, UIViewControllerTransitioningDelegate {
    private weak var source: UIImageView?

    init(source: UIImageView?) { self.source = source }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        PhotoAnimator(source: self.source, presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        PhotoAnimator(source: source, presenting: false)
    }

    private final class PhotoAnimator: NSObject, UIViewControllerAnimatedTransitioning {
        weak var source: UIImageView?
        let presenting: Bool
        init(source: UIImageView?, presenting: Bool) { self.source = source; self.presenting = presenting }

        func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
            UIAccessibility.isReduceMotionEnabled ? 0.18 : 0.48
        }

        func animateTransition(using context: UIViewControllerContextTransitioning) {
            guard let from = context.viewController(forKey: .from), let to = context.viewController(forKey: .to) else {
                context.completeTransition(false); return
            }
            // UIKit may omit the from-view when presenting over an existing
            // sheet. Its controller still supplies the underlying source view.
            let fromView = context.view(forKey: .from) ?? from.view!
            let suppliedToView = context.view(forKey: .to)
            let toView = suppliedToView ?? to.view!
            let container = context.containerView
            if presenting {
                toView.frame = context.finalFrame(for: to)
                container.addSubview(toView)
            } else if suppliedToView != nil {
                toView.frame = context.finalFrame(for: to)
                container.insertSubview(toView, belowSubview: fromView)
            }
            // A nil to-view on dismissal belongs to a presentation controller
            // that restores its sheet itself; do not detach or resize it.
            toView.layoutIfNeeded()
            let navigation = (presenting ? to : from) as? UINavigationController
            let atlas = navigation?.viewControllers.first as? MoonAtlasViewController
            let fadingView = presenting ? toView : fromView
            let duration = transitionDuration(using: context)

            guard !UIAccessibility.isReduceMotionEnabled,
                  let source, let image = source.image, let atlas,
                  let sourceRect = MoonAtlasPhotoGeometry.imageFrame(source, in: container),
                  !MoonAtlasPhotoGeometry.visibleFrame(source, in: container).isEmpty,
                  let atlasRect = atlas.photoView.displayedImageFrame(in: container) else {
                if presenting { toView.alpha = 0 }
                UIView.animate(withDuration: duration, animations: {
                    fadingView.alpha = self.presenting ? 1 : 0
                }, completion: { _ in
                    fadingView.alpha = 1
                    context.completeTransition(!context.transitionWasCancelled)
                })
                return
            }
            let sourceClip = MoonAtlasPhotoGeometry.visibleFrame(source, in: container)
            let atlasClip = atlas.photoView.convert(atlas.photoView.bounds, to: container)
            let startClip = presenting ? sourceClip : atlasClip
            let endClip = presenting ? atlasClip : sourceClip
            let startImage = presenting ? sourceRect : atlasRect
            let endImage = presenting ? atlasRect : sourceRect
            let movingPhoto = UIView(frame: startClip)
            movingPhoto.clipsToBounds = true
            movingPhoto.accessibilityIdentifier = "atlas.transitionPhoto"
            let movingImage = UIImageView(image: presenting ? image : atlas.photoView.displayedImage)
            movingImage.contentMode = .scaleAspectFit
            movingImage.frame = startImage.offsetBy(dx: -startClip.minX, dy: -startClip.minY)
            movingPhoto.addSubview(movingImage)
            container.addSubview(movingPhoto)
            let sourceHidden = source.isHidden
            source.isHidden = true
            atlas.photoView.isHidden = true
            if presenting { toView.alpha = 0 }
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut], animations: {
                movingPhoto.frame = endClip
                movingImage.frame = endImage.offsetBy(dx: -endClip.minX, dy: -endClip.minY)
                fadingView.alpha = self.presenting ? 1 : 0
            }, completion: { _ in
                source.isHidden = sourceHidden
                atlas.photoView.isHidden = false
                fadingView.alpha = 1
                movingPhoto.removeFromSuperview()
                context.completeTransition(!context.transitionWasCancelled)
            })
        }
    }
}

enum MoonAtlasPhotoGeometry {
    static func imageFrame(_ view: UIImageView, in coordinateView: UIView) -> CGRect? {
        guard let image = view.image, image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(view.bounds.width / image.size.width, view.bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return view.convert(CGRect(x: view.bounds.midX - size.width / 2, y: view.bounds.midY - size.height / 2,
                                   width: size.width, height: size.height), to: coordinateView)
    }

    static func visibleFrame(_ view: UIView, in coordinateView: UIView) -> CGRect {
        var visible = coordinateView.bounds
        var ancestor: UIView? = view
        while let current = ancestor {
            if current.clipsToBounds { visible = visible.intersection(current.convert(current.bounds, to: coordinateView)) }
            ancestor = current.superview
        }
        return visible.isNull ? .zero : visible
    }
}
