import SwiftUI

struct GoalDetectionView: View {
    let liveFrame: UIImage
    let frameSize: CGSize
    let detectedTapeRegion: CGRect?
    let goalLocked: Bool

    var body: some View {
        GeometryReader { geo in
            let viewSize = geo.size
            let scale    = frameSize.width > 0 ? viewSize.width / frameSize.width : 1
            let yOffset  = frameSize.height > 0
                ? (viewSize.height - frameSize.height * scale) / 2
                : 0

            Image(uiImage: liveFrame)
                .resizable()
                .scaledToFit()
                .frame(width: viewSize.width, height: viewSize.height)
                .overlay(
                    Group {
                        if !goalLocked,
                           let region = detectedTapeRegion,
                           region != .zero
                        {
                            let rect = CGRect(
                                x: region.origin.x * scale,
                                y: region.origin.y * scale + yOffset,
                                width: region.width * scale,
                                height: region.height * scale
                            )
                            Rectangle()
                                .stroke(Color.pink, lineWidth: 4)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                        }
                    }
                )
        }
    }
} 