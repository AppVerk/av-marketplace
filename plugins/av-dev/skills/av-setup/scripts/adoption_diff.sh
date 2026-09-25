#!/usr/bin/env bash
# adoption_diff.sh - detektor utraty wiedzy przy adopcji setupu AI.
#
# Wyciaga tokeny w backtickach (3-120 znakow) ze starych plikow (agenci,
# komendy, pipeline) i sprawdza, czy kazdy wystepuje doslownie w nowym
# korpusie (CLAUDE.md, docs, nakladki, skille rol). Token bez sladu to
# kandydat do sekcji "Wiedza, ktora ginie" albo do poprawy nakladek.
#
# Stary plik usuniety z drzewa czyta z git show <rev>:<plik> (--old-rev).
# Filtr orkiestracji: tokeny z RUN_ID, CHECK_ID, EVIDENCE, $ARGUMENTS,
# .claude/agents, .claude/commands, pipeline_state, pipeline_check oraz
# pasujace do --noise REGEX (ERE, np. nazwy starych agentow i komend).
# Korpus pomija katalogi workspace/ i sessions/ oraz same stare pliki.
#
# Wynik:
#   LOST <stary-plik> <token>          token bez sladu w nowym korpusie
#   TOKENS n LOST m FILTERED f         podsumowanie (unikalne tokeny)
#
# Uzycie:
#   adoption_diff.sh [--root DIR] --old <plik>... --new <plik|katalog>... [--noise REGEX]
#   adoption_diff.sh [--root DIR] --old-rev REV --deleted --new <plik|katalog>... [--noise REGEX]
#     --deleted dodaje do starych plikow usuniete od REV pliki tekstowe
#     (git diff --name-only --diff-filter=D REV: .md, .txt, .toml, .html).
# Kod wyjscia: 0 brak LOST, 1 sa LOST, 2 blad uzycia.
# Wymaga: bash 3.2+, git, awk.

set -uo pipefail

root="."
rev=""
deleted=0
noise=""
mode=""
old=()
new=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift ;;
    --old-rev) rev="${2:-}"; shift ;;
    --deleted) deleted=1 ;;
    --noise) noise="${2:-}"; shift ;;
    --old) mode=old ;;
    --new) mode=new ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    -*) echo "USAGE nieznana opcja: $1"; exit 2 ;;
    *)
      case "$mode" in
        old) old+=("$1") ;;
        new) new+=("$1") ;;
        *) echo "USAGE argument bez --old albo --new: $1"; exit 2 ;;
      esac ;;
  esac
  shift
done
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "USAGE brak katalogu root"; exit 2; }
[ "$deleted" -eq 1 ] && [ -z "$rev" ] && { echo "USAGE --deleted wymaga --old-rev"; exit 2; }
[ "${#new[@]}" -gt 0 ] || { echo "USAGE brak --new"; exit 2; }
if [ -n "$rev" ]; then
  git -C "$root" rev-parse --verify -q "$rev^{commit}" >/dev/null || { echo "USAGE nieznana rewizja: $rev"; exit 2; }
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$root" || exit 2

# MARK: stare pliki

: >"$tmp/oldlist"
for f in ${old[@]+"${old[@]}"}; do printf '%s\n' "${f#$root/}" >>"$tmp/oldlist"; done
if [ "$deleted" -eq 1 ]; then
  git -c core.quotepath=off diff --name-only --diff-filter=D "$rev" -- 2>/dev/null |
    grep -E '\.(md|markdown|txt|toml|html)$' >>"$tmp/oldlist"
fi
awk '!seen[$0]++' "$tmp/oldlist" >"$tmp/oldu"
[ -s "$tmp/oldu" ] || { echo "USAGE brak starych plikow (--old albo --deleted)"; exit 2; }

: >"$tmp/tokens"
while IFS= read -r f; do
  if [ -f "$f" ]; then cat -- "$f" >"$tmp/src"
  elif [ -n "$rev" ] && git show "$rev:$f" >"$tmp/src" 2>/dev/null; then :
  else printf 'WARNING brak pliku: %s\n' "$f" >&2; continue; fi
  awk -v file="$f" '
    /^[ \t]*```/ { in_code = !in_code; next }
    in_code { next }
    {
      rest = $0
      while (match(rest, /`[^`]+`/)) {
        tok = substr(rest, RSTART + 1, RLENGTH - 2); rest = substr(rest, RSTART + RLENGTH)
        gsub(/^[ \t]+|[ \t]+$/, "", tok)
        if (length(tok) >= 3 && length(tok) <= 120) printf "%s\t%s\n", file, tok
      }
    }' "$tmp/src" >>"$tmp/tokens"
done <"$tmp/oldu"

# MARK: nowy korpus

: >"$tmp/corpus"
for n in "${new[@]}"; do
  n="${n#$root/}"
  if [ -d "$n" ]; then
    find "$n" -type f \( -name '*.md' -o -name '*.json' -o -name '*.txt' -o -name '*.toml' -o -name '*.yml' -o -name '*.yaml' -o -name '*.html' \) \
      -not -path '*/workspace/*' -not -path '*/sessions/*' 2>/dev/null
  elif [ -f "$n" ]; then
    printf '%s\n' "$n"
  else
    printf 'WARNING brak nowego pliku albo katalogu: %s\n' "$n" >&2
  fi
done | sed 's|^\./||' | awk 'NR == FNR { skip[$0] = 1; next } !skip[$0] && !seen[$0]++' "$tmp/oldu" - |
  while IFS= read -r f; do cat -- "$f"; printf '\n'; done >"$tmp/corpus"

# MARK: porownanie

default_noise='RUN_ID|CHECK_ID|EVIDENCE|[$]ARGUMENTS|[.]claude/agents|[.]claude/commands|pipeline_state|pipeline_check'
AD_NOISE="$default_noise" AD_EXTRA="$noise" awk -F'\t' -v corpus="$tmp/corpus" '
  BEGIN {
    noise = ENVIRON["AD_NOISE"]; extra = ENVIRON["AD_EXTRA"]
    RS_OLD = RS; RS = "\001"
    if ((getline text < corpus) <= 0) text = ""
    RS = RS_OLD
  }
  {
    file = $1; tok = substr($0, length(file) + 2)
    if (tok in seen) next
    seen[tok] = 1; total++
    if (tok ~ noise || (extra != "" && tok ~ extra)) { filtered++; next }
    if (index(text, tok) == 0) { lost++; printf "LOST %s %s\n", file, tok }
  }
  END { printf "TOKENS %d LOST %d FILTERED %d\n", total, lost, filtered; exit (lost > 0) }
' "$tmp/tokens"
