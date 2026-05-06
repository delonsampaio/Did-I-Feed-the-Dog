// DidIFeedTheDogWidget/WidgetImage.swift
import UIKit
import ImageIO

// Avatar photoData stored in WidgetDataStore can be up to 1024x1024 — when
// UIImage(data:) decodes that into raw pixel buffers, each image expands to
// 4-12MB in memory. Six avatars in the Large widget × that = potentially
// 30MB+, which trips the widget extension's hard memory limit and causes
// iOS to kill the extension (resulting in a redacted placeholder).
//
// CGImageSourceCreateThumbnailAtIndex creates a downsampled thumbnail
// directly from the source data, never holding the full-resolution image
// in memory. The 30x30 pt avatar at @3x = 90 pixels, so we cap the
// thumbnail at ~120px to leave headroom for retina displays.
enum WidgetImage {
    static func downsample(data: Data, toPointSize pointSize: CGSize, scale: CGFloat = 3) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let maxPixels = max(pointSize.width, pointSize.height) * scale
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
