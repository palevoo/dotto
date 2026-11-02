import Core
import SwiftUI
import UIKit

/// Photos of one line, full screen. Swipe sideways between them, pinch or double-tap to
/// zoom, pull up or down to close.
struct PhotoViewer: View {
    let photos: [Media]
    @State var index: Int
    let model: NotebookModel
    @Environment(\.dismiss) private var dismiss
    @State private var pull: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { position, photo in
                    ZoomableImage(url: model.mediaURL(photo))
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .never))
            .offset(y: pull)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if abs(value.translation.height) > abs(value.translation.width) {
                            pull = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if abs(value.translation.height) > 110 {
                            dismiss()
                        } else {
                            withAnimation(Motion.settle) { pull = 0 }
                        }
                    }
            )

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .background(Theme.square(44).fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .padding(.top, 8)
            .accessibilityLabel("Close")
        }
        .background(Color.black.opacity(1 - min(abs(pull) / 400, 0.6)).ignoresSafeArea())
        .statusBarHidden()
    }
}

struct ZoomableImage: View {
    let url: URL
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        scale = max(1, min(5, settledScale * value.magnification))
                    }
                    .onEnded { _ in
                        settledScale = scale
                        if scale <= 1.02 {
                            withAnimation(Motion.settle) { reset() }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        guard scale > 1 else { return }
                        offset = CGSize(width: settledOffset.width + value.translation.width,
                                        height: settledOffset.height + value.translation.height)
                    }
                    .onEnded { _ in
                        settledOffset = offset
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(Motion.settle) {
                    if scale > 1 {
                        reset()
                    } else {
                        scale = 2.5
                        settledScale = 2.5
                    }
                }
            }
        }
        .task(id: url) {
            image = await Photo.load(url)
        }
    }

    private func reset() {
        scale = 1
        settledScale = 1
        offset = .zero
        settledOffset = .zero
    }
}
