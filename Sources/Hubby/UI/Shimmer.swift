import SwiftUI

/// The working indicator, ported from Codex's TUI shimmer and recolored
/// blush: not a rotating glyph but a soft light band sweeping the text — a
/// raised-cosine (Hann) window travelling `length + 2×10` cells every 2.0s.
/// Every instance is phase-locked to one app-wide clock (Codex locks to
/// process start), so all generating rows breathe together. Period, band
/// width, easing, and the 0.9 max blend all match Codex; only the highlight
/// differs — blush pink instead of the terminal background.
enum Shimmer {
    /// One app-wide phase clock.
    static let epoch = Date()
    static let sweepSeconds: Double = 2.0
    /// The band enters this many cells before the text and exits as many after.
    static let padding: Double = 10
    static let bandHalfWidth: Double = 5
    static let maxBlend: Double = 0.9

    /// The row ink the sweep starts from (titles are near-black on blush glass).
    static let base: UInt32 = 0x2A2226
    /// The blush-pink peak of the sweep (the mascot's pink).
    static let highlight: UInt32 = 0xE89EB0

    /// The band centre, in cell coordinates, for a run of `length` cells.
    static func bandCenter(length: Double, at date: Date) -> Double {
        let period = length + padding * 2
        let phase = date.timeIntervalSince(epoch)
            .truncatingRemainder(dividingBy: sweepSeconds) / sweepSeconds
        return phase * period - padding
    }

    /// Hann-window highlight intensity (0…1) at `cell` for a band centre.
    static func intensity(cell: Double, bandCenter: Double) -> Double {
        let dist = abs(cell - bandCenter)
        guard dist <= bandHalfWidth else { return 0 }
        return 0.5 * (1 + cos(.pi * dist / bandHalfWidth))
    }

    /// Base→highlight blend at intensity `t` (already maxBlend-scaled).
    static func color(_ t: Double) -> Color {
        func channel(_ shift: UInt32) -> Double {
            let from = Double((base >> shift) & 0xFF)
            let to = Double((highlight >> shift) & 0xFF)
            return (from + (to - from) * t) / 255
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }
}

/// The generating status dot: cell 0 of the row's sweep — it flares blush
/// as the band passes through, then rests on the ink.
struct ShimmerDot: View {
    /// Total cells in this row's sweep domain (dot + gap + title).
    let rowCells: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Circle().fill(Shimmer.color(Shimmer.maxBlend))
                .frame(width: 7, height: 7)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let band = Shimmer.bandCenter(length: rowCells, at: context.date)
                let t = Shimmer.intensity(cell: 0, bandCenter: band) * Shimmer.maxBlend
                // The dot rests blush-tinted (it must read as "working" even
                // between sweeps) and saturates to full blush at the peak.
                Circle().fill(Shimmer.color(0.35 + t * 0.65))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

/// Text swept by the shimmer band. `cellOffset` places the text inside the
/// row's shared sweep domain so the dot and the title carry one continuous
/// band, exactly like Codex's "• Working".
struct ShimmerText: View {
    let text: String
    let font: Font
    var cellOffset: Double = 0
    let rowCells: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            Text(text).font(font)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let band = Shimmer.bandCenter(length: rowCells, at: context.date)
                Text(text).font(font)
                    .foregroundStyle(gradient(bandCenter: band))
                    .lineLimit(1)
            }
        }
    }

    /// The Hann window sampled across the text's width. Sampling (rather
    /// than placing exact band-edge stops) sidesteps clamping/ordering
    /// headaches when the band is partly or wholly outside the text.
    private func gradient(bandCenter: Double) -> LinearGradient {
        let length = max(Double(text.count), 1)
        let samples = 12
        let stops = (0...samples).map { i -> Gradient.Stop in
            let unit = Double(i) / Double(samples)
            let cell = cellOffset + unit * length
            let t = Shimmer.intensity(cell: cell, bandCenter: bandCenter) * Shimmer.maxBlend
            return Gradient.Stop(color: Shimmer.color(t), location: unit)
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
}
