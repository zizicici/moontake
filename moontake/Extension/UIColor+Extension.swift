//
//  UIColor+Extension.swift
//  moontake
//
//  Created by Ci Zi on 2023/7/8.
//


import UIKit

extension UIColor {
    static let backgroundColor: UIColor = UIColor(named: "BackgroundColor") ?? UIColor.systemBackground
    static let moonColor: UIColor = UIColor(named: "MoonColor") ?? UIColor.white
    static let skyColor: UIColor = UIColor(named: "SkyColor") ?? UIColor.black
}

extension UIImage {
    convenience init?(color: UIColor, size: CGSize = CGSize(width: 1, height: 1)) {
        let rect = CGRect(origin: .zero, size: size)
        UIGraphicsBeginImageContextWithOptions(rect.size, false, 0.0)
        color.setFill()
        UIRectFill(rect)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let cgImage = image?.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }
}

class ColorHighlightButton: UIButton {
    var highlightedColor: UIColor?
    var normalColor: UIColor? {
        didSet {
            backgroundColor = normalColor
        }
    }
    
    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? highlightedColor : normalColor
        }
    }
}
