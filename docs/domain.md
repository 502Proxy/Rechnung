# Fachliche Regeln

## Rechnungen (§ 14 UStG)

Jede Rechnung enthält:

- Name und Anschrift von dir und vom Kunden
- Steuernummer und Finanzamt
- Rechnungsdatum und eine einmalig vergebene Rechnungsnummer
- Leistungsdatum
- Art und Umfang der Leistung, Entgelt
- den Hinweis „Gemäß § 19 UStG wird keine Umsatzsteuer berechnet“

Ohne Name, Anschrift und Steuernummer im Profil lässt sich keine Rechnung versenden.

## Rechnungsnummern

§ 14 Abs. 4 Nr. 4 UStG verlangt eine einmalige Nummer, keine lückenlose Folge. Gage bietet zwei Schemata (Einstellungen › Rechnungen & Kalender):

| Schema | Beispiel | Regel |
| --- | --- | --- |
| Rechnungsdatum (Standard) | `101126`, `101126_2` | `TTMMJJ` des Rechnungsdatums, weitere Rechnungen am selben Tag mit `_2`, `_3` … |
| Jahr und laufende Nummer | `2026-001` | je Jahr hochgezählt |

Bei einem Entwurf folgt die datumsbasierte Nummer dem Rechnungsdatum. Nach dem Versand ist sie fest. Importierte Rechnungen behalten ihre ursprüngliche Nummer und werden bei der Vergabe neuer Nummern berücksichtigt.

Erlaubt sind Buchstaben, Ziffern, `-`, `_` und `.`. Pfadtrenner und `..` sind verboten, weil die Nummer im Dateinamen des Archivs steht.

## Import früherer Rechnungen

- Rechnungen › „Alte Rechnungen importieren“: PDFs auswählen oder hineinziehen.
- Gage liest Nummer, Rechnungsdatum, Leistungsdatum, Beschreibung, Stunden × Satz, Summe und Empfänger. Jede Rechnung wird vor der Übernahme geprüft.
- Unbekannte Empfänger werden als Kunde angelegt. Der Spielort aus dem Dateinamen (`Rg_101126_Umbaubar.pdf`) wird als weiterer Name des Kunden gespeichert.
- Die Original-PDF wird unverändert, schreibgeschützt und mit SHA-256 archiviert. Die Rechnung ist danach gesperrt.
- Pages-Dateien zuerst als PDF exportieren: `scripts/export-pages-to-pdf.sh <Ordner>`.

## Unveränderbarkeit (GoBD)

- Entwürfe sind frei änderbar.
- Mit „Senden“ wird die PDF archiviert und die Rechnung gesperrt. Danach ändert sich nur noch der Zahlungsstatus.
- Korrekturen laufen über eine Stornorechnung (geplant). Die ursprüngliche Rechnung bleibt erhalten.
- Jede fachliche Änderung erzeugt einen Eintrag im verketteten Änderungsprotokoll.

## Kleinunternehmerregelung (§ 19 UStG, Fassung ab 2025)

| Bedingung | Folge in Gage |
| --- | --- |
| Umsatz Vorjahr > 25.000 € | Hinweis: Regelung gilt im laufenden Jahr nicht |
| Umsatz laufendes Jahr ≥ 90 % von 25.000 € | Warnung |
| Umsatz laufendes Jahr > 25.000 € | Hinweis: Regelung gilt im Folgejahr nicht |
| Umsatz laufendes Jahr > 100.000 € | Dringende Warnung: Umsatzsteuer ab sofort |

Als Umsatz zählt die Summe der versendeten Rechnungen nach Rechnungsdatum. Das ist eine vorsichtige Schätzung. Die verbindliche Berechnung erfolgt nach § 19 Abs. 2 UStG.

## Einnahmen-Überschuss-Rechnung (§ 4 Abs. 3 EStG)

- **Einnahmen** zählen am Tag des Zahlungseingangs (Zuflussprinzip, § 11 EStG), nicht am Rechnungsdatum.
- **Ausgaben** sind Buchungen mit einer Ausgabenkategorie. Als „Privat“ markierte Buchungen zählen nicht.
- Nicht zugeordnete Buchungen fehlen in der Aufstellung. Gage weist darauf hin.
- Nicht automatisch berücksichtigt werden:
  - die Zehn-Tage-Regel für regelmäßig wiederkehrende Zahlungen zum Jahreswechsel (§ 11 Abs. 1 Satz 2 EStG)
  - Abschreibungen über mehrere Jahre (AfA) für Anschaffungen über 800 € netto
  - Fahrtkosten-Pauschalen und andere Pauschbeträge

## Zahlungsabgleich

| Fall | Ergebnis |
| --- | --- |
| Rechnungsnummer im Verwendungszweck **und** Betrag exakt gleich | automatisch verbucht |
| Rechnungsnummer gefunden, Betrag abweichend | Vorschlag |
| Betrag gleich und Zahler ähnelt dem Kunden | Vorschlag |
| Betrag passt genau zu einer offenen Rechnung | Vorschlag |
| sonst | manuell zuordnen |

Rechnungsnummern werden in den Formen `2026-015`, `2026015`, `2026/015` und `2026 015` erkannt, aber nicht als Teil einer längeren Zahl.

## Rechnungen aus dem Kalender

- Kalender: standardmäßig „Gigs“ (einstellbar)
- Notiz im Termin: `Gage: 1.400 €` und optional `Kunde: Nordlicht Events GmbH`
- Zeitpunkt: Tag nach dem Gig, 09:00 Uhr (einstellbar)
- Ist der Kunde nicht eindeutig zu erkennen, entsteht kein Entwurf. Die Übersicht zeigt stattdessen eine Aufgabe.
- Für jeden Termin entsteht höchstens eine Rechnung.
