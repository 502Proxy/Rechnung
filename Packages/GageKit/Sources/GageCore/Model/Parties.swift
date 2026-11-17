import Foundation

public struct Customer: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var name: String
    public var contactPerson: String?
    public var address: PostalAddress
    public var email: EmailAddress?
    /// Other names this customer goes by in calendar notes ("Kantine" for "Club Kantine GmbH").
    public var aliases: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        contactPerson: String? = nil,
        address: PostalAddress,
        email: EmailAddress?,
        aliases: [String] = []
    ) {
        self.id = id
        self.name = name
        self.contactPerson = contactPerson
        self.address = address
        self.email = email
        self.aliases = aliases
    }
}

/// The seller's details. These are the mandatory § 14 UStG fields on every invoice.
public struct BusinessProfile: Hashable, Sendable {
    public var name: String
    /// Artist or project name shown prominently on the invoice, e.g. "Prysma/Takttornado".
    public var artistName: String
    /// Logo as PNG, re-encoded on import so no foreign metadata is kept.
    public var logoPNG: Data?
    public var tradeDescription: String
    public var address: PostalAddress
    public var taxNumber: String
    public var taxOffice: String
    public var iban: IBAN?
    public var bic: String
    public var bankName: String
    public var email: EmailAddress?
    public var phone: String

    public init(
        name: String,
        tradeDescription: String,
        address: PostalAddress,
        taxNumber: String,
        taxOffice: String,
        iban: IBAN?,
        bic: String,
        bankName: String,
        email: EmailAddress?,
        phone: String,
        artistName: String = "",
        logoPNG: Data? = nil
    ) {
        self.name = name
        self.artistName = artistName
        self.logoPNG = logoPNG
        self.tradeDescription = tradeDescription
        self.address = address
        self.taxNumber = taxNumber
        self.taxOffice = taxOffice
        self.iban = iban
        self.bic = bic
        self.bankName = bankName
        self.email = email
        self.phone = phone
    }

    public static let empty = BusinessProfile(
        name: "",
        tradeDescription: "",
        address: PostalAddress(street: "", postalCode: "", city: ""),
        taxNumber: "",
        taxOffice: "",
        iban: nil,
        bic: "",
        bankName: "bunq",
        email: nil,
        phone: ""
    )

    /// Missing fields that keep an invoice from being legally complete.
    public var missingMandatoryFields: [String] {
        var missing: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("Name") }
        if !address.isComplete { missing.append("Anschrift") }
        if taxNumber.trimmingCharacters(in: .whitespaces).isEmpty { missing.append("Steuernummer") }
        return missing
    }
}

extension BusinessProfile: Codable {
    private enum CodingKeys: String, CodingKey {
        case name, artistName, logoPNG, tradeDescription, address, taxNumber, taxOffice
        case iban, bic, bankName, email, phone
    }

    /// Fields added in later versions are optional when decoding, so older stores stay readable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        artistName = try container.decodeIfPresent(String.self, forKey: .artistName) ?? ""
        logoPNG = try container.decodeIfPresent(Data.self, forKey: .logoPNG)
        tradeDescription = try container.decode(String.self, forKey: .tradeDescription)
        address = try container.decode(PostalAddress.self, forKey: .address)
        taxNumber = try container.decode(String.self, forKey: .taxNumber)
        taxOffice = try container.decode(String.self, forKey: .taxOffice)
        iban = try container.decodeIfPresent(IBAN.self, forKey: .iban)
        bic = try container.decode(String.self, forKey: .bic)
        bankName = try container.decode(String.self, forKey: .bankName)
        email = try container.decodeIfPresent(EmailAddress.self, forKey: .email)
        phone = try container.decode(String.self, forKey: .phone)
    }
}
