import SwiftUI

/// The hub's crown: the user's top three priorities, one glance from
/// anywhere. Three lines with a checkbox on the trailing edge — write in a
/// line, drag it vertically to reorder, tick it done. Rank carries a
/// subtle hierarchy (the top line reads strongest). Ticking strikes the
/// line through, then it fades to an empty slot after a short grace
/// (untick within it to undo).
struct PrioritiesSection: View {
    @ObservedObject var store: PriorityStore
    /// Index being dragged and its live vertical translation.
    @State private var dragIndex: Int?
    @State private var dragOffset: CGFloat = 0
    /// Pending strike-then-clear countdowns, by slot id.
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
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(HubbyGlass.accent.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(HubbyGlass.accent.opacity(0.15), lineWidth: 0.5))
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private func row(index: Int, slot: PriorityStore.Priority) -> some View {
        HStack(spacing: 8) {
            // The rank numeral doubles as the drag handle.
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(HubbyGlass.accent.opacity(0.8))
                .frame(width: 14, height: Self.rowHeight)
                .contentShape(Rectangle())
                .gesture(dragGesture(index: index))
            if slot.checkedAt != nil {
                // A ticked line is done, not editable — it lingers struck
                // through for the grace window, then clears.
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(
                        slot.checkedAt != nil
                            ? HubbyGlass.accent : Color.black.opacity(0.25))
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

    // MARK: checkbox

    private func toggleCheck(index: Int, slot: PriorityStore.Priority) {
        if slot.checkedAt == nil {
            // Ticking an empty slot means nothing — nothing to complete.
            guard !slot.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            store.setChecked(true, at: index)
            let id = slot.id
            clearTasks[id]?.cancel()
            clearTasks[id] = Task { @MainActor in
                try? await Task.sleep(for: .seconds(PriorityStore.clearGrace))
                guard !Task.isCancelled else { return }
                if let current = store.slots.firstIndex(where: {
                    $0.id == id && $0.checkedAt != nil
                }) {
                    withAnimation(HubbyAnim.accordion) { store.clear(at: current) }
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
            set: { if store.slots.indices.contains(index) { store.slots[index].text = $0 } })
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
        DragGesture(minimumDistance: 2)
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
