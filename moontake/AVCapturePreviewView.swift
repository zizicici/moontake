//
//  AVCapturePreviewView.swift
//  moontake
//
//  Created by Ci Zi on 2023/7/9.
//

import UIKit
import AVKit
import SnapKit

class AVCaptureVideoPreviewView: UIView {
    static let lineWidth = 30
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        let topLeftLine1 = getLine()
        addSubview(topLeftLine1)
        topLeftLine1.snp.makeConstraints { make in
            make.top.leading.equalTo(self)
            make.width.equalTo(AVCaptureVideoPreviewView.lineWidth)
            make.height.equalTo(1)
        }
        
        let topLeftLine2 = getLine()
        addSubview(topLeftLine2)
        topLeftLine2.snp.makeConstraints { make in
            make.top.leading.equalTo(self)
            make.width.equalTo(1)
            make.height.equalTo(AVCaptureVideoPreviewView.lineWidth)
        }
        
        let topRightLine1 = getLine()
        addSubview(topRightLine1)
        topRightLine1.snp.makeConstraints { make in
            make.top.trailing.equalTo(self)
            make.width.equalTo(AVCaptureVideoPreviewView.lineWidth)
            make.height.equalTo(1)
        }
        
        let topRightLine2 = getLine()
        addSubview(topRightLine2)
        topRightLine2.snp.makeConstraints { make in
            make.top.trailing.equalTo(self)
            make.width.equalTo(1)
            make.height.equalTo(AVCaptureVideoPreviewView.lineWidth)
        }
        
        let bottomLeftLine1 = getLine()
        addSubview(bottomLeftLine1)
        bottomLeftLine1.snp.makeConstraints { make in
            make.bottom.leading.equalTo(self)
            make.width.equalTo(AVCaptureVideoPreviewView.lineWidth)
            make.height.equalTo(1)
        }
        
        let bottomLeftLine2 = getLine()
        addSubview(bottomLeftLine2)
        bottomLeftLine2.snp.makeConstraints { make in
            make.bottom.leading.equalTo(self)
            make.width.equalTo(1)
            make.height.equalTo(AVCaptureVideoPreviewView.lineWidth)
        }
        
        let bottomRightLine1 = getLine()
        addSubview(bottomRightLine1)
        bottomRightLine1.snp.makeConstraints { make in
            make.bottom.trailing.equalTo(self)
            make.width.equalTo(AVCaptureVideoPreviewView.lineWidth)
            make.height.equalTo(1)
        }
        
        let bottomRightLine2 = getLine()
        addSubview(bottomRightLine2)
        bottomRightLine2.snp.makeConstraints { make in
            make.bottom.trailing.equalTo(self)
            make.width.equalTo(1)
            make.height.equalTo(AVCaptureVideoPreviewView.lineWidth)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. Check AVCaptureVideoPreviewView.layerClass implementation.")
        }
        return layer
    }
    
    var session: AVCaptureSession? {
        get {
            return videoPreviewLayer.session
        }
        set {
            videoPreviewLayer.session = newValue
        }
    }
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
}

extension AVCaptureVideoPreviewView {
    func getLine() -> UIView {
        let line = UIView()
        line.backgroundColor = .white
        return line
    }
}
