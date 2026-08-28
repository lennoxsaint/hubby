import SwiftUI

/// The one-click unblock control on a blocked row: a translucent capsule,
/// green "Approve" for plan approvals, amber "Choose…" for multi-choice.
/// Hovering the row floats the PromptCard with context; clicking Approve
/// actuates (guarded), clicking Choose… just reveals the card.
struct PromptPill: View {
    let prompt: PendingPrompt
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(prompt.kind == .approve ? "Approve ↗" : "Choose…")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(color.opacity(0.14)))
                .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var color: Color {
        prompt.kind == .approve ? HubbyGlass.running : HubbyGlass.needsYou
    }
}

/// The hover card for a blocked prompt: what's being asked, and — for
/// multi-choice — each option as a clickable row. Interactive, unlike the
/// recap card; the hub keeps it alive while the cursor is inside it.
struct PromptCard: View {
    let thread: AgentThread
    let prompt: PendingPrompt
    /// nil = approve; otherwise the 0-based option picked.
    let onAnswer: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("⚠")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HubbyGlass.needsYou)
                Text(prompt.kind == .approve ? "Waiting for approval" : "Waiting for a choice")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(HubbyGlass.needsYou)
            }
            Text(prompt.question)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if prompt.kind == .approve {
                // The approval dialog's option list varies (auto-accept /
                // clear-context variants), so the final key press stays the
                // user's — Hubby lands them on the dialog instead.
                actionRow(label: "Take me to the approval ↗", color: HubbyGlass.running) {
                    onAnswer(nil)
                }
            } else if prompt.actuatable {
                ForEach(Array(prompt.options.enumerated()), id: \.offset) { index, option in
                    optionRow(index: index, option: option)
                }
            } else {
                Text("Answer in the app — this prompt needs more than one selection.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0xFCF3F5).opacity(0.98)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(HubbyGlass.hairline, lineWidth: 0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(HubbyGlass.needsYou.opacity(0.30), lineWidth: 1)
                .blur(radius: 0.6))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private func optionRow(index: Int, option: PendingPrompt.Option) -> some View {
        Button {
            onAnswer(index)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(HubbyGlass.needsYou.opacity(0.8)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(1)
                    if let description = option.description,
                       let sentence = RecapText.excerpt(description, limit: 70) {
                        Text(sentence)
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.04)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func actionRow(
        label: String, color: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Capsule().fill(color.opacity(0.14)))
                .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
