import AppKit

/// A small diagnostic log in ~/Library/Logs/Kurenai/kurenai.log. Records what the app does (launch,
/// permissions, layouts, the keyboard tap, errors), never what you type or copy: texts are logged by
/// length only. "Collect a report" zips it with macOS crash reports for the developer.
enum Log {
    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Kurenai", isDirectory: true)
    static let file = folder.appendingPathComponent("kurenai.log")
    private static let queue = DispatchQueue(label: "kurenai.log", qos: .utility)
    private static let maxSize = 2_000_000
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static func write(_ message: @autoclosure () -> String, _ area: String = "app") {
        let line = "\(stamp.string(from: Date())) [\(area)] \(message())\n"
        queue.async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Keep one previous file when this one grows too big.
            if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int, size > maxSize {
                let old = folder.appendingPathComponent("kurenai.1.log")
                try? FileManager.default.removeItem(at: old)
                try? FileManager.default.moveItem(at: file, to: old)
            }
            if let h = try? FileHandle(forWritingTo: file) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            } else {
                FileManager.default.createFile(atPath: file.path, contents: Data(line.utf8), attributes: [.posixPermissions: 0o600])
            }
        }
    }

    /// Writes synchronously; for the last words before a crash.
    static func flush() { queue.sync {} }

    /// Uncaught Objective-C exceptions and fatal signals get one last line in the log before macOS
    /// writes its own crash report.
    static func installCrashHooks() {
        NSSetUncaughtExceptionHandler { e in
            Log.write("CRASH exception \(e.name.rawValue): \(e.reason ?? "") \(e.callStackSymbols.prefix(15).joined(separator: " | "))", "crash")
            Log.flush()
        }
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            signal(sig) { s in
                // Only async-signal-safe calls here: append a fixed line with write(2) and re-raise.
                let msg = "CRASH signal \(s)\n"
                let fd = open(Log.file.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
                if fd >= 0 { _ = msg.withCString { Darwin.write(fd, $0, strlen($0)) }; close(fd) }
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }

    /// What the developer needs to know about this Mac, without anything personal.
    static func systemSummary() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        var arch = "?"
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #endif
        let translated = (try? sysctlInt("sysctl.proc_translated")) == 1 ? " (Rosetta)" : ""
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let layouts = KeyboardLayout.enabled().map { "\($0.0.id)(\($0.0.language))" }.joined(separator: ", ")
        let screens = NSScreen.screens.map { "\(Int($0.frame.width))x\(Int($0.frame.height))" }.joined(separator: ", ")
        return "Kurenai \(version) (\(build)) · macOS \(os) · \(arch)\(translated) · model \(model()) · "
            + "screens \(screens) · layouts \(layouts) · locale \(Locale.current.identifier) · "
            + "accessibility \(Paster.ensureAccessibility(prompt: false)) · app at \(Bundle.main.bundlePath)"
    }

    private static func sysctlInt(_ name: String) throws -> Int {
        var v: Int32 = 0; var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { throw POSIXError(.EINVAL) }
        return Int(v)
    }

    private static func model() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    /// Zips the log, the previous log and Kurenai's crash reports from the last 30 days onto the Desktop.
    static func collectReport() -> URL? {
        flush()
        let fm = FileManager.default
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd-HHmm"
        let dir = fm.temporaryDirectory.appendingPathComponent("Kurenai-report-\(stamp.string(from: Date()))", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? (systemSummary() + "\n").write(to: dir.appendingPathComponent("system.txt"), atomically: true, encoding: .utf8)
        for name in ["kurenai.log", "kurenai.1.log"] {
            try? fm.copyItem(at: folder.appendingPathComponent(name), to: dir.appendingPathComponent(name))
        }
        let reports = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let monthAgo = Date().addingTimeInterval(-30 * 86_400)
        for name in (try? fm.contentsOfDirectory(atPath: reports.path)) ?? []
        where name.hasPrefix("Kurenai") || name.hasPrefix("Clippo") {
            let src = reports.appendingPathComponent(name)
            if let d = (try? fm.attributesOfItem(atPath: src.path))?[.modificationDate] as? Date, d > monthAgo {
                try? fm.copyItem(at: src, to: dir.appendingPathComponent(name))
            }
        }
        let zip = fm.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/\(dir.lastPathComponent).zip")
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", dir.path, zip.path]
        try? ditto.run(); ditto.waitUntilExit()
        try? fm.removeItem(at: dir)
        return ditto.terminationStatus == 0 ? zip : nil
    }
}
