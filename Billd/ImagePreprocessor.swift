//
//  ImagePreprocessor.swift
//  Billd
//
//  Created on 2/19/26.
//

import UIKit
import CoreImage
import Vision

/// Preprocesses images to improve OCR accuracy
class ImagePreprocessor {
    static let shared = ImagePreprocessor()
    private init() {}
    
    /// Enhances a receipt image for better OCR recognition.
    /// Kept intentionally light — Vision's OCR engine already handles color images,
    /// noise, and varying contrast well. Aggressive preprocessing (grayscale, heavy
    /// sharpening, noise reduction) can actually degrade results by merging characters
    /// or blowing out thin thermal-print text.
    func enhanceForOCR(_ image: UIImage) -> UIImage {
        guard let ciImage = CIImage(image: image) else { return image }

        let context = CIContext()
        var enhanced = ciImage

        // Mild contrast boost — helps faded thermal receipts without destroying detail
        if let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(enhanced, forKey: kCIInputImageKey)
            contrastFilter.setValue(1.1, forKey: kCIInputContrastKey)
            contrastFilter.setValue(0.0, forKey: kCIInputBrightnessKey)
            if let output = contrastFilter.outputImage {
                enhanced = output
            }
        }

        if let cgImage = context.createCGImage(enhanced, from: enhanced.extent) {
            return UIImage(cgImage: cgImage)
        }

        return image
    }
    
    /// Automatically detects and corrects perspective distortion in receipt images
    /// - Parameter image: The original image
    /// - Returns: Perspective-corrected image, or original if detection fails
    func correctPerspective(_ image: UIImage) async -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumAspectRatio = 0.3
        request.maximumAspectRatio = 1.0
        request.minimumSize = 0.3
        request.minimumConfidence = 0.6
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
            
            guard let observation = request.results?.first else {
                print("No rectangle detected for perspective correction")
                return image
            }
            
            // Get the corners of the detected rectangle
            let topLeft = observation.topLeft
            let topRight = observation.topRight
            let bottomLeft = observation.bottomLeft
            let bottomRight = observation.bottomRight
            
            // Convert normalized coordinates to image coordinates
            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            let convertedTopLeft = convertPoint(topLeft, imageSize: imageSize)
            let convertedTopRight = convertPoint(topRight, imageSize: imageSize)
            let convertedBottomLeft = convertPoint(bottomLeft, imageSize: imageSize)
            let convertedBottomRight = convertPoint(bottomRight, imageSize: imageSize)
            
            // Apply perspective correction
            if let ciImage = CIImage(image: image),
               let corrected = applyPerspectiveCorrection(
                to: ciImage,
                topLeft: convertedTopLeft,
                topRight: convertedTopRight,
                bottomLeft: convertedBottomLeft,
                bottomRight: convertedBottomRight
               ) {
                let context = CIContext()
                if let cgCorrected = context.createCGImage(corrected, from: corrected.extent) {
                    print("✅ Perspective correction applied")
                    return UIImage(cgImage: cgCorrected)
                }
            }
        } catch {
            print("Perspective detection error: \(error)")
        }
        
        return image
    }
    
    // MARK: - Private Helpers
    
    private func convertPoint(_ point: CGPoint, imageSize: CGSize) -> CGPoint {
        // Vision coordinates are bottom-left origin, convert to top-left
        return CGPoint(
            x: point.x * imageSize.width,
            y: (1 - point.y) * imageSize.height
        )
    }
    
    private func applyPerspectiveCorrection(
        to image: CIImage,
        topLeft: CGPoint,
        topRight: CGPoint,
        bottomLeft: CGPoint,
        bottomRight: CGPoint
    ) -> CIImage? {
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            return nil
        }
        
        // Convert points to CIVector
        let inputTopLeft = CIVector(cgPoint: topLeft)
        let inputTopRight = CIVector(cgPoint: topRight)
        let inputBottomLeft = CIVector(cgPoint: bottomLeft)
        let inputBottomRight = CIVector(cgPoint: bottomRight)
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(inputTopLeft, forKey: "inputTopLeft")
        filter.setValue(inputTopRight, forKey: "inputTopRight")
        filter.setValue(inputBottomLeft, forKey: "inputBottomLeft")
        filter.setValue(inputBottomRight, forKey: "inputBottomRight")
        
        return filter.outputImage
    }
}
