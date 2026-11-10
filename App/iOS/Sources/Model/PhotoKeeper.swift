import Core
import CoreLocation
import Foundation
import Photos

/// A photo taken with dotto's camera is kept in Photos too, when you say so in Setup: the
/// bytes the camera made, at full size, with their moment and place. Asked for as add-only,
/// so this is a way in to your library and never a way to read it. Photos brought from the
/// library or shared in are already there and are not saved again.
@MainActor
@Observable
final class PhotoKeeper {
    private static let onKey = "photos.keep"

    private(set) var isOn = UserDefaults.standard.bool(forKey: PhotoKeeper.onKey)
    /// Whether Photos lets us add, as the phone has it now.
    private(set) var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    /// What Photos said when a save failed, in its own words, so Setup can show it.
    private(set) var trouble: String?

    var allowed: Bool { status == .authorized || status == .limited }
    /// On and allowed: photos are being kept.
    var keeps: Bool { isOn && allowed }

    /// The phone's answer again, after a visit to Settings.
    func refresh() {
        status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    }

    /// Asked once, for adding only. Refused, the answer lives in Settings.
    func turnOn() async {
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard allowed else { return }
        set(true)
    }

    func turnOff() {
        set(false)
    }

    private func set(_ on: Bool) {
        isOn = on
        trouble = nil
        UserDefaults.standard.set(on, forKey: Self.onKey)
    }

    /// The photo as the camera made it goes into Photos. Nothing waits on it: the line has
    /// its own copy already.
    func keep(_ data: Data, at moment: Date, location: Location?) {
        guard keeps else { return }
        let place = location.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        Task {
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: data, options: nil)
                    request.creationDate = moment
                    request.location = place
                }
                trouble = nil
            } catch {
                NSLog("keeping a photo in Photos failed: \(error)")
                trouble = error.localizedDescription
            }
        }
    }
}
