import SwiftUI

struct TargetDetectionView: View {
    let lockedTargets: [[AnyHashable: Any]]
    let frameSize: CGSize
    let viewSize: CGSize  // pass in the GeometryReader's geo.size
    let yOffset: CGFloat
    let scale: CGFloat

    var body: some View {
        ForEach(Array(lockedTargets.enumerated()), id: \.offset) { index, target in
            if let cx = target["centerX"]  as? CGFloat,
               let cy = target["centerY"]  as? CGFloat,
               let r  = target["radius"]   as? CGFloat
            {
                // Calculate inflated rectangle (20% larger)
                let baseRect = CGRect(x: cx - r, y: cy - r, width: 2*r, height: 2*r)
                let inflatedRect = baseRect.insetBy(dx: -baseRect.width*0.1, dy: -baseRect.height*0.1)

                let scaled = CGRect(
                    x: inflatedRect.minX * scale,
                    y: inflatedRect.minY * scale + yOffset,
                    width: inflatedRect.width  * scale,
                    height: inflatedRect.height * scale
                )

                Rectangle()
                    .stroke(Color.green, lineWidth: 3)
                    .frame(width: scaled.width, height: scaled.height)
                    .position(x: scaled.midX, y: scaled.midY)
            }
        }
    }
} 