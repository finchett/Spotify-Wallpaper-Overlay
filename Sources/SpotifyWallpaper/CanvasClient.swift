import Foundation
import CryptoKit

/// Simple stderr logging for diagnosing the (unofficial) Canvas fetch.
func log(_ message: String) {
    FileHandle.standardError.write(Data("[canvas] \(message)\n".utf8))
}

/// Fetches a track's Spotify **Canvas** (the short looping video) via Spotify's internal,
/// UNOFFICIAL endpoint. This is not a public API: it can break at any time (Spotify has
/// added bot-protection to the token endpoint), and many tracks have no Canvas. Every
/// failure path returns nil so the caller falls back to the animated cover.
final class CanvasClient {
    private let session = URLSession(configuration: .default)
    private var cachedToken: String?
    private var tokenExpiry = Date.distantPast

    // A realistic desktop browser UA — the token endpoint rejects obviously-scripted clients.
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    // Spotify rotates the TOTP secret + version roughly monthly. By default we auto-fetch
    // the current pair from a community secrets feed (self-healing). You can override:
    //   SPOTIFY_SECRETS_URL   — point at a feed you trust (must map version -> cipher ints)
    //   SPOTIFY_TOTP_CIPHER + SPOTIFY_TOTP_VER — pin values manually, skipping the network
    //
    // ⚠️ The default feed URL below is a best-effort community source that I could not
    // verify from here — check the [canvas] logs and override SPOTIFY_SECRETS_URL if the
    // fetch fails or the format doesn't match.
    static let defaultSecretsURL =
        "https://raw.githubusercontent.com/xyloflake/spot-secrets-go/main/secrets/secretDict.json"

    struct Candidate { let cipher: [Int]; let ver: String }

    private let totpCipher: [Int]     // fallback cipher (env or hardcoded)
    private let totpVer: String       // fallback version
    private let manualOverride: Bool  // env pins the secret; don't auto-fetch
    private let secretsURL: String
    private var resolvedCandidates: [Candidate]?

    init() {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["SPOTIFY_TOTP_CIPHER"] {
            let parsed = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            totpCipher = parsed.isEmpty ? TOTP.defaultCipher : parsed
        } else {
            totpCipher = TOTP.defaultCipher
        }
        totpVer = env["SPOTIFY_TOTP_VER"] ?? TOTP.defaultVersion
        manualOverride = env["SPOTIFY_TOTP_CIPHER"] != nil
        secretsURL = env["SPOTIFY_SECRETS_URL"] ?? Self.defaultSecretsURL
    }

    /// Drop the cached token so the next fetch re-authenticates (e.g. after the cookie changes).
    func resetToken() {
        cachedToken = nil
        tokenExpiry = .distantPast
    }

    func fetchCanvasURL(trackURI: String, completion: @escaping (URL?) -> Void) {
        // AppleScript gives us "spotify:track:..." which is exactly the entity URI needed.
        guard trackURI.hasPrefix("spotify:track:") else { completion(nil); return }
        accessToken { [weak self] token in
            guard let self, let token else { completion(nil); return }
            self.requestCanvas(trackURI: trackURI, token: token, completion: completion)
        }
    }

    // MARK: - Web access token (TOTP handshake)

    private func accessToken(_ completion: @escaping (String?) -> Void) {
        if let cachedToken, Date() < tokenExpiry {
            completion(cachedToken)
            return
        }
        resolveCandidates { [weak self] candidates in
            guard let self, !candidates.isEmpty else { completion(nil); return }
            // Prefer Spotify's server time so the TOTP window matches theirs; fall back to
            // local time (fine as long as the Mac's clock is NTP-synced). Fetched once and
            // reused across version attempts.
            self.fetchServerTime { serverSeconds in
                let ts = serverSeconds ?? Int(Date().timeIntervalSince1970)
                self.tryExchange(candidates: candidates, index: 0, ts: ts, completion: completion)
            }
        }
    }

    /// The newest totpVer is sometimes broken while the previous one still works, so we
    /// walk candidates newest-first until the token endpoint accepts one.
    private func tryExchange(candidates: [Candidate], index: Int, ts: Int,
                             completion: @escaping (String?) -> Void) {
        guard index < candidates.count else {
            log("all \(candidates.count) TOTP version(s) rejected")
            completion(nil)
            return
        }
        let candidate = candidates[index]
        let code = TOTP.generate(cipher: candidate.cipher, timeSeconds: ts)
        exchangeToken(totp: code, ver: candidate.ver) { [weak self] token in
            guard let self else { completion(nil); return }
            if let token {
                completion(token)
            } else {
                log("version \(candidate.ver) rejected; trying next")
                self.tryExchange(candidates: candidates, index: index + 1, ts: ts, completion: completion)
            }
        }
    }

    /// Resolves TOTP candidates (newest-first), once per launch: manual env override wins,
    /// otherwise auto-fetch from the secrets feed, otherwise the hardcoded fallback.
    private func resolveCandidates(_ completion: @escaping ([Candidate]) -> Void) {
        if let resolvedCandidates {
            completion(resolvedCandidates)
            return
        }
        let fallback = [Candidate(cipher: totpCipher, ver: totpVer)]
        if manualOverride {
            resolvedCandidates = fallback
            log("using manually pinned TOTP secret (version \(totpVer))")
            completion(fallback)
            return
        }
        fetchSecrets { [weak self] fetched in
            guard let self else { return }
            let result: [Candidate]
            if let fetched, !fetched.isEmpty {
                result = fetched
                log("auto-fetched \(fetched.count) TOTP version(s); newest \(fetched[0].ver)")
            } else {
                result = fallback
                log("secret auto-fetch failed; falling back to version \(self.totpVer) (override SPOTIFY_SECRETS_URL)")
            }
            self.resolvedCandidates = result
            completion(result)
        }
    }

    private func fetchSecrets(_ completion: @escaping ([Candidate]?) -> Void) {
        guard let url = URL(string: secretsURL) else { completion(nil); return }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard let data, status == 200 else {
                log("secrets fetch failed (HTTP \(status)): \(error?.localizedDescription ?? "no data")")
                completion(nil); return
            }
            let parsed = CanvasClient.parseSecrets(data)
            if parsed == nil {
                let preview = String(data: data, encoding: .utf8)?.prefix(160) ?? ""
                log("secrets fetch parsed nothing usable — format mismatch? \(preview)")
            }
            completion(parsed)
        }.resume()
    }

    /// Parser for the community feed. Accepts a {version: cipherInts} dict (the current
    /// format) or an array of {version, secret} objects. Returns candidates newest-first,
    /// capped so we don't hammer the token endpoint if everything fails.
    static func parseSecrets(_ data: Data) -> [Candidate]? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }

        func cipher(from any: Any) -> [Int]? {
            if let ints = any as? [Int] { return ints.isEmpty ? nil : ints }
            if let nums = any as? [NSNumber] { return nums.isEmpty ? nil : nums.map(\.intValue) }
            if let s = any as? String {
                let parts = s.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                return parts.isEmpty ? nil : parts
            }
            return nil
        }

        var found: [(version: Int, cipher: [Int])] = []
        if let dict = obj as? [String: Any] {
            for (key, value) in dict {
                guard let v = Int(key), let c = cipher(from: value) else { continue }
                found.append((v, c))
            }
        } else if let array = obj as? [[String: Any]] {
            for entry in array {
                guard let v = (entry["version"] as? Int) ?? (entry["version"] as? NSNumber)?.intValue,
                      let secret = entry["secret"], let c = cipher(from: secret) else { continue }
                found.append((v, c))
            }
        }
        guard !found.isEmpty else { return nil }

        return found
            .sorted { $0.version > $1.version }
            .prefix(4)
            .map { Candidate(cipher: $0.cipher, ver: String($0.version)) }
    }

    private func fetchServerTime(_ completion: @escaping (Int?) -> Void) {
        guard let url = URL(string: "https://open.spotify.com/api/server-time") else {
            completion(nil); return
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://open.spotify.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://open.spotify.com", forHTTPHeaderField: "Origin")
        session.dataTask(with: request) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil); return
            }
            // Shape has shifted over time; accept either key/number type.
            let t = (json["serverTime"] as? Int) ?? (json["serverTime"] as? Double).map(Int.init)
            completion(t)
        }.resume()
    }

    private func exchangeToken(totp: String, ver: String, completion: @escaping (String?) -> Void) {
        var comps = URLComponents(string: "https://open.spotify.com/api/token")!
        comps.queryItems = [
            .init(name: "reason", value: "transport"),
            .init(name: "productType", value: "web_player"),
            .init(name: "totp", value: totp),
            .init(name: "totpServer", value: totp),
            .init(name: "totpVer", value: ver),
        ]
        guard let url = comps.url else { completion(nil); return }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://open.spotify.com", forHTTPHeaderField: "Origin")
        request.setValue("https://open.spotify.com/", forHTTPHeaderField: "Referer")
        request.setValue("WebPlayer", forHTTPHeaderField: "App-Platform")
        // A stored sp_dc cookie yields a non-anonymous token, which canvaz actually serves
        // Canvas data to (anonymous tokens get an empty response). Set once via the menu.
        if let spDc = Credentials.spDc() {
            request.setValue("sp_dc=\(spDc)", forHTTPHeaderField: "Cookie")
        }

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { completion(nil); return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let token = json["accessToken"] as? String, !token.isEmpty else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? (error?.localizedDescription ?? "no data")
                log("token exchange failed (HTTP \(status)): \(body.prefix(300))")
                completion(nil); return
            }
            let anon = (json["isAnonymous"] as? Bool) ?? true
            log("got token (HTTP \(status), anonymous=\(anon)) via TOTP")
            self.cachedToken = token
            if let expMs = json["accessTokenExpirationTimestampMs"] as? Double {
                self.tokenExpiry = Date(timeIntervalSince1970: expMs / 1000 - 60)
            } else {
                self.tokenExpiry = Date().addingTimeInterval(1800)
            }
            completion(token)
        }.resume()
    }

    // MARK: - Canvas lookup (protobuf over HTTP)

    private func requestCanvas(trackURI: String, token: String, completion: @escaping (URL?) -> Void) {
        guard let url = URL(string:
            "https://spclient.wg.spotify.com/canvaz-cache/v0/canvases")
        else { completion(nil); return }

        // EntityCanvazRequest { repeated Entity entities = 1 { string entity_uri = 1 } }
        let entity = Protobuf.string(field: 1, trackURI)
        let body = Protobuf.message(field: 1, entity)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-protobuf", forHTTPHeaderField: "Accept")
        request.httpBody = body

        session.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            guard let data, status == 200 else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? (error?.localizedDescription ?? "no data")
                log("canvas request failed (HTTP \(status)): \(body.prefix(200))")
                completion(nil); return
            }
            // EntityCanvazResponse { repeated Canvaz canvases = 1 { string url = 2 } }
            guard let canvaz = Protobuf.firstLengthDelimited(field: 1, in: data),
                  let urlBytes = Protobuf.firstLengthDelimited(field: 2, in: canvaz),
                  let urlString = String(data: urlBytes, encoding: .utf8),
                  let canvasURL = URL(string: urlString) else {
                let hex = data.map { String(format: "%02x", $0) }.joined()
                log("canvas HTTP 200 but no url (\(data.count) bytes: \(hex)) — no Canvas for this track, or token not entitled")
                completion(nil); return
            }
            log("canvas found: \(urlString)")
            completion(canvasURL)
        }.resume()
    }
}

/// Replicates the TOTP that Spotify's web player computes to obtain an access token.
///
/// ⚠️ FRAGILE: the cipher + version are a secret baked into the web player's JavaScript,
/// and Spotify rotates them roughly monthly. These defaults are known-STALE (version 5
/// expired 2025-10-18) — supply the current pair via SPOTIFY_TOTP_CIPHER / SPOTIFY_TOTP_VER.
/// A `token exchange failed (HTTP 400)` with `totpVerExpired` means it's time to update them.
enum TOTP {
    // Snapshot of the current feed value (version 61) so Canvas still has a shot if the
    // feed is unreachable at launch. Auto-fetch supersedes this when it succeeds.
    static let defaultCipher: [Int] =
        [44, 55, 47, 42, 70, 40, 34, 114, 76, 74, 50, 111, 120, 97, 75, 76, 94, 102, 43, 69, 49, 120, 118, 80, 64, 78]
    static let defaultVersion = "61"

    static func generate(cipher: [Int], timeSeconds: Int, period: Int = 30, digits: Int = 6) -> String {
        // Derive the HMAC key exactly as the web player does: XOR-transform the cipher,
        // concatenate the resulting decimals, and use those UTF-8 bytes as the key.
        let transformed = cipher.enumerated().map { index, value in value ^ ((index % 33) + 9) }
        let key = SymmetricKey(data: Data(transformed.map(String.init).joined().utf8))

        var counter = UInt64(timeSeconds / period).bigEndian
        let counterData = withUnsafeBytes(of: &counter) { Data($0) }
        let hash = Array(HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: key))

        // Standard RFC 6238 dynamic truncation.
        let offset = Int(hash[hash.count - 1] & 0x0f)
        let binary = (UInt32(hash[offset] & 0x7f) << 24)
                   | (UInt32(hash[offset + 1]) << 16)
                   | (UInt32(hash[offset + 2]) << 8)
                   |  UInt32(hash[offset + 3])
        let otp = binary % UInt32(pow(10, Double(digits)))
        return String(format: "%0\(digits)d", otp)
    }
}

/// Just enough protobuf wire-format to build the request and read one field out of the
/// response — avoids pulling in swift-protobuf for two tiny messages.
enum Protobuf {
    static func string(field: Int, _ value: String) -> Data {
        lengthDelimited(field: field, Data(value.utf8))
    }
    static func message(field: Int, _ payload: Data) -> Data {
        lengthDelimited(field: field, payload)
    }

    private static func lengthDelimited(field: Int, _ payload: Data) -> Data {
        var out = Data()
        out.append(varint(UInt64(field << 3 | 2)))   // wire type 2 = length-delimited
        out.append(varint(UInt64(payload.count)))
        out.append(payload)
        return out
    }

    private static func varint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    /// Returns the payload bytes of the first length-delimited field with the given number.
    static func firstLengthDelimited(field: Int, in data: Data) -> Data? {
        var i = data.startIndex
        while i < data.endIndex {
            guard let (tag, afterTag) = readVarint(data, i) else { return nil }
            i = afterTag
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x7)
            switch wireType {
            case 0:   // varint
                guard let (_, next) = readVarint(data, i) else { return nil }
                i = next
            case 2:   // length-delimited
                guard let (len, afterLen) = readVarint(data, i) else { return nil }
                let end = data.index(afterLen, offsetBy: Int(len), limitedBy: data.endIndex) ?? data.endIndex
                if fieldNumber == field { return data.subdata(in: afterLen..<end) }
                i = end
            case 5:   // 32-bit
                i = data.index(i, offsetBy: 4, limitedBy: data.endIndex) ?? data.endIndex
            case 1:   // 64-bit
                i = data.index(i, offsetBy: 8, limitedBy: data.endIndex) ?? data.endIndex
            default:
                return nil
            }
        }
        return nil
    }

    private static func readVarint(_ data: Data, _ start: Data.Index) -> (UInt64, Data.Index)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var i = start
        while i < data.endIndex {
            let byte = data[i]
            i = data.index(after: i)
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return (result, i) }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }
}
