import AppKit

/// Screenshot mode: `Kurenai -KurenaiDemo history|list|queue|settings|onboarding`; `stress` records copies for load tests.
/// Runs on throwaway sample data in a temp folder, never reads or records the real clipboard,
/// registers no shortcuts and leaves the real history and settings untouched.
enum Demo {
    static let panel = argument("KurenaiDemo")

    /// A `-Name value` launch argument. Deliberately not UserDefaults: a value saved with `defaults write`
    /// would switch these modes on for every launch.
    static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-" + name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static var isOn: Bool { panel != nil }

    static let directory: URL = {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("KurenaiDemo", isDirectory: true)
        try? FileManager.default.removeItem(at: d)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// Must run before anything reads Settings: sample preferences go into the argument domain,
    /// which wins over the saved ones and is never written to disk.
    static func prepare() {
        guard isOn else { return }
        var args = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        args["excludedApps"] = ["com.apple.keychainaccess", "com.apple.Passwords", "com.apple.Notes"]
        args["historyLimit"] = 2000
        args["encryptStore"] = true
        args["clearOnQuit"] = false
        args["checkUpdates"] = true
        UserDefaults.standard.setVolatileDomain(args, forName: UserDefaults.argumentDomain)
    }

    static let history: [(String, TimeInterval)] = [
        ("Invoice #2048 is due on Friday, 31 October", 40),
        ("git commit -m \"Release 1.0\"", 300),
        ("Thanks for reaching out! I'll get back to you by tomorrow.\nBest regards,\nAlex", 3600),
        ("https://lorder19.github.io/kurenai/", 5400),
        ("SELECT name, email FROM users WHERE active = 1;", 9000),
        ("221B Baker Street, London NW1 6XE", 90_000),
        ("#d42a35", 180_000),
        ("Meeting moved to 3:30 PM, same Zoom link", 200_000),
    ]
    static let lists: [(String, [String])] = [
        ("Replies", ["Thanks, received!", "Could you send it as a PDF?", "Let's schedule a call this week.",
                     "I'll check and get back to you today.", "Sounds good, approved."]),
        ("Addresses", ["221B Baker Street, London NW1 6XE"]),
    ]
    static let queue = ["Order #4471 shipped", "Tracking: 1Z999AA10123456784", "Delivery: Mon, 27 Oct",
                        "Customer: Jane Cooper", "Total: $129.00"]
}
