# ADR 0001: Clean Architecture mit lokalem Swift Package

- Status: angenommen
- Datum: 2026-11-17

## Kontext

Die App soll langfristig wartbar, gut testbar und sicher sein. Die Fachlogik (UStG, EStG, GoBD) ist der wertvollste und fehleranfälligste Teil.

## Entscheidung

- Native SwiftUI-App für macOS 14+.
- Die gesamte Logik liegt in einem lokalen Swift Package `GageKit` mit fünf Modulen (`Core`, `Security`, `Persistence`, `Integrations`, `UI`).
- `GageCore` kennt nur Foundation und definiert Ports als Protokolle.
- Das Xcode-Projekt wird mit XcodeGen aus `project.yml` erzeugt und nicht eingecheckt.

## Folgen

- Fachlogik ist mit `swift test` ohne UI und ohne Simulator testbar.
- Modulgrenzen verhindern ungewollte Abhängigkeiten, etwa von der UI in die Persistenz.
- Wer mitentwickelt, braucht XcodeGen.
