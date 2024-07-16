//
//  ImageViewController.swift
//  moontake
//
//  Created by zici on 14/7/24.
//

import UIKit
import SnapKit
import Kingfisher

class ImageViewController: UIViewController {
    var imageInfo: ImageInfo!
    
    var imageView: UIImageView!
    var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 6.0
        scrollView.bouncesZoom = true
        scrollView.isMultipleTouchEnabled = true
        scrollView.contentInsetAdjustmentBehavior = .never
        
        return scrollView
    }()
    
    convenience init(imageInfo: ImageInfo) {
        self.init(nibName: nil, bundle: nil)
        self.imageInfo = imageInfo
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.largeTitleDisplayMode = .never
        
        view.backgroundColor = .skyColor
        
        scrollView.delegate = self
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view)
        }
        
        imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)
        
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
            self.loadImage()
        }
    }
    
    func loadImage() {
        if let originURL = imageInfo.originURL {
            imageView.kf.setImage(with: originURL)
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let height = scrollView.frame.width / 4 * 3
        imageView.frame = CGRect(x: 0, y: 0, width: scrollView.frame.width, height: height)
        updateImageView(scrollView)
        scrollView.contentSize = scrollView.frame.size
    }
    
    @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
        if scrollView.zoomScale == scrollView.minimumZoomScale {
            let center = recognizer.location(in: imageView)
            let zoomRect = CGRect(x: center.x, y: center.y, width: 1, height: 1)
            scrollView.zoom(to: zoomRect, animated: true)
        } else {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        }
    }
    
    func updateImageView(_ scrollView: UIScrollView?) {
        let targetScrollView = scrollView ?? self.scrollView
        let offsetX = (targetScrollView.frame.width > targetScrollView.contentSize.width) ? (targetScrollView.frame.width - targetScrollView.contentSize.width) * 0.5 : 0.0
        let offsetY = (targetScrollView.frame.height > targetScrollView.contentSize.height) ? (targetScrollView.frame.height - targetScrollView.contentSize.height) * 0.5 : 0.0
        imageView.center = CGPoint(
            x: targetScrollView.contentSize.width * 0.5 + offsetX,
            y: targetScrollView.contentSize.height * 0.5 + offsetY
        )
    }
}

extension ImageViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateImageView(scrollView)
    }
}
