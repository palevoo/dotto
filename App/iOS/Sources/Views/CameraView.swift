@preconcurrency import AVFoundation
import SwiftUI
import UIKit

/// Our own camera: the live picture in the app's rounded square, one shutter, nothing else.
struct CameraView: View {
    let onCapture: (Data?) -> Void
    @State private var camera = CameraController()

    var body: some View {
        GeometryReader { geometry in
            let side = geometry.size.width - 32
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    CameraPreview(session: camera.session)
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
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

@MainActor
@Observable
final class CameraController: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private(set) var denied = false
    private(set) var isCapturing = false

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "margin.camera")
    private var position: AVCaptureDevice.Position = .back
    private var completion: ((Data?) -> Void)?

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
        queue.async {
            session.beginConfiguration()
            session.sessionPreset = .photo
            Self.attachInput(to: session, position: position)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            session.startRunning()
        }
    }

    func stop() {
        let session = self.session
        queue.async { session.stopRunning() }
    }

    func flip() {
        position = position == .back ? .front : .back
        let session = self.session
        let position = self.position
        queue.async {
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            Self.attachInput(to: session, position: position)
            session.commitConfiguration()
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

    private nonisolated static func attachInput(to session: AVCaptureSession, position: AVCaptureDevice.Position) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
    }
}
