import AVFoundation
import Core
import Foundation
import ImageIO
import Photos
import PhotosUI
import Speech
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The library, through PhotoKit when the library allows it: the original file with the
/// moment and place the photo knows. Otherwise the picker's copy, which keeps the date but
/// not the place.
enum PhotoLibrary {
    struct Picked: Sendable {
        let data: Data
        let takenAt: Date?
        let location: Location?
    }

    /// Asked once, on the first visit. Whatever the answer, the picker still opens.
    static func ask() async {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined else { return }
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    static func load(_ item: PhotosPickerItem) async -> Picked? {
        if let id = item.itemIdentifier,
           let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject,
           let data = await originalData(of: asset) {
            let place = asset.location.map {
                Location(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, accuracy: $0.horizontalAccuracy)
            }
            return Picked(data: data, takenAt: asset.creationDate, location: place)
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return Picked(data: data, takenAt: nil, location: nil)
    }

    private static func originalData(of asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        final class Once: @unchecked Sendable { var done = false }
        let once = Once()
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                guard !once.done else { return }
                once.done = true
                continuation.resume(returning: data)
            }
        }
    }
}

/// Hold to speak. The audio is kept; the words are made on this device.
@MainActor
@Observable
final class VoiceRecorder {
    private(set) var isRecording = false
    private(set) var startedAt: Date?
    private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var ticker: Task<Void, Never>?

    struct Take {
        let fileURL: URL
        let duration: TimeInterval
        let startedAt: Date
    }

    func start() async {
        guard !isRecording else { return }
        guard await AVAudioApplication.requestRecordPermission() else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else {
                NSLog("record failed: recorder would not start")
                return
            }
            self.recorder = recorder
            startedAt = Date()
            elapsed = 0
            isRecording = true
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard let self, let started = self.startedAt else { return }
                    self.elapsed = Date().timeIntervalSince(started)
                }
            }
        } catch {
            NSLog("record failed: \(error)")
        }
    }

    /// Stops and returns the take, or nil if it was too short to keep.
    func stop() -> Take? {
        ticker?.cancel()
        guard let recorder, let startedAt else { return nil }
        recorder.stop()
        let duration = Date().timeIntervalSince(startedAt)
        isRecording = false
        self.recorder = nil
        self.startedAt = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        guard duration >= 0.7 else {
            try? FileManager.default.removeItem(at: recorder.url)
            return nil
        }
        return Take(fileURL: recorder.url, duration: duration, startedAt: startedAt)
    }
}

/// Speech to text that stays on the phone when the language allows it.
enum Transcriber {
    static func transcribe(_ url: URL) async -> String {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized, let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else { return "" }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        return await withCheckedContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    finished = true
                    continuation.resume(returning: "")
                }
            }
        }
    }
}

/// Plays one voice note at a time.
@MainActor
@Observable
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayer()

    private(set) var playingHash: String?
    private var player: AVAudioPlayer?

    func toggle(url: URL, hash: String) {
        if playingHash == hash {
            player?.stop()
            player = nil
            playingHash = nil
            return
        }
        player?.stop()
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSLog("play failed: no file at \(url.path)")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.volume = 1
            guard player.prepareToPlay(), player.play() else {
                NSLog("play failed: player would not start for \(url.lastPathComponent)")
                return
            }
            self.player = player
            playingHash = hash
        } catch {
            NSLog("play failed: \(error)")
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playingHash = nil
        }
    }
}

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

/// Small versions of photos, made once, kept in the app's cache folder and in memory.
/// Derived from the notebook, never part of it.
enum Thumbs {
    private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        return cache
    }()

    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("thumbs", isDirectory: true)
    }

    static func url(_ hash: String) -> URL {
        directory.appendingPathComponent("\(hash).jpg")
    }

    static func save(_ data: Data, hash: String) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(hash), options: .atomic)
    }

    /// What is already in memory, for a first frame with no wait.
    static func cached(_ hash: String) -> UIImage? {
        memory.object(forKey: hash as NSString)
    }

    /// From memory, else from the cache folder, else made from the original and kept.
    static func image(hash: String, original: URL) async -> UIImage? {
        if let cached = memory.object(forKey: hash as NSString) { return cached }
        let image: UIImage? = await Task.detached(priority: .userInitiated) {
            let cached = url(hash)
            if let data = try? Data(contentsOf: cached), let image = UIImage(data: data) {
                return image
            }
            guard let source = CGImageSourceCreateWithURL(original as CFURL, nil),
                  let small = Photo.downsample(source, maxSide: Photo.thumbnailSide)
            else { return nil }
            if let data = Photo.encode(small, quality: 0.8) {
                save(data, hash: hash)
            }
            return UIImage(cgImage: small)
        }.value
        if let image { memory.setObject(image, forKey: hash as NSString) }
        return image
    }
}

/// Two taps the hand can tell apart: a light one when the page takes focus or a photo lands,
/// a firm one when a line is stored.
@MainActor
enum Haptic {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let firm = UIImpactFeedbackGenerator(style: .rigid)

    static func touch() {
        light.impactOccurred()
    }

    static func store() {
        firm.impactOccurred()
    }
}
