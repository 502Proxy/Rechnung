import Foundation
import GageCore
@testable import GageIntegrations
import GageSecurity
import Testing

/// Simulates the bunq API, including server signatures.
private actor FakeBunqServer: HTTPTransport {
    let serverKey: BunqKeyPair
    var tamperWithSignatures = false
    private(set) var requests: [URLRequest] = []
    private var clientPublicKeyPEM: String?

    init() throws {
        serverKey = try BunqKeyPair.generate()
    }

    func setTampering(_ value: Bool) { tamperWithSignatures = value }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let path = request.url?.path() ?? ""
        let body = request.httpBody ?? Data()
        let json: String

        switch (request.httpMethod ?? "", path) {
        case ("POST", "/v1/installation"):
            let object = try JSONSerialization.jsonObject(with: body) as? [String: String]
            clientPublicKeyPEM = object?["client_public_key"]
            let pem = try serverKey.publicKeyPEM().replacingOccurrences(of: "\n", with: "\\n")
            json = #"{"Response":[{"Id":{"id":1}},{"Token":{"token":"installation-token"}},{"ServerPublicKey":{"server_public_key":"\#(pem)"}}]}"#
        case ("POST", "/v1/device-server"), ("POST", "/v1/session-server"):
            let secret = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["secret"] as? String
            if secret == "sandbox_rejected" {
                return try respond(#"{"Error":[{"error_description_translated":"Zugangsdaten falsch."}]}"#, status: 400)
            }
            guard let clientKey = clientPublicKeyPEM,
                  let signature = request.value(forHTTPHeaderField: "X-Bunq-Client-Signature"),
                  BunqKeyPair.verify(signatureBase64: signature, data: body, publicKeyPEM: clientKey),
                  request.value(forHTTPHeaderField: "X-Bunq-Client-Authentication") == "installation-token"
            else { return try respond(#"{"Error":[{"error_description_translated":"Signatur ungültig"}]}"#, status: 400) }
            json = path.hasSuffix("device-server")
                ? #"{"Response":[{"Id":{"id":2}}]}"#
                : #"{"Response":[{"Id":{"id":3}},{"Token":{"token":"session-token"}},{"UserPerson":{"id":42}}]}"#
        case ("GET", "/v1/user/42/monetary-account"):
            json = #"""
            {"Response":[
              {"MonetaryAccountBank":{"id":5,"status":"ACTIVE","description":"Main",
                "alias":[{"type":"IBAN","value":"NL91ABNA0417164300","name":"Max"}]}},
              {"MonetaryAccountBank":{"id":7,"status":"ACTIVE","description":"DJ",
                "alias":[{"type":"IBAN","value":"DE89370400440532013000","name":"Max"}]}}
            ]}
            """#
        case ("GET", "/v1/user/42/monetary-account/7/payment"):
            json = #"""
            {"Response":[
              {"Payment":{"id":901,"created":"2026-11-17 09:12:45.123456",
                "amount":{"value":"700.00","currency":"EUR"},"description":"Gage November danke!",
                "counterparty_alias":{"display_name":"Club Kantine GmbH","iban":"DE02120300000000202051"}}},
              {"Payment":{"id":900,"created":"2026-11-12 08:00:00.000000",
                "amount":{"value":"-39.95","currency":"EUR"},"description":"Mobilfunk",
                "counterparty_alias":{"display_name":"Telekom"}}},
              {"Payment":{"id":800,"created":"2026-09-01 08:00:00.000000",
                "amount":{"value":"-10.00","currency":"EUR"},"description":"alt",
                "counterparty_alias":{"display_name":"Alt"}}}
            ]}
            """#
        default:
            return try respond(#"{"Error":[{"error_description_translated":"Nicht gefunden"}]}"#, status: 404)
        }
        return try respond(json, status: 200)
    }

    private func respond(_ json: String, status: Int) throws -> (Data, HTTPURLResponse) {
        let data = Data(json.utf8)
        var signature = try serverKey.sign(data)
        if tamperWithSignatures { signature = try serverKey.sign(Data("anders".utf8)) }
        guard let url = URL(string: "https://public-api.sandbox.bunq.com"),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: status,
                  httpVersion: "HTTP/1.1",
                  headerFields: ["X-Bunq-Server-Signature": signature]
              )
        else { throw BunqError.invalidResponse }
        return (data, response)
    }
}

@Suite("bunq integration")
struct BunqTests {
    @Test("Public keys survive the PKCS#1 ⇄ X.509 conversion")
    func keyEncoding() throws {
        let keyPair = try BunqKeyPair.generate()
        let pem = try keyPair.publicKeyPEM()
        #expect(pem.hasPrefix("-----BEGIN PUBLIC KEY-----\n"))
        let message = Data("Rechnung 2026-015".utf8)
        let signature = try keyPair.sign(message)
        #expect(BunqKeyPair.verify(signatureBase64: signature, data: message, publicKeyPEM: pem))
        #expect(!BunqKeyPair.verify(signatureBase64: signature, data: Data("manipuliert".utf8), publicKeyPEM: pem))

        let restored = try BunqKeyPair.restore(from: keyPair.exportPrivateKey())
        #expect(try restored.publicKeyPEM() == pem)
    }

    @Test("Malformed DER is rejected without crashing")
    func malformedDER() {
        #expect(DER.rsaPublicKey(fromSubjectPublicKeyInfo: Data()) == nil)
        #expect(DER.rsaPublicKey(fromSubjectPublicKeyInfo: Data([0x30, 0x84, 0xFF, 0xFF, 0xFF, 0xFF])) == nil)
        #expect(DER.rsaPublicKey(fromSubjectPublicKeyInfo: Data([0x30, 0x03, 0x02, 0x01, 0x00])) == nil)
    }

    @Test("Full flow: installation, device, session, payments")
    func fullFlow() async throws {
        let server = try FakeBunqServer()
        let secrets = InMemorySecretStore()
        let client = BunqClient(secrets: secrets, transport: server)

        try await client.connect(apiKey: "sandbox_test_placeholder")
        let connection = BunqConnection(client: client)
        let accounts = try await connection.accounts()
        #expect(accounts.map(\.name) == ["Main", "DJ"])

        // Only the selected DJ account is read, never the private main account (id 5).
        let since = try #require(LocalDate(year: 2026, month: 11, day: 1))
        let transactions = try await connection.transactions(since: since, accountIBAN: "DE89 3704 0044 0532 0130 00")
        #expect(transactions.allSatisfy { $0.accountIBAN == "DE89370400440532013000" })

        #expect(transactions.map(\.id) == ["bunq-901", "bunq-900"])
        #expect(transactions.first?.amount == Money(cents: 70000))
        #expect(transactions.first?.counterpartyName == "Club Kantine GmbH")
        #expect(transactions.last?.amount == Money(cents: -3995))

        let requests = await server.requests
        #expect(requests.map { $0.url?.path() ?? "" }.prefix(3) == ["/v1/installation", "/v1/device-server", "/v1/session-server"])
        #expect(requests.allSatisfy { $0.url?.host() == "public-api.sandbox.bunq.com" })
        #expect(!requests.contains { $0.url?.path().contains("/monetary-account/5/") ?? false })
        #expect(requests.dropFirst(3).allSatisfy { $0.value(forHTTPHeaderField: "X-Bunq-Client-Authentication") == "session-token" })

        // Secrets live in the Keychain abstraction; the session token is never stored.
        #expect(try secrets.data(for: .bunqAPIKey) != nil)
        #expect(try secrets.data(for: .bunqClientPrivateKey) != nil)
        let installation = try #require(try secrets.data(for: .bunqInstallation))
        #expect(String(data: installation, encoding: .utf8)?.contains("session-token") == false)
    }

    @Test("Responses with a wrong server signature are discarded")
    func rejectsTamperedResponses() async throws {
        let server = try FakeBunqServer()
        let client = BunqClient(secrets: InMemorySecretStore(), transport: server)
        try await client.connect(apiKey: "sandbox_test_placeholder")
        await server.setTampering(true)
        await #expect(throws: BunqError.invalidServerSignature) { _ = try await client.accounts() }
    }

    @Test("Disconnecting removes every key")
    func disconnect() async throws {
        let secrets = InMemorySecretStore()
        let server = try FakeBunqServer()
        let client = BunqClient(secrets: secrets, transport: server)
        try await client.connect(apiKey: "sandbox_test_placeholder")
        try await client.disconnect()
        for key in [SecretKey.bunqAPIKey, .bunqClientPrivateKey, .bunqInstallation] {
            #expect(try secrets.data(for: key) == nil)
        }
    }

    @Test("The environment follows from the API key")
    func environmentDetection() {
        #expect(BunqClient.environment(forAPIKey: "sandbox_abc") == .sandbox)
        #expect(BunqClient.environment(forAPIKey: "a1b2c3") == .production)
    }

    @Test("A rejected key is not kept and the error names the step")
    func rejectedKey() async throws {
        let secrets = InMemorySecretStore()
        let server = try FakeBunqServer()
        let client = BunqClient(secrets: secrets, transport: server)
        await #expect(throws: BunqError.api(operation: "Gerät registrieren", status: 400, message: "Zugangsdaten falsch.")) {
            try await client.connect(apiKey: "sandbox_rejected")
        }
        #expect(try secrets.data(for: .bunqAPIKey) == nil)
        #expect(await client.connectedEnvironment() == nil)
    }

    @Test("Pagination stays on the bunq host")
    func paginationPaths() {
        let page = BunqPage(olderURL: "/v1/user/1/monetary-account/2/payment?count=200&older_id=5")
        #expect(page?.path == "/user/1/monetary-account/2/payment")
        #expect(page?.query == [URLQueryItem(name: "count", value: "200"), URLQueryItem(name: "older_id", value: "5")])
        #expect(BunqPage(olderURL: "https://evil.example/v1/user") == nil)
        #expect(BunqPage(olderURL: "//evil.example/v1/user") == nil)
    }

    @Test("Booking dates follow the user's time zone")
    func bookingDates() throws {
        let berlin = try #require(TimeZone(identifier: "Europe/Berlin"))
        #expect(BunqMapping.bookingDate(from: "2026-11-16 23:30:00.000000", timeZone: berlin)?.description == "2026-11-17")
        #expect(BunqMapping.bookingDate(from: "2026-11-16 10:00:00.000000", timeZone: berlin)?.description == "2026-11-16")
    }
}
