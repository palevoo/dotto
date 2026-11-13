@preconcurrency import AVFoundation
import Photos
import PhotosUI
import SwiftUI
import UIKit

/// What the camera hands back: the photo's bytes untouched, and the words read off it when
/// the frame was held and a passage selected.
struct Shot {
    let data: Data
    var quote: String?
}

/// Our own camera: the live picture in the app's rounded square, one shutter, the library
/// in the corner. Tap the picture to focus there, pinch to zoom; the lenses switch on their
/// own, macro included. The words button on the picture holds the frame with its words
/// live, as the Camera app does: select a passage and Quote takes it, with the photo, into
/// the live line.
struct CameraView: View {
    @Binding var picked: [PhotosPickerItem]
    let onCapture: (Shot?) -> Void
    @State private var camera = CameraController()
    @State private var showLibrary = false
    @State private var latest: UIImage?
    /// The picture: live, being held, or held still with its words live.
    @State private var frame: Frame = .live
    /// What is selected in the held frame right now. The passage Quote takes is the last
    /// selection that was not empty: a touch that lands on the button may end the selection first.
    @State private var selected = ""

    private enum Frame: Equatable {
        case live
        case holding
        case held(Held)

        var isLive: Bool { self == .live }
        var held: Held? { if case .held(let held) = self { return held }; return nil }
    }

    private struct Held: Equatable {
        let data: Data
        let image: UIImage
        var passage = ""
    }

    private var passage: String { frame.held?.passage ?? "" }

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width - 32
            VStack(spacing: 0) {
                HStack {
                    Button {
                        onCapture(nil)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                    Spacer()
                    if frame.held == nil, LiveTextView.isSupported, camera.stage.hasCamera {
                        Button {
                            hold()
                        } label: {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 17, weight: .light))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(!frame.isLive || camera.stage != .live)
                        .accessibilityLabel("Hold the frame and read its words")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer(minLength: 0)
                ZStack {
                    CameraPreview(camera: camera)
                    if let held = frame.held {
                        LiveTextView(image: held.image, selected: $selected)
                    }
                    if let mark = camera.focusMark, frame.isLive {
                        Theme.square(64)
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                            .frame(width: 64, height: 64)
                            .position(mark)
                            .transition(.opacity)
                    }
                    if camera.isZooming {
                        Text(Format.zoom(camera.displayZoom))
                            .font(Theme.mono)
                            .foregroundStyle(Color.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Theme.square(28).fill(Color.black.opacity(0.35)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 14)
                            .transition(.opacity)
                    }
                    switch camera.stage {
                    case .denied:
                        VStack(spacing: 10) {
                            Text("dotto has no camera permission.")
                                .font(Theme.serifSmall)
                                .foregroundStyle(Color.white.opacity(0.85))
                            Text("Settings · dotto · Camera")
                                .font(Theme.mono)
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                    case .unavailable:
                        Text("No camera on this device.")
                            .font(Theme.serifSmall)
                            .foregroundStyle(Color.white.opacity(0.85))
                    case .starting, .live, .capturing:
                        EmptyView()
                    }
                }
                .frame(width: side, height: side)
                .clipShape(Theme.square(side))
                .background(Theme.square(side).fill(Color.black))
                .animation(.easeOut(duration: 0.25), value: camera.focusMark == nil)
                .animation(.easeOut(duration: 0.25), value: camera.isZooming)
                Spacer(minLength: 0)
                if frame.held != nil {
                    reading
                } else {
                    controls
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.2), value: frame.held == nil)
            .animation(.easeOut(duration: 0.15), value: passage.isEmpty)
        }
        .onChange(of: selected) { _, words in
            guard !words.isEmpty, var held = frame.held else { return }
            held.passage = words
            frame = .held(held)
        }
        .background(Color(white: 0.08))
        .photosPicker(isPresented: $showLibrary, selection: $picked, maxSelectionCount: 20,
                      matching: .images, photoLibrary: .shared())
        .task { await camera.start() }
        .task { latest = await PhotoLibrary.latestThumbnail(side: 88) }
        .onDisappear { camera.stop() }
    }

    /// The frame as it is now, held still so its words can be read. The picture does not
    /// move, only the controls under it change.
    private func hold() {
        guard frame.isLive else { return }
        frame = .holding
        camera.capture { data in
            Task {
                guard let data, let image = await Photo.decode(data) else {
                    frame = .live
                    return
                }
                selected = ""
                frame = .held(Held(data: data, image: image))
                Haptic.touch()
            }
        }
    }

    /// Under a held frame: the way back to the live picture, and Quote once words are selected.
    private var reading: some View {
        HStack {
            Button {
                frame = .live
                selected = ""
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 72, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to the camera")
            Spacer()
            if !passage.isEmpty {
                HStack(spacing: 10) {
                    Button {
                        guard let held = frame.held else { return }
                        Haptic.store()
                        onCapture(Shot(data: held.data, quote: held.passage))
                    } label: {
                        Text("Quote")
                            .font(Theme.sansSmall.weight(.medium))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 22)
                            .frame(height: 44)
                            .background(Theme.square(44).fill(Color.white))
                    }
                    .buttonStyle(.plain)
                    Text(wordCount(passage))
                        .font(Theme.mono)
                        .foregroundStyle(Color.white.opacity(0.6))
                        .monospacedDigit()
                }
                .transition(.opacity)
            } else {
                Text("Select the words")
                    .font(Theme.mono)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .transition(.opacity)
            }
            Spacer()
            Color.clear.frame(width: 72, height: 44)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    /// Under the live picture: the library, the shutter, the other camera.
    private var controls: some View {
        HStack {
            Button {
                Task {
                    await PhotoLibrary.ask()
                    showLibrary = true
                }
            } label: {
                Group {
                    if let latest {
                        Image(uiImage: latest)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Theme.square(44))
                .overlay(Theme.square(44).strokeBorder(Color.white.opacity(latest == nil ? 0 : 0.5), lineWidth: 1))
                .frame(width: 72, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("From the library")
            Spacer()
            Button {
                // A photo that did not come back leaves the camera open to try again.
                camera.capture { data in
                    if let data { onCapture(Shot(data: data)) }
                }
            } label: {
                Theme.square(72)
                    .strokeBorder(Color.white, lineWidth: 3)
                    .frame(width: 72, height: 72)
                    .overlay(Theme.square(56).fill(Color.white).frame(width: 56, height: 56))
            }
            .buttonStyle(.plain)
            .disabled(camera.stage != .live || !frame.isLive)
            .accessibilityLabel("Take photo")
            Spacer()
            Button {
                camera.flip()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(width: 72, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch camera")
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }
}

struct CameraPreview: UIViewRepresentable {
    let camera: CameraController

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:))))
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(camera: camera) }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    @MainActor
    final class Coordinator: NSObject {
        let camera: CameraController

        init(camera: CameraController) { self.camera = camera }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PreviewView else { return }
            let point = gesture.location(in: view)
            camera.focus(at: view.previewLayer.captureDevicePointConverted(fromLayerPoint: point), mark: point)
        }

        @objc func pinch(_ gesture: UIPinchGestureRecognizer) {
            camera.pinch(gesture.state, scale: gesture.scale)
        }
    }
}

@MainActor
@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()

    /// Where the camera stands. It starts when the view appears and is live once the session
    /// runs with a lens; a capture takes it out of live until the photo is back. Denied and
    /// unavailable are final for this showing. Only live takes a photo or switches lenses.
    enum Stage: Equatable {
        case starting
        case live
        case capturing
        case denied
        case unavailable

        /// Whether there is a picture to show at all.
        var hasCamera: Bool { self == .starting || self == .live || self == .capturing }
    }
    private(set) var stage: Stage = .starting
    /// Where the last tap asked for focus, in preview points; gone again once the camera has settled.
    private(set) var focusMark: CGPoint?
    /// The zoom as the system camera would show it: 0.5 on the ultra wide, 1 on the wide.
    private(set) var displayZoom: Double = 1
    private(set) var isZooming = false

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "dotto.camera")
    private let rig = Rig()
    private var position: AVCaptureDevice.Position = .back
    private var completion: ((Data?) -> Void)?
    private var markFade: Task<Void, Never>?
    private var zoomFade: Task<Void, Never>?

    /// The device and what the pinch started from. Touched on the camera queue only.
    private final class Rig: @unchecked Sendable {
        var device: AVCaptureDevice?
        var pinchStart: CGFloat = 1
        var sceneObserver: NSObjectProtocol?
    }

    func start() async {
        guard stage == .starting else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { stage = .denied; return }
        default:
            stage = .denied
            return
        }
        let session = self.session
        let output = self.output
        let position = self.position
        let rig = self.rig
        let queue = self.queue
        queue.async {
            session.beginConfiguration()
            session.sessionPreset = .photo
            Self.attach(to: session, position: position, rig: rig, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            session.startRunning()
            let live = session.isRunning && !session.inputs.isEmpty
            Task { @MainActor in
                guard self.stage == .starting else { return }
                self.stage = live ? .live : .unavailable
            }
        }
    }

    func stop() {
        let session = self.session
        let rig = self.rig
        queue.async {
            Self.detach(rig: rig)
            session.stopRunning()
        }
    }

    func flip() {
        guard stage == .live else { return }
        position = position == .back ? .front : .back
        let session = self.session
        let position = self.position
        let rig = self.rig
        let queue = self.queue
        queue.async {
            session.beginConfiguration()
            Self.detach(rig: rig)
            for input in session.inputs { session.removeInput(input) }
            Self.attach(to: session, position: position, rig: rig, queue: queue)
            session.commitConfiguration()
        }
        isZooming = false
        displayZoom = 1
    }

    /// Focus and expose on the tapped point. The camera goes back to watching the whole
    /// scene by itself as soon as the scene changes enough.
    func focus(at point: CGPoint, mark: CGPoint) {
        Haptic.touch()
        focusMark = mark
        markFade?.cancel()
        markFade = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            focusMark = nil
        }
        let rig = self.rig
        queue.async {
            guard let device = rig.device, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.autoExpose) {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
        }
    }

    /// Pinch to zoom, from the ultra wide up to ten times the wide lens.
    func pinch(_ state: UIGestureRecognizer.State, scale: CGFloat) {
        let rig = self.rig
        switch state {
        case .began:
            zoomFade?.cancel()
            isZooming = true
            queue.async { rig.pinchStart = rig.device?.videoZoomFactor ?? 1 }
        case .changed:
            queue.async {
                guard let device = rig.device, (try? device.lockForConfiguration()) != nil else { return }
                let floor = device.minAvailableVideoZoomFactor
                let ceiling = min(device.maxAvailableVideoZoomFactor, Self.wideFactor(of: device) * 10)
                let factor = min(max(rig.pinchStart * scale, floor), ceiling)
                device.videoZoomFactor = factor
                device.unlockForConfiguration()
                let shown = Double(factor * device.displayVideoZoomFactorMultiplier)
                Task { @MainActor in self.displayZoom = shown }
            }
        default:
            zoomFade = Task {
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                isZooming = false
            }
        }
    }

    /// Hands back the photo's bytes untouched; decoding happens off the main thread later.
    func capture(_ completion: @escaping (Data?) -> Void) {
        guard stage == .live else { return }
        stage = .capturing
        self.completion = completion
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .balanced
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        output.capturePhoto(with: settings, delegate: self)
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            if stage == .capturing { stage = .live }
            let done = completion
            completion = nil
            done?(data)
        }
    }

    // MARK: - On the camera queue

    /// The back camera is the whole set of lenses as one device, so it can switch between
    /// them and drop into macro on its own. Front is the one lens there is.
    private nonisolated static func attach(to session: AVCaptureSession, position: AVCaptureDevice.Position,
                                           rig: Rig, queue: DispatchQueue) {
        let wanted: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: wanted, mediaType: .video, position: position).devices
        guard let device = wanted.lazy.compactMap({ type in found.first { $0.deviceType == type } }).first,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        rig.device = device
        settle(device)
        rig.sceneObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: device, queue: nil
        ) { _ in
            queue.async { Self.settle(device) }
        }
    }

    private nonisolated static func detach(rig: Rig) {
        if let observer = rig.sceneObserver { NotificationCenter.default.removeObserver(observer) }
        rig.sceneObserver = nil
        rig.device = nil
    }

    /// Watch the whole scene from the middle, as the camera does when nobody has tapped.
    /// On first use this also puts the zoom on the wide lens rather than the ultra wide.
    private nonisolated static func settle(_ device: AVCaptureDevice) {
        guard (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if device.videoZoomFactor < wideFactor(of: device), device.isVirtualDevice {
            device.videoZoomFactor = wideFactor(of: device)
        }
        let middle = CGPoint(x: 0.5, y: 0.5)
        if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = middle }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = middle }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        device.isSubjectAreaChangeMonitoringEnabled = true
    }

    /// On a virtual device zoom 1 is the ultra wide; the wide lens sits at the first switch-over.
    private nonisolated static func wideFactor(of device: AVCaptureDevice) -> CGFloat {
        guard device.constituentDevices.first?.deviceType == .builtInUltraWideCamera,
              let first = device.virtualDeviceSwitchOverVideoZoomFactors.first else { return 1 }
        return CGFloat(truncating: first)
    }
}
