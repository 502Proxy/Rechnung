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

## Merge-Strategie

| Pull Request | Merge-Art | Grund |
| --- | --- | --- |
| `feature/*`, `fix/*` → `develop` | **Squash and merge** | ein sauberer Commit pro Änderung |
| `develop` → `qa`, `qa` → `main` | **Create a merge commit** | die Stage-Branches behalten dieselbe Historie. Ein Squash würde sie auseinanderlaufen lassen |
| `hotfix/*` → `main` | **Create a merge commit**, danach `main` → `develop` | der Fix landet auch in der Entwicklung |

## Einmalige Einrichtung in GitHub

Das Skript `scripts/setup-github-repo.sh` richtet alles ein. Es braucht die GitHub CLI mit Admin-Rechten:

```bash
brew install gh
gh auth login
scripts/setup-github-repo.sh
```

Das Skript lässt sich gefahrlos mehrfach ausführen. Es setzt:

1. **Standard-Branch** `develop`, Squash- und Merge-Commits erlaubt, Rebase-Merge aus, Branches nach dem Merge löschen. Als Commit-Nachricht wird nur der PR-Titel übernommen, nicht die PR-Beschreibung
2. **Ruleset „Stage-Branches“** für `main`, `qa` und `develop`: kein Löschen, kein Force-Push, Änderungen nur per Pull Request, alle Threads erledigt, Pflicht-Checks `SwiftLint`, `Unit tests (GageKit)`, `Build app`, `Secret scan`, `Branch policy` und `Analyze (Swift)`, Branch muss aktuell sein
3. **Environments**: `development` (nur von `develop`), `qa` (nur von `qa`), `production` (nur von Tags `v*`, Freigabe durch dich)
4. **Sicherheit**: Dependabot-Warnungen und -Sicherheitsupdates, Secret Scanning mit Push Protection, Private Vulnerability Reporting

Von Hand bleibt nur noch, sobald ein Apple Developer Account vorhanden ist: unter **Settings → Environments → qa / production** die Secrets anlegen.

- `MACOS_CERTIFICATE_P12_BASE64`: Developer-ID-Application-Zertifikat als Base64 (`base64 -i cert.p12 | pbcopy`)
- `MACOS_CERTIFICATE_PASSWORD`
- `APPLE_TEAM_ID`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`

Ohne diese Secrets bauen die Pipelines unsigniert (ad-hoc signiert). Ein Release wird dann nur als Entwurf angelegt.

## Release erstellen

```bash
git checkout main && git pull
git tag -a v1.0.0 -m "Gage 1.0.0"
git push origin v1.0.0
```
