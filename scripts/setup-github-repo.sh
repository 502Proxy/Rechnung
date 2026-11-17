#!/usr/bin/env bash
# Richtet die GitHub-Einstellungen für das Branch- und Stage-Modell ein
# (siehe docs/branching.md). Mehrfaches Ausführen ist unbedenklich.
#
# Voraussetzungen: GitHub CLI (`brew install gh`), angemeldet mit `gh auth login`
# als Admin des Repositorys.
#
# Aufruf:  scripts/setup-github-repo.sh [owner/repo]

set -euo pipefail

command -v gh >/dev/null || { echo "GitHub CLI fehlt: brew install gh" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Bitte zuerst anmelden: gh auth login" >&2; exit 1; }

REPO="${1:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
RULESET_NAME="Stage-Branches"
REQUIRED_CHECKS=("SwiftLint" "Unit tests (GageKit)" "Build app" "Secret scan" "Branch policy" "Analyze (Swift)")

step() { printf '\n▶ %s\n' "$1"; }
warn() { printf '  ⚠ %s\n' "$1" >&2; }

echo "Repository: $REPO"

step "Branches main, develop und qa prüfen"
for branch in main develop qa; do
  gh api "repos/$REPO/branches/$branch" --silent || { echo "Branch $branch fehlt." >&2; exit 1; }
  echo "  ✓ $branch"
done

step "Standard-Branch develop, Squash- und Merge-Commits, Branches nach Merge löschen"
gh api -X PATCH "repos/$REPO" --silent \
  -f default_branch=develop \
  -F allow_squash_merge=true \
  -F allow_merge_commit=true \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  -F allow_auto_merge=true \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY \
  -f merge_commit_title=PR_TITLE \
  -f merge_commit_message=PR_BODY
echo "  ✓ erledigt"

step "Ruleset „$RULESET_NAME“ für main, qa, develop"
checks_json=$(printf '{"context":"%s"},' "${REQUIRED_CHECKS[@]}")
ruleset=$(cat <<JSON
{
  "name": "$RULESET_NAME",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": { "include": ["refs/heads/main", "refs/heads/qa", "refs/heads/develop"], "exclude": [] }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [${checks_json%,}]
      }
    }
  ]
}
JSON
)
existing_id=$(gh api "repos/$REPO/rulesets" -q ".[] | select(.name == \"$RULESET_NAME\") | .id" || true)
if [[ -n "$existing_id" ]]; then
  echo "$ruleset" | gh api -X PUT "repos/$REPO/rulesets/$existing_id" --input - --silent
  echo "  ✓ aktualisiert (ID $existing_id)"
else
  echo "$ruleset" | gh api -X POST "repos/$REPO/rulesets" --input - --silent
  echo "  ✓ angelegt"
fi

step "Environments development, qa, production"
my_id=$(gh api user -q .id)

create_environment() {
  local name="$1" reviewers="$2"
  local body='{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}'
  if [[ "$reviewers" == "yes" ]]; then
    body+=",\"reviewers\":[{\"type\":\"User\",\"id\":$my_id}],\"prevent_self_review\":false"
  fi
  body+='}'
  echo "$body" | gh api -X PUT "repos/$REPO/environments/$name" --input - --silent
}

allow_ref() {
  local environment="$1" pattern="$2" type="$3"
  local existing
  existing=$(gh api "repos/$REPO/environments/$environment/deployment-branch-policies" \
    -q ".branch_policies[] | select(.name == \"$pattern\") | .id" || true)
  [[ -n "$existing" ]] && return 0
  gh api -X POST "repos/$REPO/environments/$environment/deployment-branch-policies" \
    -f name="$pattern" -f type="$type" --silent
}

{ create_environment development no && allow_ref development develop branch && echo "  ✓ development (nur develop)"; } \
  || warn "Environment development konnte nicht eingerichtet werden"
{ create_environment qa no && allow_ref qa qa branch && echo "  ✓ qa (nur qa)"; } \
  || warn "Environment qa konnte nicht eingerichtet werden"
{ create_environment production yes && allow_ref production 'v*' tag && echo "  ✓ production (nur Tags v*, Freigabe durch dich)"; } \
  || warn "Environment production konnte nicht eingerichtet werden"

step "Sicherheitsfunktionen"
gh api -X PUT "repos/$REPO/vulnerability-alerts" --silent && echo "  ✓ Dependabot-Warnungen" || warn "Dependabot-Warnungen nicht aktiviert"
gh api -X PUT "repos/$REPO/automated-security-fixes" --silent && echo "  ✓ Dependabot-Sicherheitsupdates" || warn "Dependabot-Sicherheitsupdates nicht aktiviert"
gh api -X PUT "repos/$REPO/private-vulnerability-reporting" --silent && echo "  ✓ Private Vulnerability Reporting" || warn "Private Vulnerability Reporting nicht aktiviert"
echo '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}' \
  | gh api -X PATCH "repos/$REPO" --input - --silent \
  && echo "  ✓ Secret Scanning mit Push Protection" || warn "Secret Scanning nicht aktiviert"

cat <<'DONE'

Fertig. Ab jetzt:
  • Änderungen nur noch per Pull Request in develop, qa und main
  • Merge erst, wenn alle Pflicht-Checks grün sind
  • Feature → develop: „Squash and merge“
  • develop → qa und qa → main: „Create a merge commit“
  • Release-Builds (Environment production) laufen nur nach deiner Freigabe

Signatur-Secrets für qa/production später unter Settings → Environments hinterlegen
(siehe docs/branching.md, Abschnitt „Einmalige Einrichtung“).
DONE
