# Mitarbeiten

## Ablauf

1. Issue anlegen oder ein vorhandenes auswählen.
2. Branch von `develop` abzweigen:
   - `feature/<kurzbeschreibung>` für neue Funktionen
   - `fix/<kurzbeschreibung>` für Fehlerkorrekturen
   - `chore/…`, `docs/…`, `refactor/…` für alles andere
   - `hotfix/<kurzbeschreibung>` nur für dringende Fehler in Produktion, abgezweigt von `main`
3. Kleine, in sich geschlossene Commits nach [Conventional Commits](https://www.conventionalcommits.org/de/):
   `feat(invoices): add cancellation invoice`, `fix(bunq): retry on 429`, `docs: …`
4. Pull Request nach `develop` öffnen und die Vorlage ausfüllen. Die CI muss grün sein.
5. Merge per **Squash and merge**, danach den Branch löschen.

Der Weg in die Produktion ist in [docs/branching.md](docs/branching.md) beschrieben.

## Regeln für den Code

- Fachlogik gehört nach `GageCore` und hängt von keinem Framework außer Foundation ab.
- Jede neue Regel bekommt einen Test (Swift Testing, `@Test`).
- Geldbeträge immer als `Money` (ganze Cent), Kalendertage als `LocalDate`, nie als `Double` oder `Date`.
- Kein `print()`. Für Logs `os.Logger` verwenden, persönliche Daten mit `privacy: .private`.
- Keine Secrets im Code, in Logs oder in Tests mit echten Werten.
- Neue Abhängigkeiten von Dritten nur mit einer ADR (siehe [docs/adr](docs/adr/)).
- `swiftlint lint` und `swift test` müssen lokal durchlaufen.

## Commits

- Englische Commit-Betreffzeile im Imperativ, höchstens 72 Zeichen.
- Im Text beschreiben, *warum* die Änderung nötig ist.
- Keine generierten Signatur- oder Werbezeilen in Commit-Nachrichten.
