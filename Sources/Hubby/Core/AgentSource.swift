import AppKit
import Foundation

/// The adapter protocol — one conformer per agent app. This is also Hubby's
/// plugin contract: implement it, register in `ThreadStore.defaultSources()`.
///
/// Rules (see AGENTS.md): read-only on other apps' data, parse defensively,
/// return [] rather than throwing, degrade to running-state when unreadable.
protocol AgentSource: Sendable {
    var info: AgentAppInfo { get }
    /// Whether the agent app (or its sessions) is currently live.
    /// `runningBundleIDs` is captured on the main thread each tick so this
    /// can run on any executor without touching NSWorkspace.
    func isRunning(runningBundleIDs: Set<String>) -> Bool
    /// Current threads, newest first. Called off the main thread every tick.
    func fetchThreads() -> [AgentThread]
    /// Directories the FSEvents watcher monitors to refresh this source
    /// the moment its app writes (renames, new turns...).
    var watchedPaths: [URL] { get }
}

extension AgentSource {
    var watchedPaths: [URL] { [] }
    func isRunning(runningBundleIDs: Set<String>) -> Bool {
        !runningBundleIDs.isDisjoint(with: info.bundleIDs)
    }

    func snapshot(runningBundleIDs: Set<String>) -> AgentSnapshot {
        let threads = fetchThreads()
        let running = isRunning(runningBundleIDs: runningBundleIDs) || !threads.isEmpty
        return AgentSnapshot(info: info, isRunning: running, threads: threads)
    }

    /// Bring the thread frontmost — as precisely as the app allows. Adapters
    /// override with deep links or Accessibility window matching; the
    /// default just activates the app and says so honestly.
    func jump(to thread: AgentThread?) -> JumpResolution {
        activateApp() ? .appActivated : .failed
    }

    @discardableResult
    func activateApp() -> Bool {
        for bundleID in info.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config)
                return true
            }
        }
        return false
    }
}
