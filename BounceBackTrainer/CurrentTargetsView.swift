import SwiftUI

struct CurrentTargetsView: View {
    let currentTargets: [[AnyHashable: Any]]
    let frameSize: CGSize
    let viewSize: CGSize
    let yOffset: CGFloat
    let scale: CGFloat
    let onLockTargets: () -> Void
    
    var body: some View {
        ZStack {
            // Show current detected targets with yellow rectangles
            ForEach(Array(currentTargets.enumerated()), id: \.offset) { index, target in
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
                        .stroke(Color.yellow, lineWidth: 3)
                        .frame(width: scaled.width, height: scaled.height)
                        .position(x: scaled.midX, y: scaled.midY)
                }
            }
            
            // Lock targets button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: onLockTargets) {
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("Lock \(currentTargets.count) Targets")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                    }
                    .padding(.bottom, 100) // Above HUD
                    .padding(.trailing, 20)
                }
            }
            
            // Info text when no targets to lock
            if currentTargets.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("All targets already locked")
                            .font(.caption)
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                            .padding(.bottom, 100)
                            .padding(.trailing, 20)
                    }
                }
            }
        }
    }
} 