import SwiftUI

struct UndoToast: View {
    let message: String
    let onUndo: (() -> Void)?
    let onDismiss: () -> Void

    private let duration: Double = AppConstants.undoToastSeconds
    @State private var progress: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                if let onUndo {
                    Button("Undo") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onUndo()
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.green)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 3)
                    Capsule()
                        .fill(Color.green)
                        .frame(width: geo.size.width * progress, height: 3)
                }
            }
            .frame(height: 3)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 2)
        // .task auto-cancels when this view leaves the hierarchy, so
        // background/manual-dismiss/foreground transitions don't fire onDismiss
        // after the toast is gone. Replaces the old DispatchQueue.asyncAfter
        // pattern that leaked timers.
        .task {
            withAnimation(.linear(duration: duration)) { progress = 0.0 }
            do {
                try await Task.sleep(for: .seconds(duration))
                onDismiss()
            } catch {
                // Cancelled — view disappeared, no-op.
            }
        }
    }
}
