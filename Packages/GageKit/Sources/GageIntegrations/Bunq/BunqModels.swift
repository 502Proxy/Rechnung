import Foundation

/// bunq wraps every response in `{"Response": [{"<Type>": {...}}, ...]}`.
struct BunqEnvelope: Decodable {
    let items: [BunqItem]
    let olderURL: String?

    private enum CodingKeys: String, CodingKey {
        case response = "Response"
        case pagination = "Pagination"
    }

    private struct Pagination: Decodable {
        let olderURL: String?
        enum CodingKeys: String, CodingKey { case olderURL = "older_url" }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([BunqItem].self, forKey: .response)
        olderURL = try container.decodeIfPresent(Pagination.self, forKey: .pagination)?.olderURL
    }
}

struct BunqErrorEnvelope: Decodable {
    struct Entry: Decodable {
        let description: String
        enum CodingKeys: String, CodingKey { case description = "error_description_translated" }
    }

    let entries: [Entry]
    enum CodingKeys: String, CodingKey { case entries = "Error" }
}

struct BunqAmount: Decodable, Equatable {
    let value: String
    let currency: String
}

struct BunqAlias: Decodable, Equatable {
    let type: String?
    let value: String?
    let iban: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case type, value, iban
        case displayName = "display_name"
    }
}

struct BunqMonetaryAccount: Decodable, Equatable {
    let id: Int
    let status: String
    let description: String?
    let alias: [BunqAlias]

    var iban: String? { alias.first { $0.type == "IBAN" }?.value }
}

struct BunqPayment: Decodable, Equatable {
    let id: Int
    let created: String
    let amount: BunqAmount
    let description: String
    let counterpartyAlias: BunqAlias?

    enum CodingKeys: String, CodingKey {
        case id, created, amount, description
        case counterpartyAlias = "counterparty_alias"
    }
}

enum BunqItem: Decodable, Equatable {
    case id(Int)
    case token(String)
    case serverPublicKey(String)
    case user(id: Int)
    case monetaryAccount(BunqMonetaryAccount)
    case payment(BunqPayment)
    case other(String)

    private struct DynamicKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private struct IDBox: Decodable { let id: Int }
    private struct TokenBox: Decodable { let token: String }
    private struct ServerKeyBox: Decodable {
        let key: String
        enum CodingKeys: String, CodingKey { case key = "server_public_key" }
    }

    private static let userTypes: Set<String> = ["UserPerson", "UserCompany", "UserApiKey", "UserLight"]
    private static let accountTypes: Set<String> = ["MonetaryAccountBank", "MonetaryAccountJoint", "MonetaryAccountSavings"]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        guard let key = container.allKeys.first else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Empty item"))
        }
        switch key.stringValue {
        case "Id": self = try .id(container.decode(IDBox.self, forKey: key).id)
        case "Token": self = try .token(container.decode(TokenBox.self, forKey: key).token)
        case "ServerPublicKey": self = try .serverPublicKey(container.decode(ServerKeyBox.self, forKey: key).key)
        case "Payment": self = try .payment(container.decode(BunqPayment.self, forKey: key))
        case let type where Self.userTypes.contains(type): self = try .user(id: container.decode(IDBox.self, forKey: key).id)
        case let type where Self.accountTypes.contains(type): self = try .monetaryAccount(container.decode(BunqMonetaryAccount.self, forKey: key))
        default: self = .other(key.stringValue)
        }
    }
}

extension [BunqItem] {
    var token: String? {
        for case let .token(value) in self { return value }
        return nil
    }

    var serverPublicKey: String? {
        for case let .serverPublicKey(value) in self { return value }
        return nil
    }

    var userID: Int? {
        for case let .user(id) in self { return id }
        return nil
    }

    var accounts: [BunqMonetaryAccount] {
        var result: [BunqMonetaryAccount] = []
        for case let .monetaryAccount(account) in self { result.append(account) }
        return result
    }

    var payments: [BunqPayment] {
        var result: [BunqPayment] = []
        for case let .payment(payment) in self { result.append(payment) }
        return result
    }
}
