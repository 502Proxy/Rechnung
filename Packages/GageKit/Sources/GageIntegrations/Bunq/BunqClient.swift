import Foundation
import GageCore
import GageSecurity
import OSLog

public enum BunqEnvironment: String, Sendable, Codable, CaseIterable {
    case production
    case sandbox

    var host: String {
        switch self {
        case .production: "api.bunq.com"
        case .sandbox: "public-api.sandbox.bunq.com"
        }
    }

    var baseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/v1"
        return components.url ?? URL(fileURLWithPath: "/")
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession without cache, cookies or credential store. Requires TLS 1.2 or later.
public struct HardenedURLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BunqError.invalidResponse }
        return (data, http)
    }
}

/// Reads accounts and payments from the bunq API. The app never makes a payment.
///
/// Flow: installation (key exchange) → device registration → session → GET
/// requests. The client's private key, the installation token and the server
/// public key are kept in the Keychain. The session token only exists in memory.
public actor BunqClient {
    struct Installation: Codable {
        let environment: BunqEnvironment
        let token: String
        let serverPublicKey: String
        var deviceRegistered: Bool
    }

    private struct Session {
        let token: String
        let userID: Int
    }

    private let environment: BunqEnvironment
    private let secrets: any SecretStore
    private let transport: any HTTPTransport
    private let deviceDescription: String
    private let requireServerSignature: Bool
    private let logger = Logger(subsystem: "app.gage", category: "bunq")
    private var session: Session?

    public init(
        environment: BunqEnvironment,
        secrets: any SecretStore,
        transport: any HTTPTransport = HardenedURLSessionTransport(),
        deviceDescription: String = "Gage für macOS",
        requireServerSignature: Bool = true
    ) {
        self.environment = environment
        self.secrets = secrets
        self.transport = transport
        self.deviceDescription = deviceDescription
        self.requireServerSignature = requireServerSignature
    }

    /// Stores the API key and registers this Mac with bunq.
    public func connect(apiKey: String) async throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 256 else { throw BunqError.missingAPIKey }
        try secrets.set(Data(trimmed.utf8), for: .bunqAPIKey)
        try secrets.remove(.bunqInstallation)
        session = nil
        _ = try await ensureSession()
    }

    /// Removes the API key and all keys from the Keychain.
    public func disconnect() throws {
        session = nil
        try secrets.remove(.bunqAPIKey)
        try secrets.remove(.bunqInstallation)
        try secrets.remove(.bunqClientPrivateKey)
    }

    public func accounts() async throws -> [BunqMonetaryAccountSummary] {
        let session = try await ensureSession()
        let envelope = try await send(method: "GET", path: "/user/\(session.userID)/monetary-account", token: session.token)
        return envelope.items.accounts
            .filter { $0.status == "ACTIVE" }
            .map { BunqMonetaryAccountSummary(id: $0.id, iban: $0.iban, description: $0.description) }
    }

    /// Payments booked since `date`, newest first, at most `maxPages` × 200 entries.
    func payments(accountID: Int, since date: LocalDate, maxPages: Int = 20) async throws -> [BunqPayment] {
        let session = try await ensureSession()
        var path = "/user/\(session.userID)/monetary-account/\(accountID)/payment?count=200"
        var collected: [BunqPayment] = []

        for page in 0..<maxPages {
            if page > 0 { try await Task.sleep(for: .milliseconds(1100)) } // bunq allows 3 GET requests per 3 s
            let envelope = try await send(method: "GET", path: path, token: session.token)
            let payments = envelope.items.payments
            collected += payments
            let reachedStart = payments.contains { (BunqMapping.bookingDate(from: $0.created) ?? date) < date }
            guard !reachedStart, let older = envelope.olderURL, let next = Self.relativePath(fromOlderURL: older) else { break }
            path = next
        }
        return collected.filter { (BunqMapping.bookingDate(from: $0.created) ?? date) >= date }
    }

    // MARK: - Session handling

    private func ensureSession() async throws -> Session {
        if let session { return session }
        guard let apiKeyData = try secrets.data(for: .bunqAPIKey),
              let apiKey = String(data: apiKeyData, encoding: .utf8)
        else { throw BunqError.missingAPIKey }

        let keyPair = try loadOrCreateKeyPair()
        var installation = try await loadOrCreateInstallation(keyPair: keyPair)

        if !installation.deviceRegistered {
            let body = try JSONSerialization.data(withJSONObject: ["description": deviceDescription, "secret": apiKey])
            _ = try await send(
                method: "POST",
                path: "/device-server",
                body: body,
                token: installation.token,
                keyPair: keyPair,
                serverKey: installation.serverPublicKey
            )
            installation.deviceRegistered = true
            try secrets.set(JSONEncoder().encode(installation), for: .bunqInstallation)
        }

        let body = try JSONSerialization.data(withJSONObject: ["secret": apiKey])
        let envelope = try await send(
            method: "POST",
            path: "/session-server",
            body: body,
            token: installation.token,
            keyPair: keyPair,
            serverKey: installation.serverPublicKey
        )
        guard let token = envelope.items.token, let userID = envelope.items.userID else {
            throw BunqError.unexpectedPayload("session-server")
        }
        let session = Session(token: token, userID: userID)
        self.session = session
        logger.info("bunq session established")
        return session
    }

    private func loadOrCreateKeyPair() throws -> BunqKeyPair {
        if let stored = try secrets.data(for: .bunqClientPrivateKey) {
            return try BunqKeyPair.restore(from: stored)
        }
        let keyPair = try BunqKeyPair.generate()
        try secrets.set(keyPair.exportPrivateKey(), for: .bunqClientPrivateKey)
        return keyPair
    }

    private func loadOrCreateInstallation(keyPair: BunqKeyPair) async throws -> Installation {
        if let stored = try secrets.data(for: .bunqInstallation),
           let installation = try? JSONDecoder().decode(Installation.self, from: stored),
           installation.environment == environment {
            return installation
        }
        // Trust on first use: the installation response gives us the server key
        // that every later response is checked against.
        let body = try JSONSerialization.data(withJSONObject: ["client_public_key": keyPair.publicKeyPEM()])
        let envelope = try await send(method: "POST", path: "/installation", body: body, verifySignature: false)
        guard let token = envelope.items.token, let serverKey = envelope.items.serverPublicKey else {
            throw BunqError.unexpectedPayload("installation")
        }
        let installation = Installation(environment: environment, token: token, serverPublicKey: serverKey, deviceRegistered: false)
        try secrets.set(JSONEncoder().encode(installation), for: .bunqInstallation)
        return installation
    }

    // MARK: - Transport

    private func send(
        method: String,
        path: String,
        body: Data? = nil,
        token: String? = nil,
        keyPair: BunqKeyPair? = nil,
        serverKey: String? = nil,
        verifySignature: Bool = true
    ) async throws -> BunqEnvelope {
        let request = try makeRequest(method: method, path: path, body: body, token: token, keyPair: keyPair)
        let (data, response) = try await transport.send(request)

        if verifySignature, requireServerSignature {
            let key = try serverKey ?? storedServerKey()
            guard let signature = response.value(forHTTPHeaderField: "X-Bunq-Server-Signature") else {
                throw BunqError.missingServerSignature
            }
            guard BunqKeyPair.verify(signatureBase64: signature, data: data, publicKeyPEM: key) else {
                throw BunqError.invalidServerSignature
            }
        }

        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(BunqErrorEnvelope.self, from: data))?.entries.first?.description
            if response.statusCode == 401 { session = nil }
            logger.error("bunq request failed with status \(response.statusCode, privacy: .public)")
            throw BunqError.api(status: response.statusCode, message: message ?? "Unbekannter Fehler")
        }
        do {
            return try JSONDecoder().decode(BunqEnvelope.self, from: data)
        } catch {
            throw BunqError.unexpectedPayload(path.components(separatedBy: "?")[0])
        }
    }

    private func makeRequest(method: String, path: String, body: Data?, token: String?, keyPair: BunqKeyPair?) throws -> URLRequest {
        guard path.hasPrefix("/"), !path.contains(".."),
              let url = URL(string: environment.baseURL.absoluteString + path),
              url.host() == environment.host, url.scheme == "https"
        else { throw BunqError.untrustedHost(path) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        let headers: [String: String] = [
            "Cache-Control": "no-cache",
            "User-Agent": "Gage/1.0 (macOS)",
            "X-Bunq-Language": "de_DE",
            "X-Bunq-Region": "de_DE",
            "X-Bunq-Geolocation": "0 0 0 0 000",
            "X-Bunq-Client-Request-Id": UUID().uuidString,
            "Content-Type": "application/json",
        ]
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        if let token { request.setValue(token, forHTTPHeaderField: "X-Bunq-Client-Authentication") }
        if let keyPair, let body {
            let signature = try keyPair.sign(body)
            request.setValue(signature, forHTTPHeaderField: "X-Bunq-Client-Signature")
        }
        return request
    }

    private func storedServerKey() throws -> String {
        guard let stored = try secrets.data(for: .bunqInstallation),
              let installation = try? JSONDecoder().decode(Installation.self, from: stored)
        else { throw BunqError.missingServerSignature }
        return installation.serverPublicKey
    }

    /// Turns bunq's `older_url` ("/v1/user/1/…?older_id=5") into a path relative to `/v1`.
    static func relativePath(fromOlderURL olderURL: String) -> String? {
        guard olderURL.hasPrefix("/v1/") else { return nil }
        return String(olderURL.dropFirst(3))
    }
}

public struct BunqMonetaryAccountSummary: Hashable, Sendable, Identifiable {
    public let id: Int
    public let iban: String?
    public let description: String?
}
