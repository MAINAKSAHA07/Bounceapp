import SwiftUI

struct HUDOverlay: View {
    let frameCounter: Int
    let lockedTargetsCount: Int
    let currentTargetsCount: Int
    let goalLocked: Bool

    var body: some View {
        if goalLocked {
            VStack {
                Spacer()
                HStack {
                    Text("Frames: \(frameCounter)")
                    Spacer()
                    Text("Current: \(currentTargetsCount) | Locked: \(lockedTargetsCount)")
                    Spacer()
                    if lockedTargetsCount > 0 {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
                .padding(.bottom, 20)
                .padding(.horizontal, 20)
            }
        }
    }
} 