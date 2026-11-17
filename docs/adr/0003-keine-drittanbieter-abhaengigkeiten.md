# ADR 0003: Keine Laufzeit-Abhängigkeiten von Dritten

- Status: angenommen
- Datum: 2026-11-17

## Kontext

Jede Bibliothek ist ein mögliches Einfallstor (Supply-Chain-Angriffe) und muss gepflegt werden.

## Entscheidung

Zur Laufzeit nutzt Gage nur Apple-Frameworks (SwiftUI, CryptoKit, Security, LocalAuthentication, EventKit, Charts, AppKit). Entwicklungswerkzeuge (XcodeGen, SwiftLint) sind erlaubt, weil sie nicht in die App gelangen. Eine neue Laufzeit-Abhängigkeit braucht eine eigene ADR.

## Folgen

- Kleine Angriffsfläche, keine Lizenzfragen.
- Etwas mehr eigener Code, z. B. die minimale DER-Verarbeitung für bunq-Schlüssel.
