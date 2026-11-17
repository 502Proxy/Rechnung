import EventKit
import Foundation
import GageCore

public enum CalendarAccessError: Error, Equatable, Sendable, LocalizedError {
    case denied
    case calendarNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .denied:
            "Gage hat keinen Zugriff auf deine Kalender. Erlaube ihn unter Systemeinstellungen › Datenschutz & Sicherheit › Kalender."
        case let .calendarNotFound(title):
            "Der Kalender „\(title)“ wurde nicht gefunden."
        }
    }
}

/// Reads gigs from a single Apple Calendar calendar.
///
/// Gage only reads. It never creates or changes events, and only events in
/// the calendar the user chose are evaluated.
public actor EventKitGigSource: GigSource {
    private let store = EKEventStore()

    public init() {}

    public func gigs(in interval: DateInterval, calendarTitle: String) async throws -> [Gig] {
        try await requestAccessIfNeeded()
        let calendars = store.calendars(for: .event).filter { $0.title == calendarTitle }
        guard !calendars.isEmpty else { throw CalendarAccessError.calendarNotFound(calendarTitle) }

        let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
        return store.events(matching: predicate)
            .map { event in
                let parsed = GigNoteParser.parse(event.notes)
                return Gig(
                    id: event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Gig",
                    start: event.startDate,
                    location: event.location,
                    fee: parsed.fee,
                    customerName: parsed.customerName
                )
            }
            .sorted { $0.start < $1.start }
    }

    public func calendarTitles() async throws -> [String] {
        try await requestAccessIfNeeded()
        return Array(Set(store.calendars(for: .event).map(\.title))).sorted()
    }

    private func requestAccessIfNeeded() async throws {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return
        case .notDetermined:
            guard try await store.requestFullAccessToEvents() else { throw CalendarAccessError.denied }
        default:
            throw CalendarAccessError.denied
        }
    }
}
