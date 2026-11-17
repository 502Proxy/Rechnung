## Worum geht es?

<!-- Was ändert sich und warum? Verweise auf das Issue, z. B. "Closes #12". -->

## Art der Änderung

- [ ] Neue Funktion
- [ ] Fehlerkorrektur
- [ ] Refactoring ohne Verhaltensänderung
- [ ] Dokumentation / CI
- [ ] Stage-Promotion (`develop → qa` oder `qa → main`)

## Prüfung

- [ ] `swift test` läuft lokal durch
- [ ] `swiftlint lint` ohne neue Warnungen
- [ ] Neue oder geänderte Regeln haben Tests
- [ ] UI-Änderungen im Hell- und Dunkelmodus angesehen

## Sicherheit & Datenschutz

- [ ] Keine Secrets, echten Kundendaten oder IBANs im Code, in Tests oder in Logs
- [ ] Keine neuen Berechtigungen (Entitlements) – oder begründet
- [ ] Keine neue Abhängigkeit von Dritten – oder ADR angelegt
