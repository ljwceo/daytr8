import SwiftUI
import UIKit

/// Fullscreen viewer voor trade-screenshots met pinch-to-zoom (dubbeltik om
/// te resetten/zoomen) en swipen tussen meerdere afbeeldingen.
struct ScreenshotViewerView: View {

    @Environment(\.dismiss) private var dismiss

    let screenshots: [TradeScreenshot]

    @State private var currentIndex: Int
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    init(screenshots: [TradeScreenshot], startIndex: Int) {
        self.screenshots = screenshots
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(screenshots.enumerated()), id: \.element.id) { index, screenshot in
                    zoomableImage(screenshot)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: screenshots.count > 1 ? .always : .never))
            .onChange(of: currentIndex) { _, _ in
                scale = 1
                lastScale = 1
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .padding()
                }
                Spacer()
                if let caption = currentCaption, !caption.isEmpty {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.5))
                        .clipShape(Capsule())
                        .padding(.bottom, 24)
                }
            }
        }
    }

    private var currentCaption: String? {
        guard screenshots.indices.contains(currentIndex) else { return nil }
        return screenshots[currentIndex].caption
    }

    @ViewBuilder
    private func zoomableImage(_ screenshot: TradeScreenshot) -> some View {
        if let uiImage = UIImage(data: screenshot.imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = min(max(lastScale * value, 1), 5)
                        }
                        .onEnded { _ in
                            lastScale = scale
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        scale = scale > 1 ? 1 : 2
                        lastScale = scale
                    }
                }
        } else {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
