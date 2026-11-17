import Foundation

public enum MailTemplates {
    public static func invoice(_ invoice: Invoice, profile: BusinessProfile) -> (subject: String, body: String) {
        let subject = "Rechnung \(invoice.number)"
        let body = """
        Guten Tag,

        vielen Dank für die Zusammenarbeit. Anbei erhalten Sie meine Rechnung \(invoice.number) \
        über \(invoice.total.formatted()), zahlbar bis zum \(format(invoice.dueDate)).

        Viele Grüße
        \(profile.name)
        """
        return (subject, body)
    }

    public static func reminder(_ invoice: Invoice, profile: BusinessProfile) -> (subject: String, body: String) {
        let subject = "Zahlungserinnerung zu Rechnung \(invoice.number)"
        let body = """
        Guten Tag,

        sicher ist es im Alltag untergegangen: Meine Rechnung \(invoice.number) vom \(format(invoice.issueDate)) \
        über \(invoice.total.formatted()) war am \(format(invoice.dueDate)) fällig. \
        Ich freue mich über einen Ausgleich in den nächsten Tagen.

        Viele Grüße
        \(profile.name)
        """
        return (subject, body)
    }

    public static func format(_ date: LocalDate) -> String {
        String(format: "%02d.%02d.%04d", date.day, date.month, date.year)
    }
}
