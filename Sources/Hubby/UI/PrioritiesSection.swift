import SwiftUI

/// The hub's crown: the user's top three priorities, one glance from
/// anywhere. Three plain lines — write in a line, drag its number to
/// reorder, click its number (or the circle) to tick it done. A ticked
/// line strikes through for a beat (click again to undo), then the queue
/// promotes: everything below moves up a rank and slot 3 opens for the
/// next priority. Completions land in a durable on-disk ledger.
struct PrioritiesSection: View {
    @ObservedObject var store: PriorityStore
    /// Index being dragged and its live vertical translation.
    @State private var dragIndex: Int?
    @State private var dragOffset: CGFloat = 0
    /// Pending strike-then-promote countdowns, by slot id.
    @State private var clearTasks: [UUID: Task<Void, Never>] = [:]
    @FocusState private var focused: UUID?

    private static let rowHeight: CGFloat = 26

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.slots.enumerated()), id: \.element.id) { index, slot in
                row(index: index, slot: slot)
                    .frame(height: Self.rowHeight)
                    .offset(y: offset(for: index))
                    .zIndex(dragIndex == index ? 1 : 0)
            }
        }
        .animation(HubbyAnim.accordion, value: dropTarget)
        .padding(.vertical, 6)
        .padding(.horizontal, 16)
        .padding(.top, 6)
        // No card, no tint — the list sits directly on the glass; one
        // hairline separates it from the agent world below.
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
        }
    }

    private func row(index: Int, slot: PriorityStore.Priority) -> some View {
        HStack(spacing: 8) {
            // The rank numeral is both handle and control: click ticks the
            // line done, drag reorders.
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.30))
                .frame(width: 14, height: Self.rowHeight)
                .contentShape(Rectangle())
                // Simultaneous, not exclusive: plain .onTapGesture lost to
                // the drag's arbitration in this panel. The tap only lands
                // on a near-still click (movement fails it), and a started
                // drag suppresses it via dragIndex.
                .simultaneousGesture(TapGesture().onEnded {
                    if dragIndex == nil { toggleCheck(index: index, slot: slot) }
                })
                .gesture(dragGesture(index: index))
            if slot.checkedAt != nil {
                // A ticked line is done, not editable — it lingers struck
                // through for a beat, then the queue promotes.
                Text(slot.text)
                    .font(rankFont(index))
                    .strikethrough(true, color: .secondary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Priority \(index + 1)", text: text(at: index))
                    .textFieldStyle(.plain)
                    .font(rankFont(index))
                    .foregroundStyle(.primary.opacity(rankOpacity(index)))
                    .focused($focused, equals: slot.id)
                    .onSubmit { focused = nil }
            }
            Button {
                toggleCheck(index: index, slot: slot)
            } label: {
                Image(systemName: slot.checkedAt != nil ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(
                        slot.checkedAt != nil
                            ? Color.black.opacity(0.45) : Color.black.opacity(0.18))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: hierarchy

    private func rankFont(_ index: Int) -> Font {
        switch index {
        case 0: .system(size: 13, weight: .semibold, design: .rounded)
        case 1: .system(size: 12, weight: .medium, design: .rounded)
        default: .system(size: 12, weight: .regular, design: .rounded)
        }
    }

    private func rankOpacity(_ index: Int) -> Double {
        [1, 0.85, 0.7][min(index, 2)]
    }

    // MARK: complete

    private func toggleCheck(index: Int, slot: PriorityStore.Priority) {
        if slot.checkedAt == nil {
            // Ticking an empty slot means nothing — nothing to complete.
            guard !slot.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            focused = nil
            store.setChecked(true, at: index)
            let id = slot.id
            clearTasks[id]?.cancel()
            clearTasks[id] = Task { @MainActor in
                try? await Task.sleep(for: .seconds(PriorityStore.clearGrace))
                guard !Task.isCancelled else { return }
                if let current = store.slots.firstIndex(where: {
                    $0.id == id && $0.checkedAt != nil
                }) {
                    withAnimation(HubbyAnim.accordion) { store.finish(at: current) }
                }
            }
        } else {
            clearTasks[slot.id]?.cancel()
            store.setChecked(false, at: index)
        }
    }

    private func text(at index: Int) -> Binding<String> {
        Binding(
            get: { store.slots.indices.contains(index) ? store.slots[index].text : "" },
            set: { store.setText($0, at: index) })
    }

    // MARK: drag reorder

    /// Where the dragged row would land if released now.
    private var dropTarget: Int? {
        guard let dragIndex else { return nil }
        let shift = Int((dragOffset / Self.rowHeight).rounded())
        return min(max(dragIndex + shift, 0), PriorityStore.slotCount - 1)
    }

    private func offset(for index: Int) -> CGFloat {
        guard let dragIndex, let dropTarget else { return 0 }
        if index == dragIndex { return dragOffset }
        // Rows between the origin and the drop slot step aside.
        if dragIndex < index, index <= dropTarget { return -Self.rowHeight }
        if dropTarget <= index, index < dragIndex { return Self.rowHeight }
        return 0
    }

    private func dragGesture(index: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if dragIndex == nil {
                    dragIndex = index
                    focused = nil
                }
                dragOffset = value.translation.height
            }
            .onEnded { _ in
                let target = dropTarget ?? index
                withAnimation(HubbyAnim.accordion) {
                    store.move(from: index, to: target)
                    dragIndex = nil
                    dragOffset = 0
                }
            }
    }
}
