# Branches, Stages und Pipelines

## Branch-Modell

```mermaid
gitGraph
    commit id: "init"
    branch develop
    checkout develop
    branch feature/rechnung-storno
    commit id: "feat"
    checkout develop
    merge feature/rechnung-storno
    branch qa
    checkout qa
    merge develop id: "QA-Build"
    checkout main
    merge qa id: "v1.0.0" tag: "v1.0.0"
```

| Branch | Stage | Wer merged | Pipeline |
| --- | --- | --- | --- |
| `feature/*`, `fix/*` | – | – | CI bei jedem PR |
| `develop` | **Development** | PR aus Feature-Branches | CI + `dev.yml`: Debug-Build als Artefakt (7 Tage) |
| `qa` | **QA** | PR `develop → qa` | CI + `qa.yml`: Tests im Release-Modus, Release-Build (signiert, falls Zertifikat vorhanden), Artefakt (30 Tage) |
| `main` | **Production** | PR `qa → main` | CI; ein Tag `vX.Y.Z` startet `release.yml`: signiert, notarisiert, GitHub Release |
| `hotfix/*` | – | PR direkt nach `main`, danach zurück nach `develop` | CI |

Die Promotion-Reihenfolge prüft der Job **Branch policy** in `ci.yml` automatisch.

## Pipelines

| Workflow | Auslöser | Inhalt |
| --- | --- | --- |
| `ci.yml` | PR und Push auf `develop`, `qa`, `main` | Branch-Policy, SwiftLint, Unit-Tests mit Abdeckung, App-Build, gitleaks |
| `codeql.yml` | PR, Push, wöchentlich | Statische Sicherheitsanalyse (`security-extended`) |
| `dev.yml` | Push auf `develop` | Development-Build |
| `qa.yml` | Push auf `qa` | QA-Build mit Checkliste |
| `release.yml` | Tag `v*.*.*` auf `main` | Produktions-Release |
| `build-macos.yml` | wird von den Stages aufgerufen | gemeinsamer Build: Signieren und Notarisieren, wenn Secrets vorhanden |

## Einmalige Einrichtung in GitHub

Diese Einstellungen lassen sich nicht über Dateien im Repository setzen. Bitte unter **Settings** einrichten:

1. **General → Default branch:** `develop`
2. **General → Pull Requests:** nur „Allow squash merging“, „Automatically delete head branches“ aktivieren
3. **Rules → Rulesets → New branch ruleset** für `main`, `qa`, `develop`:
   - Restrict deletions, Block force pushes
   - Require a pull request before merging (für `main` und `qa`: 1 Approval; bei Solo-Entwicklung 0)
   - Require status checks to pass: `SwiftLint`, `Unit tests (GageKit)`, `Build app`, `Secret scan`, `Branch policy`, `Analyze (Swift)`
   - Require branches to be up to date before merging
4. **Environments:** `development`, `qa`, `production` anlegen. Für `production` „Required reviewers“ setzen und das Deployment auf Tags `v*` beschränken.
5. **Secrets** (nur im Environment `qa` und `production`), sobald ein Apple Developer Account vorhanden ist:
   - `MACOS_CERTIFICATE_P12_BASE64` – Developer-ID-Application-Zertifikat als Base64
   - `MACOS_CERTIFICATE_PASSWORD`
   - `APPLE_TEAM_ID`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`
6. **Code security:** Dependabot alerts, Secret scanning, Push protection und Private vulnerability reporting aktivieren.

Ohne Signatur-Secrets bauen die Pipelines unsigniert (ad-hoc signiert). Ein Release wird dann nur als Entwurf angelegt.

## Release erstellen

```bash
git checkout main && git pull
git tag -a v1.0.0 -m "Gage 1.0.0"
git push origin v1.0.0
```
