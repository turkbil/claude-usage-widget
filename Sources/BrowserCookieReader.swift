import Foundation
import SQLite3
import Security
import CommonCrypto

/// One Chromium-family browser source.
struct BrowserSource {
    let id: String
    let displayName: String
    let cookiesPath: String
    let keychainService: String

    static let chrome = BrowserSource(
        id: "chrome", displayName: "Google Chrome",
        cookiesPath: NSString("~/Library/Application Support/Google/Chrome/Default/Cookies").expandingTildeInPath,
        keychainService: "Chrome Safe Storage"
    )
    static let brave = BrowserSource(
        id: "brave", displayName: "Brave Browser",
        cookiesPath: NSString("~/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies").expandingTildeInPath,
        keychainService: "Brave Safe Storage"
    )
    static let edge = BrowserSource(
        id: "edge", displayName: "Microsoft Edge",
        cookiesPath: NSString("~/Library/Application Support/Microsoft Edge/Default/Cookies").expandingTildeInPath,
        keychainService: "Microsoft Edge Safe Storage"
    )
    static let arc = BrowserSource(
        id: "arc", displayName: "Arc",
        cookiesPath: NSString("~/Library/Application Support/Arc/User Data/Default/Cookies").expandingTildeInPath,
        keychainService: "Arc Safe Storage"
    )

    static func enabled(in prefs: Preferences) -> [BrowserSource] {
        var list: [BrowserSource] = []
        if prefs.browserChromeEnabled { list.append(.chrome) }
        if prefs.browserBraveEnabled  { list.append(.brave) }
        if prefs.browserEdgeEnabled   { list.append(.edge) }
        if prefs.browserArcEnabled    { list.append(.arc) }
        if list.isEmpty { list.append(.chrome) }   // safety net
        return list
    }
}

/// Reads and decrypts the claude.ai sessionKey from a Chromium-family cookie
/// store. All Chromium browsers share the same crypto and SQLite schema —
/// only the on-disk path and the Keychain service name differ.
enum BrowserCookieReader {

    /// Try each enabled browser in order; first one with a session wins.
    static func sessionKey(prefs: Preferences) throws -> String {
        var lastError: Error?
        for source in BrowserSource.enabled(in: prefs) {
            do { return try sessionKey(from: source) }
            catch { lastError = error }
        }
        throw lastError ?? WidgetError.message(L("error.no_session"))
    }

    static func sessionKey(from source: BrowserSource) throws -> String {
        // Copy DB to avoid lock conflicts.
        let tmp = NSTemporaryDirectory() + "claude_widget_\(source.id)_\(UUID().uuidString).db"
        try? FileManager.default.removeItem(atPath: tmp)
        do { try FileManager.default.copyItem(atPath: source.cookiesPath, toPath: tmp) }
        catch { throw WidgetError.message(L("error.cookie_db")) }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        var db: OpaquePointer?
        guard sqlite3_open(tmp, &db) == SQLITE_OK else {
            throw WidgetError.message(L("error.cookie_db"))
        }
        defer { sqlite3_close(db) }

        let sql = "SELECT encrypted_value FROM cookies WHERE host_key LIKE '%claude.ai%' AND name='sessionKey' ORDER BY length(encrypted_value) DESC LIMIT 1"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw WidgetError.message(L("error.cookie_db"))
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            throw WidgetError.message(L("error.no_session"))
        }
        guard let blobPtr = sqlite3_column_blob(stmt, 0) else {
            throw WidgetError.message(L("error.no_session"))
        }
        let blobLen = Int(sqlite3_column_bytes(stmt, 0))
        let encrypted = Data(bytes: blobPtr, count: blobLen)

        let password = try keychainPassword(service: source.keychainService, account: source.keychainAccount)
        let key      = try pbkdf2(password: password, salt: "saltysalt", rounds: 1003, keyLen: 16)

        guard encrypted.count > 3 else { throw WidgetError.message(L("error.cookie_decrypt")) }
        let prefix = String(data: encrypted.prefix(3), encoding: .utf8) ?? ""
        guard prefix == "v10" || prefix == "v11" else {
            throw WidgetError.message(L("error.unknown_cookie_version", prefix as NSString))
        }
        let ct    = encrypted.suffix(from: 3)
        let iv    = Data(repeating: 0x20, count: 16)
        let plain = try aesCBCDecrypt(Data(ct), key: key, iv: iv)

        return try stripHashPrefixAndDecode(plain)
    }

    // MARK: - shared crypto helpers

    static func keychainPassword(service: String, account: String) throws -> String {
        let q: [String: Any] = [
            kSecClass as String:           kSecClassGenericPassword,
            kSecAttrService as String:     service,
            kSecAttrAccount as String:     account,
            kSecReturnData as String:      true,
            kSecMatchLimit as String:      kSecMatchLimitOne,
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecUserCanceled || status == errSecAuthFailed {
            throw WidgetError.message(L("error.keychain_denied"))
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let s = String(data: data, encoding: .utf8) else {
            throw WidgetError.message(L("error.keychain_read", Int(status)))
        }
        return s
    }

    static func pbkdf2(password: String, salt: String, rounds: Int, keyLen: Int) throws -> Data {
        let passData = password.data(using: .utf8)!
        let saltData = salt.data(using: .utf8)!
        var derived  = Data(count: keyLen)
        let status = derived.withUnsafeMutableBytes { (db: UnsafeMutableRawBufferPointer) -> Int32 in
            passData.withUnsafeBytes { (pb: UnsafeRawBufferPointer) -> Int32 in
                saltData.withUnsafeBytes { (sb: UnsafeRawBufferPointer) -> Int32 in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pb.bindMemory(to: Int8.self).baseAddress, passData.count,
                        sb.bindMemory(to: UInt8.self).baseAddress, saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        UInt32(rounds),
                        db.bindMemory(to: UInt8.self).baseAddress, keyLen
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw WidgetError.message(L("error.cookie_decrypt")) }
        return derived
    }

    static func aesCBCDecrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        let cap = data.count + kCCBlockSizeAES128
        var out = Data(count: cap)
        var outLen = 0
        let status = out.withUnsafeMutableBytes { (ob: UnsafeMutableRawBufferPointer) -> Int32 in
            data.withUnsafeBytes { (ib: UnsafeRawBufferPointer) -> Int32 in
                key.withUnsafeBytes { (kb: UnsafeRawBufferPointer) -> Int32 in
                    iv.withUnsafeBytes { (vb: UnsafeRawBufferPointer) -> Int32 in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            kb.baseAddress, key.count,
                            vb.baseAddress,
                            ib.baseAddress, data.count,
                            ob.baseAddress, cap,
                            &outLen
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw WidgetError.message(L("error.cookie_decrypt")) }
        out.count = outLen
        return out
    }

    private static func stripHashPrefixAndDecode(_ plain: Data) throws -> String {
        let bytes = [UInt8](plain)
        var start = 0
        if bytes.count > 32 {
            let head = bytes[0..<32]
            if head.contains(where: { $0 < 0x20 || $0 >= 0x7F }) { start = 32 }
        }
        var end = bytes.count
        while end > start && (bytes[end - 1] < 0x20 || bytes[end - 1] >= 0x7F) { end -= 1 }
        guard end > start else { throw WidgetError.message(L("error.cookie_empty")) }
        let printable = bytes[start..<end].filter { $0 >= 0x20 && $0 < 0x7F }
        let result = String(bytes: printable, encoding: .ascii) ?? ""
        guard !result.isEmpty else { throw WidgetError.message(L("error.cookie_empty")) }
        return result
    }
}

private extension BrowserSource {
    /// All Chromium browsers store the master key under account "<displayName>"
    /// but some are different. Edge actually uses "Microsoft Edge" not the full
    /// display name on some versions; we try multiple candidates to be robust.
    var keychainAccount: String {
        switch id {
        case "chrome": return "Chrome"
        case "brave":  return "Brave"
        case "edge":   return "Microsoft Edge"
        case "arc":    return "Arc"
        default:       return displayName
        }
    }
}
