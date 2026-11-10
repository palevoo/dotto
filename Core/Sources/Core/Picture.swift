import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo made small enough to hand through the door: the long side capped, re-encoded as JPEG.
/// The original in `media/` is never touched.
public enum Picture {
    public static func jpeg(contentsOf url: URL, maxSide: Int) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// A picture as the notebook keeps it: a JPEG no larger than `storedSide` on its long side,
    /// orientation baked in, and a small one for a row of thumbnails.
    public struct Processed: Sendable {
        public let jpeg: Data
        public let width: Int
        public let height: Int
        public let thumbnail: Data
    }

    public static let storedSide = 2048
    public static let thumbnailSide = 480

    /// Any image the system can read, a camera's HEIC, a screenshot's PNG, a TIFF off the
    /// clipboard, made into what the notebook keeps. Nil when the bytes are not a picture.
    /// Decodes only as many pixels as it needs; call it off the main thread.
    public static func process(_ data: Data) -> Processed? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let big = downsample(source, maxSide: storedSide),
              let small = downsample(source, maxSide: thumbnailSide),
              let jpeg = encode(big, quality: 0.86),
              let thumbnail = encode(small, quality: 0.8)
        else { return nil }
        return Processed(jpeg: jpeg, width: big.width, height: big.height, thumbnail: thumbnail)
    }

    /// Decodes only as many pixels as needed. Cheap even for a 48-megapixel source.
    public static func downsample(_ source: CGImageSource, maxSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    public static func encode(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
