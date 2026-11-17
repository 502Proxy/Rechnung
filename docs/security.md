# Sicherheitskonzept

Gage verarbeitet Finanz- und Kundendaten. Deshalb gilt: so wenig Zugriff wie möglich, alles lokal und verschlüsselt, jede Änderung nachvollziehbar.

## Bedrohungsmodell

| Bedrohung | Schutzmaßnahme |
| --- | --- |
| Jemand nutzt den entsperrten Mac | App-Sperre mit Touch ID oder Login-Passwort beim Start, nach Inaktivität (einstellbar, mindestens 1 Minute), bei Ruhezustand, Bildschirmsperre und Benutzerwechsel |
| Datenträger oder Backup gelangt in fremde Hände | Datenbank mit AES-256-GCM verschlüsselt. Der Schlüssel liegt im Schlüsselbund (`WhenUnlockedThisDeviceOnly`, keine iCloud-Synchronisierung) |
| Andere Programme lesen die Daten | App Sandbox: Daten liegen im eigenen Container. Dateirechte `0600`, Ordner `0700` |
| Manipulation der Datenbank | Die GCM-Authentifizierung erkennt jede Änderung. Ein verkettetes SHA-256-Änderungsprotokoll macht nachträgliche Eingriffe sichtbar |
| Manipulation versendeter Rechnungen | Rechnungen sind nach dem Versand gesperrt. Die PDF ist schreibgeschützt und mit dem Finder-Schloss versehen, ihr SHA-256 wird mit der Rechnung gespeichert („Integrität prüfen“) |
| Abhören oder Manipulation der bunq-Verbindung | TLS ≥ 1.2, ephemere URLSession ohne Cache und Cookies. Anfragen werden mit RSA-SHA256 signiert, jede Antwort mit dem Server-Schlüssel geprüft. Nur die bunq-Hosts sind erlaubt |
| Private Kontodaten in der App | Gage liest nur das eine Konto, das du als Geschäftskonto auswählst. Buchungen anderer Konten werden weder abgerufen noch gespeichert. Beim Kontowechsel werden sie entfernt |
| Diebstahl des bunq-Zugangs | API-Schlüssel und privater RSA-Schlüssel liegen nur im Schlüsselbund, das Session-Token nur im Arbeitsspeicher. Gage stellt ausschließlich lesende Anfragen |
| Falsche Zuordnung von Zahlungen | Automatisch verbucht wird nur bei eindeutiger Rechnungsnummer **und** exaktem Betrag. Alles andere ist ein Vorschlag, den du bestätigst |
| Ungewollter E-Mail-Versand | Gage speichert kein Mail-Passwort und sendet nie selbst. Du prüfst jede E-Mail in Apple Mail ([ADR 0004](adr/0004-mail-versand-ueber-apple-mail.md)) |
| Header-Injection in E-Mails | `EmailAddress` lässt keine Zeilenumbrüche oder Sonderzeichen zu |
| Daten in Logs | Nur `os.Logger`, persönliche Werte mit `privacy: .private`, `print()` ist per Lint-Regel verboten |
| Lieferkette | Keine Abhängigkeiten von Dritten. GitHub Actions sind per Commit-SHA gepinnt, Dependabot hält sie aktuell |
| Secrets im Repository | `.gitignore` für Zertifikate und Schlüssel, gitleaks-Scan in jeder Pipeline |

## Berechtigungen (Entitlements)

| Entitlement | Zweck |
| --- | --- |
| `app-sandbox` | Grundschutz |
| `network.client` | ausgehende Verbindungen zur bunq-API |
| `personal-information.calendars` | Gig-Kalender lesen |
| `files.user-selected.read-write` | CSV-Export an einen selbst gewählten Ort |

Hardened Runtime ist aktiv. Release-Builds werden mit Developer ID signiert und von Apple notarisiert.

## Schlüsselverwaltung

| Schlüssel | Ort | Lebensdauer |
| --- | --- | --- |
| Datenbank-Schlüssel (256 Bit) | Schlüsselbund | wird beim ersten Start erzeugt |
| bunq-API-Schlüssel | Schlüsselbund | bis „Verbindung trennen“ |
| RSA-2048-Client-Schlüssel (bunq) | Schlüsselbund | bis „Verbindung trennen“ |
| bunq-Installationstoken und Server-Schlüssel | Schlüsselbund | bis „Verbindung trennen“ |
| bunq-Session-Token | Arbeitsspeicher | bis zum Beenden der App |

## Bekannte Grenzen

- Der bunq-Server-Schlüssel wird bei der ersten Verbindung übernommen (Trust on First Use). Die Transportverbindung ist dabei TLS-geschützt.
- Wer bei entsperrtem Mac das Login-Passwort kennt, kann die App entsperren. Das ist gewollt, weil Gage kein eigenes Passwort verwaltet.
- Gegen Schadsoftware mit Root-Rechten auf dem Mac kann keine App schützen.

## Geplante Erweiterungen

- Fenster bei gesperrter App aus Bildschirmaufnahmen ausblenden (`NSWindow.sharingType`)
- Archiv optional in einem selbst gewählten Ordner (Security-Scoped Bookmark)
- Verschlüsselter Export und Import für den Umzug auf einen neuen Mac
