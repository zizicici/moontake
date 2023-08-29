//
//  PhotoCaptureProcessor+WaterMark.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/8.
//

import Foundation
import UIKit

extension PhotoCaptureProcessor {
    func addWaterMark(for photoData: Data) -> Data? {
        var newData: Data?
        if let image = UIImage(data: photoData), let newImage = addWaterMarkToBottomOfImage(image: image) {
            if let data = newImage.jpegData(compressionQuality: 1.0) {
                newData = data
            }
        }
        return newData
    }
    
    func addWaterMarkToBottomOfImage(image: UIImage) -> UIImage? {
        let imageSize = image.size
        let scale = image.scale
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: imageSize.width, height: imageSize.height + 360), false, scale)
        
        // Photo
        image.draw(at: .zero)
        
        // WaterMark Background
        let whiteRect = CGRect(x: 0, y: imageSize.height, width: imageSize.width, height: 360)
        UIColor.white.setFill()
        UIRectFill(whiteRect)
        
        // First Line
        let firstAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 80, weight: .medium),
            .foregroundColor: UIColor.black
        ]
        let firstText: String = String(format: "%@ %.1f%%", MoonManager.shared.getPhaseName(), MoonManager.shared.getPhasePercent() * 100)
        let firstAttributedString = NSAttributedString(string: firstText, attributes: firstAttributes)
        
        let firstHeight = firstAttributedString.calculateBoundingSize(maxWidth: .greatestFiniteMagnitude).height
        let firstTextRect = CGRect(x: 80.0, y: imageSize.height + 70.0, width: imageSize.width - 80.0, height: firstHeight)

        firstAttributedString.draw(in: firstTextRect)
        
        // Second Line
        let secondAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 64, weight: .light),
            .foregroundColor: UIColor.black.withAlphaComponent(0.6)
        ]
        let secondText: String = Date().formatted(date: .numeric, time: .standard)
        let secondAttributedString = NSAttributedString(string: secondText, attributes: secondAttributes)
        
        let secondHeight = secondAttributedString.calculateBoundingSize(maxWidth: .greatestFiniteMagnitude).height
        let secondTextRect = CGRect(x: 80.0, y: firstTextRect.maxY + 48.0, width: imageSize.width - 80.0, height: secondHeight)
        
        secondAttributedString.draw(in: secondTextRect)
        
        switch Settings.shared.getWatermarkTypeSettings() {
        case .icon:
            // Promotion
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = NSTextAlignment.right
            paragraphStyle.lineSpacing = 30.0
            let promotionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 60, weight: .light),
                .foregroundColor: UIColor.black.withAlphaComponent(0.6),
                .paragraphStyle: paragraphStyle
            ]
            let promotionText: String = "moontake\nA Moon Camera".localized()
            let promotionAttributedString = NSMutableAttributedString(string: promotionText, attributes: promotionAttributes)
            let range = (promotionText as NSString).range(of: "moontake")
            promotionAttributedString.addAttributes([.font: UIFont.systemFont(ofSize: 72, weight: .medium), .foregroundColor: UIColor.black], range: range)
            
            let promotionSize = promotionAttributedString.calculateBoundingSize(maxWidth: .greatestFiniteMagnitude)
            let promotionTextRect = CGRect(x: imageSize.width - 340.0 - promotionSize.width, y: imageSize.height + (360 - promotionSize.height) / 2.0, width: promotionSize.width, height: promotionSize.height)
            
            promotionAttributedString.draw(in: promotionTextRect)
            
            // Icon
            if let logoImage = UIImage(named: "AppIcon") {
                // 创建圆角路径
                let cornerRadius: CGFloat = 50.0
                let path = UIBezierPath(roundedRect: CGRect(x: imageSize.width - 280, y: imageSize.height + 80, width: 200, height: 200), cornerRadius: cornerRadius)
                path.addClip()
                
                logoImage.draw(in: CGRect(x: imageSize.width - 280, y: imageSize.height + 80, width: 200, height: 200))
            }
        case .qrCode:
            // Promotion
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = NSTextAlignment.right
            paragraphStyle.lineSpacing = 24.0
            let promotionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 60, weight: .light),
                .foregroundColor: UIColor.black.withAlphaComponent(0.8),
                .paragraphStyle: paragraphStyle
            ]
            let promotionText: String = "Scan QR Code to Get\nmoontake".localized()
            let promotionAttributedString = NSMutableAttributedString(string: promotionText, attributes: promotionAttributes)
            let range = (promotionText as NSString).range(of: "moontake")
            promotionAttributedString.addAttributes([.font: UIFont.systemFont(ofSize: 72, weight: .light), .foregroundColor: UIColor.black.withAlphaComponent(0.8)], range: range)
            
            let promotionSize = promotionAttributedString.calculateBoundingSize(maxWidth: .greatestFiniteMagnitude)
            let promotionTextRect = CGRect(x: imageSize.width - 340.0 - promotionSize.width, y: imageSize.height + (360 - promotionSize.height) / 2.0, width: promotionSize.width, height: promotionSize.height)
            
            promotionAttributedString.draw(in: promotionTextRect)
            
            // QR Code
            if let codeImage = UIImage(named: "qrcode") {
                codeImage.draw(in: CGRect(x: imageSize.width - 280, y: imageSize.height + 60, width: 240, height: 240), blendMode: .normal, alpha: 0.8)
            }
        case .location:
            // TODO
            break
        case .blank:
            // Do nothing
            break
        }
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage
    }
}
