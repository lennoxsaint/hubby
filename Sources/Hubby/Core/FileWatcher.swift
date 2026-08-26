import CoreServices
import Foundation

/// One FSEvents stream over the agent apps' data directories so thread
/// renames and new turns show up in Hubby near-instantly. Events are
/// filtered to data files and debounced — Codex writes its WAL constantly.
@MainActor
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private var debounce: DispatchWorkItem?
    private let onChange: () -> Void

    /// File-name fragments worth reacting to; everything else is noise.
    private static let interestingFragments = [".jsonl", ".sqlite", ".db"]
    private static let debounceInterval: TimeInterval = 0.5

    init(paths: [URL], onChange: @escaping () -> Void) {
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)

        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            let relevant = paths.prefix(Int(count)).contains { path in
                FileWatcher.interestingFragments.contains { path.contains($0) }
            }
            if relevant { watcher.scheduleFire() }
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            paths.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes))
        else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    private func scheduleFire() {
        debounce?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: item)
    }

    func stop() {
        debounce?.cancel()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        // Stream teardown must happen via stop(); deinit may run off-main.
    }
}
