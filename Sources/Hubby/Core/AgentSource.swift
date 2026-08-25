import AppKit
import Foundation

/// The adapter protocol — one conformer per agent app. This is also Hubby's
/// plugin contract: implement it, register in `ThreadStore.defaultSources()`.
///
/// Rules (see AGENTS.md): read-only on other apps' data, parse defensively,
/// return [] rather than throwing, degrade to running-state when unreadable.
protocol AgentSource {
    var info: AgentAppInfo { get }
    /// Whether the agent app (or its sessions) is currently live.
    var isRunning: Bool { get }
    /// Current threads, newest first. Called off the main thread every tick.
    func fetchThreads() -> [AgentThread]
}

extension AgentSource {
    var isRunning: Bool {
        let running = NSWorkspace.shared.runningApplications
        return running.contains { app in
            guard let id = app.bundleIdentifier else { return false }
            return info.bundleIDs.contains(id)
        }
    }

    func snapshot() -> AgentSnapshot {
        let threads = fetchThreads()
        return AgentSnapshot(info: info, isRunning: isRunning || !threads.isEmpty, threads: threads)
    }

    /// Bring the agent app frontmost. `thread` lets adapters target a
    /// specific window/tab; the default just activates the app.
    func jump(to thread: AgentThread?) {
        activateApp()
    }

    func activateApp() {
        for bundleID in info.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config)
                return
            }
        }
    }
}
