import CryptoKit
import Foundation
import Security

/// AES-GCM encryption for Kurenai's data files, so the history isn't readable as plain text
/// by anything that just scans or uploads files.
enum Vault {
    private static let magic = Data("CLIPOENC1".utf8)
    private static let service = "Clipo history key" // legacy Keychain item name, only read for migration

    static func isEncrypted(_ data: Data) -> Bool { data.starts(with: magic) }

    static func seal(_ plain: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(plain, using: key(create: true)).combined else {
            throw CocoaError(.coderInvalidValue)
        }
        return magic + combined
    }

    static func open(_ data: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: data.dropFirst(magic.count))
        return try AES.GCM.open(box, using: key(create: false))
    }

    private static var cached: SymmetricKey?
    private static let lock = NSLock() // store and queue save on different queues

    /// The key sits in a 0600 file next to the data. The Keychain was tried first, but with a self-signed
    /// build macOS re-asks for the login password after every rebuild/update, which reads as an attack.
    private static let keyURL = Store.directory.appendingPathComponent(".key") // not Store.shared: Store.init calls into Vault

    private static func key(create: Bool) throws -> SymmetricKey {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        if let raw = try? Data(contentsOf: keyURL), raw.count == 32 {
            cached = SymmetricKey(data: raw)
            return cached!
        }
        // One-time move of a key created by earlier builds out of the Keychain.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        let fromKeychain = SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
        guard let raw = fromKeychain ?? (create ? SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } : nil) else {
            throw CocoaError(.fileReadNoPermission)
        }
        try FileManager.default.createDirectory(at: keyURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // O_EXCL: never overwrite or follow an existing key file; 0600 from the first byte.
        let fd = Darwin.open(keyURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(fd) }
        guard raw.withUnsafeBytes({ Darwin.write(fd, $0.baseAddress, $0.count) }) == raw.count else { throw POSIXError(.EIO) }
        if fromKeychain != nil {
            SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
        }
        cached = SymmetricKey(data: raw)
        return cached!
    }
}
