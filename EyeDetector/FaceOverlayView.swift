//
//  FaceOverlayView.swift
//  EyeDetector
//
//  Created by Gaurav Bhambhani on 6/18/24.
//

import UIKit

class FaceOverlayView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.clear
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        backgroundColor = UIColor.clear
    }

//    override func draw(_ rect: CGRect) {
//        guard let context = UIGraphicsGetCurrentContext() else { return }
//        
//        // Define the face rectangle
//        let faceRect = CGRect(x: bounds.midX - 125, y: bounds.midY - 200, width: 250, height: 400)
//        
//        // Add a semi-transparent background
//        context.setFillColor(UIColor(white: 0, alpha: 0.7).cgColor)
//        context.fill(bounds)
//        
//        // Clear the face rectangle area
//        context.clear(faceRect)
//        
////        // Add a white border around the face rectangle
////        context.setStrokeColor(UIColor.white.cgColor)
////        context.setLineWidth(2.0)
////        context.stroke(faceRect)
//    }
}
