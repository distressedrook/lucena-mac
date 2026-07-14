import SwiftUI

/// A skeleton line with a noir shimmer sweeping across it — the "still loading" placeholder shown in
/// the chat while the server (and Maia) warm up. A dim ink bar with a slightly brighter band moving
/// left-to-right on a loop.
struct ShimmerBar: View {
    var width: CGFloat
    var height: CGFloat = 12

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let p = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6   // 0…1 sweep phase
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.primary.opacity(0.07))
                .overlay(
                    GeometryReader { geo in
                        let bandW = geo.size.width * 0.45
                        LinearGradient(colors: [.clear, Color.primary.opacity(0.16), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: bandW)
                            .offset(x: -bandW + p * (geo.size.width + bandW))
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .frame(width: width, height: height)
    }
}

/// A full-bleed shimmer that fills whatever space it's given — a base tint with a light band sweeping
/// across on a loop. Used to cover a pane (e.g. the terminal) until it has loaded.
struct ShimmerFill: View {
    var base: Color
    var highlight: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let p = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6   // 0…1 sweep phase
            GeometryReader { geo in
                let bandW = geo.size.width * 0.4
                base.overlay(
                    LinearGradient(colors: [.clear, highlight, .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: bandW)
                        .offset(x: -bandW + p * (geo.size.width + bandW))
                )
                .clipped()
            }
        }
    }
}

/// A small square that pulses opacity — the "the coach is working" marker beside the status line.
/// Square (not round) to match the noir, right-angled chrome.
struct PulsingSquareDot: View {
    var color: Color = .primary
    var size: CGFloat = 7
    @State private var bright = false
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(bright ? 1 : 0.2)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: bright)
            .onAppear { bright = true }
    }
}

/// A noir "the coach is thinking" light that traces the board while it works. Monochrome by design:
/// a dim silver border sits in shadow, and a single bright searchlight sweeps around it with a long
/// fading tail and a soft white bloom — stark light moving through the dark, no colour. Purely
/// decorative; never intercepts board input.
struct CoachThinkingHalo: View {
    /// Corner radius of the traced border (the board is square, so this is small).
    var cornerRadius: CGFloat = 2

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let head = (t * 0.30).truncatingRemainder(dividingBy: 1)     // searchlight position 0…1
            let breathe = 0.85 + 0.15 * (0.5 + 0.5 * sin(t * 2.2))       // slow pulse of the whole light
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

            ZStack {
                // The ever-present dim rail the light rides on — cold silver in shadow.
                shape
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)

                // The searchlight sweep: a long tapering arc of white, brightest at the head.
                sweep(head: head, in: shape, opacity: breathe, lineWidth: 2.4, blur: 2)

                // The hot core at the very tip, with a tight bloom — the "eye" of the scan.
                sweep(head: head, length: 0.06, in: shape, opacity: breathe, lineWidth: 3.4, blur: 4)
                // A pinpoint white-hot center, no blur, so the tip truly sparks.
                sweep(head: head, length: 0.02, in: shape, opacity: 1, lineWidth: 2, blur: 0.5)
            }
            .compositingGroup()
            .shadow(color: .white.opacity(0.6 * breathe), radius: 5)
            .shadow(color: .white.opacity(0.4 * breathe), radius: 12)
            .shadow(color: .white.opacity(0.22 * breathe), radius: 22)
        }
        .allowsHitTesting(false)
        .blendMode(.plusLighter)   // light adds onto the dark board — the noir "glow through shadow"
    }

    /// A trimmed, blurred white arc starting at `head` and trailing back by `length`, wrapping the
    /// 0/1 seam so it never blinks. Drawn as its own tapering stroke.
    @ViewBuilder
    private func sweep(head: Double, length: Double = 0.30, in shape: RoundedRectangle,
                       opacity: Double, lineWidth: CGFloat = 1.6, blur: CGFloat = 1.4) -> some View {
        let start = head - length
        ZStack {
            arc(from: max(start, 0), to: head, in: shape, opacity: opacity, lineWidth: lineWidth, blur: blur)
            if start < 0 {   // tail spills past the seam → wrap it to the end of the loop
                arc(from: 1 + start, to: 1, in: shape, opacity: opacity, lineWidth: lineWidth, blur: blur)
            }
        }
    }

    private func arc(from: Double, to: Double, in shape: RoundedRectangle,
                     opacity: Double, lineWidth: CGFloat, blur: CGFloat) -> some View {
        shape
            .trim(from: from, to: to)
            .stroke(
                // Dark tail → bright head, so the light reads as moving forward.
                LinearGradient(colors: [.white.opacity(0), .white.opacity(opacity)],
                               startPoint: .leading, endPoint: .trailing),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .blur(radius: blur)
    }
}
