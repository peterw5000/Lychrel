import SwiftUI

// Right-hand pane showing the spiral for the last completed run.
struct SpiralPane: View {
    let image: CGImage?
    let error: String?
    let isRunning: Bool

    @Environment(\.displayScale) private var displayScale
    @State private var scaleToFit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Spiral").font(.headline)
                Spacer()
                legendItem("Lychrel", color: .red)
                legendItem("Palindrome", color: .white)
                Button(scaleToFit ? "Actual Size" : "Scale to Fit") {
                    withAnimation(.smooth) { scaleToFit.toggle() }
                }
                .disabled(image == nil)
            }

            if let image {
                SpiralScrollView(image: image, scaleToFit: scaleToFit, displayScale: displayScale)
                    .background(Color(white: 0.5))
            } else {
                placeholder
            }
        }
        .padding()
        .frame(minWidth: 320, idealWidth: 560, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
    }

    private var placeholder: some View {
        Group {
            if let error {
                Text(error).foregroundStyle(.red)
            } else if isRunning {
                ProgressView("Waiting for the run to finish…")
            } else {
                Text("Run a check to draw the spiral.").foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func legendItem(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .stroke(.secondary, lineWidth: 0.5)
                .frame(width: 10, height: 10)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
