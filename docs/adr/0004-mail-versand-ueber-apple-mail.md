# ADR 0004: E-Mail-Versand über Apple Mail statt SMTP

- Status: angenommen
- Datum: 2026-11-17

## Kontext

Rechnungen sollen möglichst automatisch verschickt werden. macOS bietet keine API, die E-Mails ohne Zutun des Nutzers versendet. Ein automatischer Versand bräuchte eine eigene SMTP-Implementierung (oder eine Bibliothek) und ein gespeichertes Mail-Passwort.

## Entscheidung

Gage erstellt die E-Mail mit Empfänger, Betreff, Text und PDF-Anhang und öffnet sie über `NSSharingService(.composeEmail)` im Standard-Mailprogramm. Der Nutzer sendet sie mit einem Klick ab. Die Kalender-Automatik erstellt deshalb nur Entwürfe und meldet sich per Mitteilung.

## Folgen

- Kein Mail-Passwort in der App, keine falsch versendeten Rechnungen.
- Gesendete Rechnungen liegen im Postfach unter „Gesendet“.
- Ein Klick pro Rechnung bleibt nötig.
- Ein späterer vollautomatischer Versand wäre über OAuth bei einem Mailanbieter möglich und braucht eine neue ADR.
