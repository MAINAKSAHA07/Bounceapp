import SwiftUI

struct ResetButton: View {
    let onReset: () -> Void
    
    var body: some View {
        Button(action: onReset) {
            HStack {
                Image(systemName: "arrow.clockwise")
                Text("Reset All")
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .background(Color.red)
            .cornerRadius(10)
        }
        .padding(.bottom, 100) // Above HUD
        .padding(.leading, 20)
    }
} 