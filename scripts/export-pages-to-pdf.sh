#!/usr/bin/env bash
# Exportiert alle Pages-Dokumente eines Ordners als PDF, damit Gage sie importieren kann.
# Pages muss installiert sein. Beim ersten Lauf fragt macOS, ob das Terminal Pages steuern darf.
#
# Aufruf:  scripts/export-pages-to-pdf.sh ~/Documents/Rechnungen
#
# Bereits vorhandene PDFs werden nicht überschrieben. Dateien mit "Vorlage" im Namen werden übersprungen.

set -euo pipefail

folder="${1:?Bitte den Ordner mit den Pages-Dateien angeben.}"
[[ -d "$folder" ]] || { echo "Ordner nicht gefunden: $folder" >&2; exit 1; }

exported=0
skipped=0
shopt -s nullglob nocaseglob
for source in "$folder"/*.pages; do
  name="$(basename "$source")"
  target="${source%.*}.pdf"
  if [[ "$name" == *[Vv]orlage* ]]; then
    echo "  – übersprungen (Vorlage): $name"
    skipped=$((skipped + 1))
    continue
  fi
  if [[ -e "$target" ]]; then
    echo "  – übersprungen (PDF existiert): $name"
    skipped=$((skipped + 1))
    continue
  fi
  osascript - "$source" "$target" <<'APPLESCRIPT'
on run {sourcePath, targetPath}
  tell application "Pages"
    set theDocument to open (POSIX file sourcePath)
    export theDocument to (POSIX file targetPath) as PDF
    close theDocument saving no
  end tell
end run
APPLESCRIPT
  echo "  ✓ $name"
  exported=$((exported + 1))
done

echo
echo "$exported exportiert, $skipped übersprungen. Die PDFs liegen im selben Ordner."
