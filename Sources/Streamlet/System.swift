import CommonCrypto
import CryptoKit
import Foundation
import SQLite3

enum Keychain {
    enum Result { case found(String), notFound, failed(String) }

    private static let lock = NSLock()
    private static var cache: [String: String] = [:]

    /// Reads a generic password via /usr/bin/security (same path cc-switch uses).
    /// Secrets are cached in memory so macOS prompts at most once per launch.
    static func password(service: String, account: String) -> Result {
        let key = service + "\u{0}" + account
        lock.lock(); if let v = cache[key] { lock.unlock(); return .found(v) }; lock.unlock()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", service, "-a", account, "-w"]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        do { try p.run() } catch { return .failed(error.localizedDescription) }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus == 44 { return .notFound }
        guard p.terminationStatus == 0 else {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return .failed("security exit \(p.terminationStatus) \(msg.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        var s = String(decoding: data, as: UTF8.self)
        if s.hasSuffix("\n") { s.removeLast() }
        guard !s.isEmpty else { return .notFound }
        lock.lock(); cache[key] = s; lock.unlock()
        return .found(s)
    }
}

enum SQLiteReader {
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// Opens strictly read-only. `immutable` additionally skips journals/shm so a
    /// live app's database is never touched.
    static func rows(path: String, sql: String, args: [String] = [], immutable: Bool = false) -> [[String: Data]]? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        var uri = URL(fileURLWithPath: path).absoluteString + "?mode=ro"
        if immutable { uri += "&immutable=1" }
        var db: OpaquePointer?
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            sqlite3_close(db); return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2000)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        for (i, a) in args.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), a, -1, transient) }
        var out: [[String: Data]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Data] = [:]
            for c in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, c))
                let n = Int(sqlite3_column_bytes(stmt, c))
                if let p = sqlite3_column_blob(stmt, c), n > 0 {
                    row[name] = Data(bytes: p, count: n)
                } else {
                    row[name] = Data()
                }
            }
            out.append(row)
        }
        return out
    }
}

/// Chromium/Electron `safeStorage` on macOS: "v10" + AES-128-CBC,
/// key = PBKDF2-SHA1(password, "saltysalt", 1003, 16), IV = 16 spaces.
enum ElectronSafeStorage {
    static let salt = Array("saltysalt".utf8)
    static let iv = [UInt8](repeating: 0x20, count: 16)

    static func deriveKey(_ password: String) -> [UInt8]? {
        var key = [UInt8](repeating: 0, count: 16)
        let pw = Array(password.utf8)
        let rc = pw.withUnsafeBufferPointer { pwp in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pwp.baseAddress.map { UnsafeRawPointer($0).assumingMemoryBound(to: Int8.self) }, pw.count,
                                 salt, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003, &key, key.count)
        }
        return rc == kCCSuccess ? key : nil
    }

    static func crypt(_ op: Int, key: [UInt8], data: [UInt8]) -> [UInt8]? {
        var out = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        var moved = 0
        let rc = CCCrypt(CCOperation(op), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                         key, key.count, iv, data, data.count, &out, out.count, &moved)
        guard rc == kCCSuccess else { return nil }
        return Array(out.prefix(moved))
    }

    static func decrypt(_ encrypted: [UInt8], password: String) -> String? {
        guard encrypted.count > 3, Array(encrypted.prefix(3)) == Array("v10".utf8),
              let key = deriveKey(password),
              let clear = crypt(kCCDecrypt, key: key, data: Array(encrypted.dropFirst(3))) else { return nil }
        return String(bytes: clear, encoding: .utf8)
    }

    static func encrypt(_ plain: String, password: String) -> [UInt8]? {
        guard let key = deriveKey(password), let enc = crypt(kCCEncrypt, key: key, data: Array(plain.utf8)) else { return nil }
        return Array("v10".utf8) + enc
    }

    /// Records in VS Code style `state.vscdb` are JSON `{"type":"Buffer","data":[...]}`.
    static func bufferBytes(_ record: Data) -> [UInt8]? {
        guard let o = J.obj(J.parse(record)), let arr = o["data"] as? [NSNumber] else { return nil }
        return arr.map { UInt8(truncatingIfNeeded: $0.intValue) }
    }
}

func sha256Hex(_ s: String) -> String {
    SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
}

func maskKey(_ s: String) -> String { s.count > 8 ? "…" + s.suffix(4) : "…" }
