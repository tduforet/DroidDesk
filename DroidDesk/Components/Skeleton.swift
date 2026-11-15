import SwiftUI

/// A grey placeholder bar that stands in for a line of text while a screen loads.
struct SkeletonBar: View {
    var width: CGFloat?
    var height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2.5)
            .fill(.primary.opacity(0.09))
            .frame(width: width, height: height)
    }
}

/// Placeholder rows shaped like a settings-style group: a title, a detail line, and an action on the right.
/// The group pulses softly, or stays still when Reduce Motion is on.
struct SkeletonGroup: View {
    var rows: Int
    var label: String
    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                row(index)
                if index < rows - 1 {
                    Divider()
                }
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor))
        }
        .opacity(dimmed ? 0.45 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                dimmed = true
            }
        }
    }

    private func row(_ index: Int) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBar(width: index.isMultiple(of: 2) ? 150 : 120, height: 12)
                SkeletonBar(width: index.isMultiple(of: 2) ? 210 : 180, height: 9)
            }
            Spacer(minLength: 12)
            SkeletonBar(width: 64, height: 22)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
