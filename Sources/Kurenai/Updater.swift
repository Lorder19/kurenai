import AppKit
import CryptoKit
import Security

/// Looks for a newer GitHub release and, when asked, installs it in place.
/// The automatic daily check is opt-in: Kurenai makes no network requests unless you ask for them.
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "Lorder19/kurenai"

    struct Release { let version: String; let page: URL; let zip: URL?; var prerelease = false }

    @Published private(set) var available: Release?
    @Published private(set) var lastResult: String?
    @Published private(set) var installing = false

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "checkUpdates") }
        set {
            UserDefaults.standard.set(newValue, forKey: "checkUpdates")
            if newValue { check() }
        }
    }

    /// Beta builds (GitHub pre-releases) are offered only after entering the tester code. Only its hash
    /// is here, so the open source doesn't give the code away.
    private static let betaCodeHash = "b51b470dfb2a25f570e93ffe74454458d1ce93eea6a23e4bf3a2b72dce2993c2"

    var betas: Bool {
        get { UserDefaults.standard.bool(forKey: "betaUpdates") }
        set { UserDefaults.standard.set(newValue, forKey: "betaUpdates"); objectWillChange.send() }
    }

    /// Turns beta updates on if the code is right.
    func unlockBetas(code: String) -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let hash = SHA256.hash(data: Data(normalized.utf8)).map { String(format: "%02x", $0) }.joined()
        guard hash == Self.betaCodeHash else { Log.write("beta code rejected", "update"); return false }
        betas = true
        Log.write("beta updates on", "update")
        return true
    }

    private var timer: Timer?
    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    func start() {
        if enabled { checkIfDue() }
        let t = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            if self?.enabled == true { self?.checkIfDue() }
        }
        t.tolerance = 600
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func checkIfDue() {
        let last = UserDefaults.standard.double(forKey: "lastUpdateCheck")
        if Date().timeIntervalSince1970 - last > 86_400 { check() }
    }

    func check(then done: ((Release?) -> Void)? = nil) {
        // Testers look through the recent releases including pre-releases; everyone else gets "latest",
        // which GitHub never points at a pre-release.
        let path = betas ? "releases?per_page=15" : "releases/latest"
        guard let api = URL(string: "https://api.github.com/repos/\(Self.repo)/\(path)") else { return }
        var req = URLRequest(url: api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession(configuration: .ephemeral).dataTask(with: req) { [weak self] data, _, error in
            guard let self else { return }
            var found: Release?
            var result = L("Не удалось проверить")
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            let releases = (json as? [[String: Any]]) ?? (json as? [String: Any]).map { [$0] } ?? []
            let candidates = releases.compactMap(Self.release(from:)).filter { self.betas || !$0.prerelease }
            if error == nil, !candidates.isEmpty {
                let best = candidates.max { Self.isNewer($1.version, than: $0.version) }!
                if Self.isNewer(best.version, than: self.current) {
                    found = best
                    result = String(format: L("Доступна версия %@"), best.version)
                } else {
                    result = L("У вас последняя версия")
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
            }
            Log.write("update check (betas \(self.betas)): \(result)", "update")
            DispatchQueue.main.async {
                self.available = found
                self.lastResult = result
                done?(found)
            }
        }.resume()
    }

    private static func release(from json: [String: Any]) -> Release? {
        guard let tag = json["tag_name"] as? String, json["draft"] as? Bool != true,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { ($0["name"] as? String) == "Kurenai.zip" }?["browser_download_url"] as? String
        return Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), page: page,
                       zip: zip.flatMap(URL.init(string:)), prerelease: json["prerelease"] as? Bool ?? false)
    }

    /// "0.5.1" > "0.5.1-beta.2" > "0.5.1-beta.1" > "0.5.0".
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parse(_ v: String) -> (nums: [Int], beta: Int?) {
            let parts = v.split(separator: "-", maxSplits: 1)
            let nums = parts[0].split(separator: ".").map { Int($0) ?? 0 }
            let beta = parts.count > 1 ? (parts[1].split(separator: ".").last.flatMap { Int($0) } ?? 0) : nil
            return (nums, beta)
        }
        let (na, ba) = parse(a), (nb, bb) = parse(b)
        for i in 0..<max(na.count, nb.count) {
            let x = i < na.count ? na[i] : 0, y = i < nb.count ? nb[i] : 0
            if x != y { return x > y }
        }
        switch (ba, bb) {
        case (nil, nil): return false
        case (nil, _): return true            // the release beats its betas
        case (_, nil): return false
        case let (x?, y?): return x > y
        }
    }

    // MARK: Install

    /// Menu entry: check, then offer to install or say there's nothing new.
    func checkInteractively() {
        check { [weak self] release in
            guard let self else { return }
            NSApp.activate()
            if let release {
                self.confirmInstall(release)
            } else {
                let alert = NSAlert()
                alert.messageText = self.lastResult ?? L("У вас последняя версия")
                alert.informativeText = String(format: L("Установлена версия %@."), self.current)
                alert.runModal()
            }
        }
    }

    func confirmInstall(_ release: Release) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(format: L("Обновить Kurenai до версии %@?"), release.version)
        alert.informativeText = L("Kurenai скачает новую версию с GitHub, проверит подпись, заменит себя и перезапустится. История и настройки сохранятся.")
        alert.addButton(withTitle: L("Обновить"))
        alert.addButton(withTitle: L("Что нового"))
        alert.addButton(withTitle: L("Отмена"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: install(release)
        case .alertSecondButtonReturn: NSWorkspace.shared.open(release.page)
        default: break
        }
    }

    func install(_ release: Release) {
        guard let zip = release.zip, !installing else { NSWorkspace.shared.open(release.page); return }
        installing = true
        URLSession(configuration: .ephemeral).downloadTask(with: zip) { [weak self] file, _, error in
            guard let self else { return }
            do {
                guard let file, error == nil else { throw error ?? CocoaError(.fileReadUnknown) }
                let newApp = try Self.unpack(file)
                try Self.verifySameSigner(newApp)
                DispatchQueue.main.async { self.replaceAndRelaunch(with: newApp) }
            } catch {
                DispatchQueue.main.async { self.installing = false; self.fail(error, release: release) }
            }
        }.resume()
    }

    private static func unpack(_ zip: URL) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("KurenaiUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, dir.path]
        try ditto.run()
        ditto.waitUntilExit()
        let app = dir.appendingPathComponent("Kurenai.app")
        guard ditto.terminationStatus == 0, FileManager.default.fileExists(atPath: app.path) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return app
    }

    /// The download must be signed by the same certificate as the running app, otherwise it's not ours.
    private static func verifySameSigner(_ app: URL) throws {
        var me: SecCode?, mine: SecStaticCode?, myReq: SecRequirement?, theirs: SecStaticCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &mine) == errSecSuccess, let mine,
              SecCodeCopyDesignatedRequirement(mine, [], &myReq) == errSecSuccess, let myReq,
              SecStaticCodeCreateWithPath(app as CFURL, [], &theirs) == errSecSuccess, let theirs else {
            throw CocoaError(.fileReadNoPermission)
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(theirs, flags, myReq)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    private func replaceAndRelaunch(with newApp: URL) {
        let current = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp, backupItemName: nil, options: [])
        } catch {
            installing = false
            fail(error, release: available)
            return
        }
        // Start the new copy once this one has quit.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", current.path]
        try? relaunch.run()
        NSApp.terminate(nil)
    }

    private func fail(_ error: Error, release: Release?) {
        Log.write("update failed: \(error)", "update")
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = L("Не получилось обновить")
        alert.informativeText = L("Можно скачать новую версию вручную со страницы релиза.") + "\n\n" + error.localizedDescription
        alert.addButton(withTitle: L("Открыть страницу"))
        alert.addButton(withTitle: L("Отмена"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release?.page ?? URL(string: "https://github.com/\(Self.repo)/releases/latest")!)
        }
    }
}
