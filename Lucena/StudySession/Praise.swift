import Foundation

/// Local, canned praise for a correct drill move. v1 hot path shows the ✓ badge plus one of these —
/// NO LLM, NO chess interpretation (the model is a learning harness, it never explains the move).
/// Generic on purpose: never names a piece, square, or motif, so it can never be wrong.
enum Praise {
    /// A fresh random line each time; avoids repeating the immediately previous one.
    static func next() -> String {
        var pick = lines.randomElement() ?? "Nice."
        if lines.count > 1 { while pick == last { pick = lines.randomElement() ?? pick } }
        last = pick
        return pick
    }

    private static var last = ""

    private static let lines: [String] = [
        "Excellent move!", "Well played.", "Nicely done.", "Great find!", "That's the one.",
        "Spot on.", "Perfect.", "You've got it.", "Exactly right.", "Sharp.",
        "Clean.", "Very nice.", "Beautiful.", "That's it exactly.", "Superb.",
        "Right on the money.", "Crisp play.", "Nailed it.", "Textbook.", "Precise.",
        "Lovely move.", "Well spotted.", "Good eye.", "That's the idea.", "Strong.",
        "Confident play.", "You saw it.", "Cleanly done.", "Just right.", "Excellent choice.",
        "Bang on.", "Neat.", "That works.", "Smart.", "Well found.",
        "Solid.", "Good instincts.", "Nicely spotted.", "There it is.", "First-rate.",
        "Impressive.", "You're on it.", "Deft.", "Handled well.", "That's correct.",
        "Great instinct.", "Clinical.", "Well seen.", "Yes — that's the move.", "Assured.",
        "Fine play.", "You found it.", "Cool and precise.", "That's the ticket.", "Elegant.",
        "Right idea, right move.", "Composed.", "Tidy.", "Good call.", "Sharp eye.",
        "That's the winner.", "Convincing.", "Well judged.", "You nailed the idea.", "Slick.",
        "Excellent judgment.", "Right where it needs to be.", "Clear thinking.", "On the button.", "Astute.",
        "That's exactly it.", "Good work.", "Well reasoned.", "Cleanly found.", "Bravo.",
        "Nicely judged.", "You read it well.", "Decisive.", "Perfectly played.", "Keen.",
        "That's the move to make.", "Sure-footed.", "You saw right through it.", "Confidently done.", "Top move.",
        "Well done indeed.", "Sharp as ever.", "You had it.", "Cleanly struck.", "Just so.",
        "Excellent instinct.", "That's the point.", "Nicely worked out.", "Right answer.", "Assuredly done.",
        "You found the mark.", "Crisply played.", "Good vision.", "That's precisely it.", "Masterful.",
    ]
}
