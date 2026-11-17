# ADR 0005: Strikte Concurrency jetzt, Swift-6-Sprachmodus später

- Status: angenommen
- Datum: 2026-11-17

## Kontext

Der Swift-6-Sprachmodus macht Datenrennen zu Compilerfehlern. Einige Apple-Frameworks (EventKit, Security) sind noch nicht vollständig als `Sendable` annotiert.

## Entscheidung

Package und App bauen im Swift-5-Sprachmodus mit `StrictConcurrency` bzw. `SWIFT_STRICT_CONCURRENCY = complete`. Gemeinsamer Zustand liegt in `actor`s oder auf dem `@MainActor`.

## Folgen

- Concurrency-Probleme erscheinen schon jetzt als Warnungen.
- Sobald die CI ohne Concurrency-Warnungen baut, wird `swiftLanguageModes: [.v6]` gesetzt.
