@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Our own camera: the live picture in the app's rounded square, one shutter, nothing else.
/// Tap the picture to focus there, pinch to zoom; the lenses switch on their own, macro included.
struct CameraView: View {
    let onCapture: (Data?) -> Void
    @State private var camera = CameraController()

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width - 32
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    CameraPreview(camera: camera)
                    if let mark = camera.focusMark {
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
                    if camera.denied {
                        VStack(spacing: 10) {
                            Text("Margin has no camera permission.")
                                .font(Theme.serifSmall)
                                .foregroundStyle(Color.white.opacity(0.85))
                            Text("Settings · Margin · Camera")
                                .font(Theme.mono)
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                    }
                }
                .frame(width: side, height: side)
                .clipShape(Theme.square(side))
                .background(Theme.square(side).fill(Color.black))
                .animation(.easeOut(duration: 0.25), value: camera.focusMark == nil)
                .animation(.easeOut(duration: 0.25), value: camera.isZooming)
                Spacer(minLength: 0)
                HStack {
                    Button {
                        onCapture(nil)
                    } label: {
                        Text("Cancel")
                            .font(Theme.mono)
                            .foregroundStyle(Color.white.opacity(0.7))
                            .frame(width: 72, height: 44)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        camera.capture { data in onCapture(data) }
                    } label: {
                        Theme.square(72)
                            .strokeBorder(Color.white, lineWidth: 3)
                            .frame(width: 72, height: 72)
                            .overlay(Theme.square(56).fill(Color.white).frame(width: 56, height: 56))
                    }
                    .buttonStyle(.plain)
                    .disabled(camera.denied || camera.isCapturing)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(white: 0.08))
        .task { await camera.start() }
        .onDisappear { camera.stop() }
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
    private(set) var denied = false
    private(set) var isCapturing = false
    /// Where the last tap asked for focus, in preview points; gone again once the camera has settled.
    private(set) var focusMark: CGPoint?
    /// The zoom as the system camera would show it: 0.5 on the ultra wide, 1 on the wide.
    private(set) var displayZoom: Double = 1
    private(set) var isZooming = false

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "margin.camera")
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
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else { denied = true; return }
        default:
            denied = true
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
        guard !isCapturing else { return }
        isCapturing = true
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
            isCapturing = false
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
