//
//  AttributedString+Extension.swift
//  moontake
//
//  Created by Ci Zi on 2023/8/7.
//

import Foundation
import UIKit

extension NSAttributedString {
    func calculateBoundingSize(maxWidth: CGFloat) -> CGSize {
        let size = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        
        let boundingRect = self.boundingRect(with: size, options: options, context: nil)
        
        return CGSize(width: ceil(boundingRect.width), height: ceil(boundingRect.height))
    }
}
