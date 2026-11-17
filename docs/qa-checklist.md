# QA-Checkliste

Für jeden Build aus der Stage `qa` vor dem Merge nach `main`.

## Installation

- [ ] Die App startet auf einem sauberen macOS-14-Benutzerkonto
- [ ] Gatekeeper lässt die App ohne Warnung starten (nur bei signiertem Build)
- [ ] Die App-Sperre erscheint beim Start, Touch ID und Passwort funktionieren

## Rechnungen

- [ ] Kunde anlegen, Rechnung erstellen, Vorschau stimmt mit der PDF überein
- [ ] Die Nummer wird fortlaufend vergeben
- [ ] „Senden“ öffnet Apple Mail mit Empfänger, Betreff und PDF-Anhang
- [ ] Eine versendete Rechnung lässt sich nicht mehr bearbeiten
- [ ] „Im Finder zeigen“ öffnet die schreibgeschützte PDF, „Integrität prüfen“ meldet „unverändert“
- [ ] Ohne Steuernummer im Profil wird das Senden verhindert und der Grund genannt

## Kalender

- [ ] Beim ersten Abruf fragt macOS nach dem Kalenderzugriff
- [ ] Ein vergangener Termin mit „Gage: …“ erzeugt einen Entwurf und eine Mitteilung
- [ ] Ein Termin mit ausgeschalteter Automatik erzeugt keinen Entwurf

## bunq (Sandbox-Konto)

- [ ] Verbinden mit einem Sandbox-API-Schlüssel (`sandbox_…`) klappt
- [ ] Ein falscher Schlüssel zeigt eine verständliche Meldung und wird nicht gespeichert
- [ ] Eine Zahlung mit Rechnungsnummer wird automatisch verbucht
- [ ] Eine Zahlung ohne Nummer erscheint als Vorschlag
- [ ] „Verbindung trennen“ entfernt die Einträge aus dem Schlüsselbund (Schlüsselbundverwaltung prüfen)

## EÜR

- [ ] Einnahmen und Ausgaben stimmen mit einer Kontrollrechnung überein
- [ ] Der CSV-Export öffnet sich in Numbers bzw. Excel mit korrekten Umlauten

## Sicherheit

- [ ] Die Datei `~/Library/Containers/app.gage.mac/Data/Library/Application Support/Gage/gage.store` enthält keinen Klartext (`strings gage.store | head`)
- [ ] Nach Ruhezustand oder Bildschirmsperre ist die App gesperrt
- [ ] Konsole.app zeigt keine Beträge, Namen oder Schlüssel in den Logs von `app.gage`
