import Core
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Photos, decoded and encoded off the main thread, never at full sensor size.
enum Photo {
    struct Processed {
        let jpeg: Data
        let width: Int
        let height: Int
        let thumbnail: Data
    }

    static let storedSide = 2048
    static let thumbnailSide = 480

    /// The original as a JPEG no larger than `storedSide`, plus a thumbnail. Orientation is baked in.
    static func process(_ data: Data) async -> Processed? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let big = downsample(source, maxSide: storedSide),
                  let small = downsample(source, maxSide: thumbnailSide),
                  let jpeg = encode(big, quality: 0.86),
                  let thumbnail = encode(small, quality: 0.8)
            else { return nil }
            return Processed(jpeg: jpeg, width: big.width, height: big.height, thumbnail: thumbnail)
        }.value
    }

    /// What a photo file knows about itself: when it was taken and where.
    struct Metadata: Sendable {
        var takenAt: Date?
        var location: Location?
    }

    static func metadata(of data: Data) async -> Metadata {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            else { return Metadata() }
            var metadata = Metadata()
            if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
               let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
                formatter.timeZone = (exif[kCGImagePropertyExifOffsetTimeOriginal] as? String).flatMap(timeZone(fromOffset:)) ?? .current
                metadata.takenAt = formatter.date(from: raw)
            }
            if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any],
               let latitude = gps[kCGImagePropertyGPSLatitude] as? Double,
               let longitude = gps[kCGImagePropertyGPSLongitude] as? Double {
                let south = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S"
                let west = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W"
                metadata.location = Location(latitude: south ? -latitude : latitude, longitude: west ? -longitude : longitude)
            }
            return metadata
        }.value
    }

    /// "+01:00" and friends, as written in EXIF.
    private static func timeZone(fromOffset text: String) -> TimeZone? {
        let parts = text.dropFirst().split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, let sign = text.first, sign == "+" || sign == "-" else { return nil }
        let seconds = (parts[0] * 3600 + parts[1] * 60) * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }

    /// A stored photo at viewing size, decoded off the main thread.
    static func load(_ url: URL, maxSide: Int = 2400) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = downsample(source, maxSide: maxSide) else { return nil }
            return UIImage(cgImage: image)
        }.value
    }

    /// A photo's bytes at viewing size, orientation baked in, decoded off the main thread.
    static func decode(_ data: Data, maxSide: Int = 2400) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = downsample(source, maxSide: maxSide) else { return nil }
            return UIImage(cgImage: image)
        }.value
    }

    /// Decodes only as many pixels as needed. Cheap even for a 48-megapixel source.
    static func downsample(_ source: CGImageSource, maxSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func encode(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
