# ADR 0002: Verschlüsselter Snapshot statt Datenbank

- Status: angenommen
- Datum: 2026-11-17

## Kontext

Ein Kleinunternehmer erzeugt einige hundert Rechnungen und wenige tausend Buchungen pro Jahr. SwiftData und Core Data verschlüsseln nicht selbst, SQLCipher wäre eine Abhängigkeit von Dritten.

## Entscheidung

Alle Daten (`AppData`) werden als JSON serialisiert, mit AES-256-GCM verschlüsselt und atomar in eine Datei geschrieben. Vor jedem Schreiben wird die vorherige Version als verschlüsseltes Backup rotiert (10 Versionen).

## Folgen

- Einfach, vollständig verschlüsselt, keine Abhängigkeiten.
- Jeder Speichervorgang schreibt die ganze Datei. Bei der erwarteten Datenmenge (< 5 MB) ist das unkritisch.
- `schemaVersion` erlaubt spätere Migrationen. Daten aus neueren Versionen werden nicht überschrieben.
- Wächst die Datenmenge deutlich, wird ein Wechsel auf SQLite mit Seitenverschlüsselung neu bewertet.
