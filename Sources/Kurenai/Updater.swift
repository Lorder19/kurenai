import AppKit
import Security

/// Looks for a newer GitHub release and, when asked, installs it in place.
/// The automatic daily check is opt-in: Kurenai makes no network requests unless you ask for them.
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "Lorder19/kurenai"

    struct Release { let version: String; let page: URL; let zip: URL? }

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
        guard let api = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var req = URLRequest(url: api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession(configuration: .ephemeral).dataTask(with: req) { [weak self] data, _, error in
            guard let self else { return }
            var found: Release?
            var result = L("Не удалось проверить")
            if error == nil, let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String,
               let page = (json["html_url"] as? String).flatMap(URL.init(string:)) {
                let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                if Self.isNewer(version, than: self.current) {
                    let assets = json["assets"] as? [[String: Any]] ?? []
                    let zip = assets.first { ($0["name"] as? String) == "Kurenai.zip" }?["browser_download_url"] as? String
                    // Only ever download from GitHub over https; the signature check is the real gate, this is belt and braces.
                    let url = zip.flatMap(URL.init(string:)).flatMap { u in
                        u.scheme == "https" && ["github.com", "objects.githubusercontent.com"].contains(u.host ?? "") ? u : nil
                    }
                    found = Release(version: version, page: page, zip: url)
                    result = String(format: L("Доступна версия %@"), version)
                } else {
                    result = L("У вас последняя версия")
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
            }
            DispatchQueue.main.async {
                self.available = found
                self.lastResult = result
                done?(found)
            }
        }.resume()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
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
