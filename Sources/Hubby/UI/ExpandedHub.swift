import SwiftUI

/// The expanded state: a frosted rounded square listing every agent app,
/// each expandable into a drop-down of its live threads.
struct ExpandedHub: View {
    let snapshots: [AgentSnapshot]
    let onJump: (AgentSnapshot, AgentThread?) -> Void
    let onCollapse: () -> Void

    @State private var openApp: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(snapshots) { snapshot in
                        AppRow(
                            snapshot: snapshot,
                            isOpen: openApp == snapshot.id,
                            onToggle: {
                                withAnimation(.spring(duration: 0.3)) {
                                    openApp = openApp == snapshot.id ? nil : snapshot.id
                                }
                            },
                            onJump: onJump)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: HubbyMetrics.hubSize.width, height: HubbyMetrics.hubSize.height)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: HubbyMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HubbyMetrics.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    }

    private var header: some View {
        HStack {
            Text("Hubby")
                .font(.system(.headline, design: .rounded).weight(.bold))
            Spacer()
            Button(action: onCollapse) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Collapse to orb")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private struct AppRow: View {
    let snapshot: AgentSnapshot
    let isOpen: Bool
    let onToggle: () -> Void
    let onJump: (AgentSnapshot, AgentThread?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(snapshot.info.tint.opacity(snapshot.isRunning ? 1 : 0.35))
                        Image(systemName: snapshot.info.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 26, height: 26)

                    Text(snapshot.info.name)
                        .font(.system(.body, design: .rounded).weight(.medium))

                    if snapshot.activeCount > 0 {
                        Text("\(snapshot.activeCount) active")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    if !snapshot.threads.isEmpty {
                        Text("\(snapshot.threads.count)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                dropDown
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isOpen ? 0.06 : 0)))
    }

    private var dropDown: some View {
        VStack(spacing: 0) {
            if snapshot.threads.isEmpty {
                Button {
                    onJump(snapshot, nil)
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.forward.app")
                        Text(snapshot.isRunning ? "Running — open app" : "Open app")
                        Spacer()
                    }
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ForEach(snapshot.threads) { thread in
                    ThreadRow(thread: thread) { onJump(snapshot, thread) }
                }
            }
        }
        .padding(.leading, 26)
        .padding(.bottom, 6)
    }
}

struct ThreadRow: View {
    let thread: AgentThread
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(thread.status() == .active ? .green : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.title)
                        .font(.system(.callout, design: .rounded))
                        .lineLimit(1)
                    if let subtitle = thread.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(relativeTimeFormatter.localizedString(for: thread.lastActivity, relativeTo: Date()))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Jump to this thread")
    }
}
