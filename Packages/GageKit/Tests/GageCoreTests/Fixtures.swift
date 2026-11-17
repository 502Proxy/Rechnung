import CryptoKit
import Foundation
@testable import GageCore

struct TestDigest: DigestProviding {
    func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum Fixtures {
    static func date(_ iso: String) -> LocalDate {
        guard let date = LocalDate(isoString: iso) else { fatalError("Invalid fixture date \(iso)") }
        return date
    }

    static let berlin = TimeZone(identifier: "Europe/Berlin") ?? .gmt

    static func instant(_ iso: String, hour: Int, minute: Int = 0) -> Date {
        guard let value = date(iso).date(hour: hour, minute: minute, in: berlin) else { fatalError("Invalid instant") }
        return value
    }

    static let kantine = Customer(
        name: "Club Kantine",
        address: PostalAddress(street: "Hafenstraße 8", postalCode: "20359", city: "Hamburg"),
        email: EmailAddress("booking@club-kantine.example"),
        aliases: ["Kantine"]
    )

    static let nordlicht = Customer(
        name: "Nordlicht Events GmbH",
        contactPerson: "z. Hd. Frau Kessler",
        address: PostalAddress(street: "Am Sandtorkai 12", postalCode: "20457", city: "Hamburg"),
        email: EmailAddress("rechnung@nordlicht-events.example")
    )

    static let profile = BusinessProfile(
        name: "Max Beispiel",
        tradeDescription: "DJ & Live-Musik",
        address: PostalAddress(street: "Lindenallee 14", postalCode: "20259", city: "Hamburg"),
        taxNumber: "43/123/45678",
        taxOffice: "Finanzamt Hamburg-Nord",
        iban: IBAN("DE89370400440532013000"),
        bic: "NTSBDEB1XXX",
        bankName: "bunq",
        email: EmailAddress("buchung@max-beispiel.example"),
        phone: "0170 1234567"
    )

    static func draft(
        customer: Customer = kantine,
        issued: String = "2026-11-02",
        service: String = "2026-10-31",
        amount: Int64 = 70000
    ) -> InvoiceDraft {
        InvoiceDraft(
            customerID: customer.id,
            issueDate: date(issued),
            serviceDate: date(service),
            lineItems: [LineItem(description: "DJ-Set Clubnacht", unitPrice: Money(cents: amount))]
        )
    }

    static func appData() -> AppData {
        AppData(profile: profile, customers: [kantine, nordlicht])
    }
}
