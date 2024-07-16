//
//  ImageDetailCell.swift
//  moontake
//
//  Created by zici on 15/7/24.
//

import UIKit
import SnapKit
import Kingfisher

class ImageDetailCell: ImageInfoBaseCell {
    var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 6.0
        scrollView.bouncesZoom = true
        scrollView.isMultipleTouchEnabled = true
        
        return scrollView
    }()
    
    var imageView: UIImageView!
    
    private func setupViewsIfNeeded() {
        guard scrollView.superview == nil else {
            return
        }
        
        contentView.addSubview(scrollView)
        scrollView.delegate = self
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(contentView)
        }
        
        imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        
        let doubleTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)
    }
    
    override func updateConfiguration(using state: UICellConfigurationState) {
        super.updateConfiguration(using: state)
        setupViewsIfNeeded()
        
        if let imageInfo = state.imageInfo {
            if let originURL = imageInfo.originURL {
                imageView.kf.setImage(with: originURL, options: [.cacheMemoryOnly])
            }
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        scrollView.contentSize = bounds.size
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
}

extension ImageDetailCell: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
    }
}
