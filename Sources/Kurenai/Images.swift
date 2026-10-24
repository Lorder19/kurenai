import AppKit
import CryptoKit

/// Copied images live as separate files next to store.json (named by content hash, so a repeat copy
/// reuses the file); the history keeps only the name. Encrypted like the rest when that setting is on.
enum ImageStore {
    static let maxBytes = 25_000_000

    static let dir: URL = {
        let d = Store.directory.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return d
    }()

    private static let thumbs = NSCache<NSString, NSImage>()

    /// PNG bytes of whatever image is on the pasteboard, or nil.
    static func png(from pb: NSPasteboard) -> Data? {
        // Files copied in Finder also carry an icon image; that is not what the user copied.
        if pb.types?.contains(.fileURL) == true { return nil }
        if let png = pb.data(forType: .png) { return png }
        guard let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Writes the image and returns its file name.
    static func save(_ png: Data) -> String? {
        let name = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined() + ".png"
        let url = dir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            var data = png
            if Settings.shared.encryptStore {
                guard let sealed = try? Vault.seal(png) else { return nil }
                data = sealed
            }
            guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return name
    }

    static func load(_ name: String) -> Data? {
        guard let raw = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return Vault.isEncrypted(raw) ? try? Vault.open(raw) : raw
    }

    static func thumbnail(_ name: String) -> NSImage? {
        if let t = thumbs.object(forKey: name as NSString) { return t }
        guard let data = load(name), let img = NSImage(data: data) else { return nil }
        thumbs.setObject(img, forKey: name as NSString)
        return img
    }

    static func size(_ name: String) -> NSSize? {
        guard let img = thumbnail(name), let rep = img.representations.first else { return nil }
        return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    /// Deletes files no longer referenced by any clip.
    static func prune(keeping names: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for f in files where !names.contains(f) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
            thumbs.removeObject(forKey: f as NSString)
        }
    }
}
