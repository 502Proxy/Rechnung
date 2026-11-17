# Gage

Native macOS-App für Rechnungen von Kleinunternehmern (§ 19 UStG): Rechnungen erstellen, sicher archivieren und per Apple Mail versenden. Zahlungseingänge über die bunq-API abgleichen, Rechnungen automatisch aus dem Apple-Kalender vorbereiten und die Einnahmen-Überschuss-Rechnung (EÜR) für das Finanzamt erzeugen.

Alle Daten bleiben lokal auf dem Mac und sind verschlüsselt gespeichert.

## Funktionen

| Bereich | Was Gage macht |
| --- | --- |
| Rechnungen | Fortlaufende Nummern (`JJJJ-NNN`), alle Pflichtangaben nach § 14 UStG, Hinweis nach § 19 UStG, PDF im A4-Format |
| Archiv | Versendete Rechnungen sind gesperrt (GoBD). Die PDF wird schreibgeschützt abgelegt und per SHA-256 auf Veränderungen geprüft |
| Versand | Eine fertige E-Mail mit PDF-Anhang öffnet sich in Apple Mail. Du prüfst sie und sendest sie selbst ab |
| Apple Kalender | Termine im Kalender „Gigs“ mit `Gage: 800` in der Notiz. Am Tag danach um 09:00 Uhr entsteht ein Rechnungsentwurf und du bekommst eine Mitteilung |
| bunq | Nur Lesezugriff auf die Kontoumsätze. Zahlungen mit Rechnungsnummer im Verwendungszweck werden automatisch verbucht, alle anderen als Vorschlag angezeigt |
| EÜR | Einnahmen nach Zahlungseingang (§ 11 EStG), Ausgaben nach Kategorien, Gewinn, CSV-Export |
| § 19 UStG | Warnt, bevor du die Umsatzgrenzen von 25.000 € bzw. 100.000 € erreichst |

Ein klickbarer Entwurf der Oberfläche liegt in [`docs/mockup/index.html`](docs/mockup/index.html).

## Voraussetzungen

- macOS 14 Sonoma oder neuer
- Xcode 16 oder neuer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- optional: [SwiftLint](https://github.com/realm/SwiftLint) (`brew install swiftlint`)

## Loslegen

```bash
git clone https://github.com/502Proxy/Rechnung.git
cd Rechnung
xcodegen generate          # erzeugt Gage.xcodeproj aus project.yml
open Gage.xcodeproj        # Schema „Gage“ starten
```

Die Tests der Fachlogik laufen ohne Xcode-Projekt:

```bash
cd Packages/GageKit
swift test
```

Ob Gage mit der echten bunq-API oder der **bunq-Sandbox** spricht, ergibt sich aus dem API-Schlüssel: Sandbox-Schlüssel beginnen mit `sandbox_`.

## Projektstruktur

```
App/Gage/                 App-Target: Einstiegspunkt, Composition Root, Entitlements
Packages/GageKit/
  Sources/GageCore        Fachlogik (Rechnungen, Abgleich, EÜR) – nur Foundation
  Sources/GageSecurity    Schlüsselbund, AES-GCM, Touch ID, App-Sperre
  Sources/GagePersistence Verschlüsselter Speicher, Rechnungsarchiv
  Sources/GageIntegrations bunq-API, EventKit, Apple Mail
  Sources/GageUI          SwiftUI-Oberfläche
  Tests/                  Swift-Testing-Suiten je Modul
docs/                     Architektur, Sicherheit, Workflow, ADRs, Mockup
.github/                  CI/CD, Vorlagen, Dependabot
```

## Dokumentation

- [Architektur](docs/architecture.md)
- [Sicherheitskonzept](docs/security.md) · [Sicherheitslücken melden](SECURITY.md)
- [Branches, Stages und Pipelines](docs/branching.md)
- [Fachliche Regeln (UStG, EStG, GoBD)](docs/domain.md)
- [QA-Checkliste](docs/qa-checklist.md)
- [Architekturentscheidungen (ADRs)](docs/adr/)
- [Mitarbeiten](CONTRIBUTING.md)

## Hinweis

Gage ersetzt keine Steuerberatung. Die steuerlichen Regeln sind nach bestem Wissen umgesetzt (Stand 2026). Prüfe die EÜR vor der Abgabe.
