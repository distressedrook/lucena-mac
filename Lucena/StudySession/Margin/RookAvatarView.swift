import SwiftUI

/// The rook — the brand mark with a job (V1_LAYOUT.md): the margin's author.
/// Poses key off the beat tone. v1 renders the logo mark with a small pose
/// accent (a tinted underline tick); real pose illustrations replace this
/// when the design pass lands — the API is the pose, not the artwork.
struct RookAvatarView: View {
    enum Pose { case idle, praise, teach, correct }
    let pose: Pose
    var size: CGFloat = Theme.Size.rookAvatar

    var body: some View {
        VStack(spacing: Theme.Spacing.hair) {
            Image("logo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .opacity(pose == .idle ? 0.7 : 1)   // idle = watchful, not loud
            Rectangle()
                .fill(accent)
                .frame(width: size * 0.6, height: 2)
                .opacity(pose == .idle ? 0 : 1)
        }
        .accessibilityLabel("Coach")
    }

    private var accent: Color {
        switch pose {
        case .idle: Theme.Palette.ink22
        case .praise: Theme.Palette.correctGreen
        case .teach: Theme.Palette.coachBlue
        case .correct: Theme.Palette.mistakeRed
        }
    }
}
