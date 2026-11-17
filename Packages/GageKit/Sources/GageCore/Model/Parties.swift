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
public struct BusinessProfile: Hashable, Sendable, Codable {
    public var name: String
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
        phone: String
    ) {
        self.name = name
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
