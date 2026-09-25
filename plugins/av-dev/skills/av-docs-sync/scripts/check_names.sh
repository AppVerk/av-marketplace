#!/usr/bin/env bash
# check_names.sh - sprawdza, czy nazwy z dokumentacji istnieja w kodzie.
#
# Wyciaga z plikow markdown identyfikatory w backtickach: nazwy klas i typow
# (CamelCase), metod (camelCase z wielka litera w srodku), stalych i kluczy
# (SNAKE_CASE, snake_case z podkresleniem). Porownuje je ze slownikiem slow
# z plikow sledzonych przez git (i nowych, nieignorowanych), poza dokumentacja
# (*.md), oraz z nazwami plikow i katalogow. Pliki *.strings i *.stringsdict
# w UTF-16 (z BOM) sa przed tym konwertowane do UTF-8, wiec ich klucze tez licza sie
# jako znalezione.
#
# Wynik:
#   NAME_MISSING plik:linia nazwa   nazwy nie ma w kodzie (kandydat na rozjazd)
#
# Pomija:
#   - linie, ktore same mowia o braku lub usunieciu, i bloki kodu,
#   - nazwy w przekresleniu ~~...~~ (historia),
#   - placeholdery: Foo/foo jako czlon nazwy (openFoo, fooViewModel, foo_title),
#     Xxx, koncowe pojedyncze X (NovolApiX), nazwy stykajace sie z { } < > *
#     (novolApi{Feature}, Request<T>, NS*UsageDescription, account_error*),
#     My<Nazwa> w linii z "np.", "przyklad", "example" albo "e.g.",
#   - nazwy krotsze niz 4 znaki,
#   - nazwy z listy ignorowanych: sekcja "## Znane falszywe nazwy" w nakladce
#     <paths.overlays>/av-docs-sync.md (domyslnie .ai/overlays), linie
#     "- `Nazwa`" (dokladnie) albo "- `Prefiks*`" (prefiks). --ignore-file
#     zastepuje nakladke; plik moze miec te sekcje albo same linie z nazwami.
#
# Uzycie:
#   check_names.sh <plik.md|katalog> [...] [--root DIR] [--ignore-file PLIK]...
# Kod wyjscia: 0 brak kandydatow, 1 sa kandydaci, 2 blad uzycia.
# Wymaga: bash 3.2+, git, awk, grep, sort, comm; iconv dla UTF-16; jq opcjonalnie.

set -uo pipefail

root="."
paths=""
ignore_files=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift ;;
    --ignore-file) ignore_files="$ignore_files${2:-}"$'\n'; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) paths="$paths$1"$'\n' ;;
  esac
  shift
done
[ -n "$paths" ] || { echo "USAGE check_names.sh <plik.md|katalog> [...] [--root DIR] [--ignore-file PLIK]"; exit 2; }
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "USAGE brak katalogu root"; exit 2; }
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo "USAGE root nie jest repo git"; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# MARK: lista ignorowanych nazw

need_section=0
if [ -z "$ignore_files" ]; then
  overlays=""
  if [ -f "$root/.ai/av.config.json" ]; then
    config_sh="$(cd "$(dirname "$0")/../.." && pwd)/av-verify/scripts/config.sh"
    if command -v jq >/dev/null 2>&1 && [ -f "$config_sh" ]; then
      overlays="$(bash "$config_sh" --root "$root" 2>/dev/null | jq -r '.paths.overlays // empty' 2>/dev/null)"
    elif command -v jq >/dev/null 2>&1; then
      overlays="$(jq -r '.paths.overlays // empty' "$root/.ai/av.config.json" 2>/dev/null)"
    else
      overlays="$(sed -n 's/.*"overlays"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$root/.ai/av.config.json" | head -1)"
    fi
  fi
  [ -n "$overlays" ] || overlays=".ai/overlays"
  need_section=1
  [ -f "$root/${overlays%/}/av-docs-sync.md" ] && ignore_files="$root/${overlays%/}/av-docs-sync.md"$'\n'
else
  printf '%s' "$ignore_files" | while IFS= read -r f; do
    [ -f "$f" ] || [ -f "$root/$f" ] || { printf 'USAGE brak pliku --ignore-file: %s\n' "$f" >&2; echo x; }
  done | grep -q x && exit 2
fi

: >"$tmp/ignore"
printf '%s' "$ignore_files" | while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$f" ] || f="$root/$f"
  awk -v need_section="$need_section" '
    function take(line,    t) {
      if (match(line, /^[ \t]*[-*][ \t]+`[^`]+`/)) {
        t = substr(line, RSTART, RLENGTH); sub(/^[^`]*`/, "", t); sub(/`$/, "", t)
      } else if (line ~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*\*?[ \t]*$/) {
        t = line; gsub(/[ \t]/, "", t)
      } else return
      if (t ~ /^[A-Za-z_][A-Za-z0-9_]*\*?$/) print t
    }
    { lines[NR] = $0 }
    /^#+[ \t]+Znane fa(ł|l)szywe nazwy/ { sec = NR }
    END {
      if (sec) {
        for (i = sec + 1; i <= NR && lines[i] !~ /^#/; i++) take(lines[i])
      } else if (!need_section) {
        for (i = 1; i <= NR; i++) if (lines[i] !~ /^#/) take(lines[i])
      }
    }' "$f"
done >"$tmp/ignore"

# MARK: slownik nazw z kodu

git -C "$root" grep -I -h -o -w -E --untracked '[A-Za-z_][A-Za-z0-9_]{3,}' -- . ':(exclude)*.md' ':(exclude)*.lock' \
  ':(exclude)*.svg' ':(exclude)*.pbxproj' 2>/dev/null >"$tmp/code_words_raw"
git -C "$root" -c core.quotePath=false ls-files --cached --others --exclude-standard -- '*.strings' '*.stringsdict' 2>/dev/null |
  while IFS= read -r f; do
    [ -f "$root/$f" ] || continue
    bom="$(LC_ALL=C head -c 2 "$root/$f" | od -An -tx1 | tr -d ' \n')"
    case "$bom" in
      fffe|feff) iconv -f UTF-16 -t UTF-8 "$root/$f" 2>/dev/null | grep -o -E '[A-Za-z_][A-Za-z0-9_]{3,}' ;;
    esac
  done >>"$tmp/code_words_raw"
LC_ALL=C sort -u "$tmp/code_words_raw" >"$tmp/code_words"
git -C "$root" ls-files --cached --others --exclude-standard 2>/dev/null |
  awk -F/ '{ for (i = 1; i < NF; i++) print $i; n = $NF; sub(/\.[^.]+$/, "", n); print n }' | LC_ALL=C sort -u >"$tmp/file_names"
LC_ALL=C sort -u "$tmp/code_words" "$tmp/file_names" >"$tmp/known"

# MARK: dokumenty

printf '%s' "$paths" | while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in
    /*) abs="$p" ;;
    *) if [ -e "$root/$p" ]; then abs="$root/$p"; else abs="$(pwd)/$p"; fi ;;
  esac
  if [ -d "$abs" ]; then
    find "$abs" \( -path '*/workspace' -o -path '*/sessions' \) -prune \
      -o -name '*.md' -not -path '*/workspace/*' -not -path '*/sessions/*' -print 2>/dev/null
  elif [ -f "$abs" ]; then
    printf '%s\n' "$abs"
  else
    printf 'WARNING brak pliku albo katalogu: %s\n' "$p" >&2
  fi
done | sort -u >"$tmp/docs"

[ -s "$tmp/docs" ] || { echo "CHECKED 0 NAME_MISSING 0"; exit 0; }

# MARK: ekstrakcja nazw

(
  IFS=$'\n'
  set -f
  # shellcheck disable=SC2046
  awk -v ignore_file="$tmp/ignore" '
    BEGIN {
      neg = "(^|[^A-Za-z])(brak|nie istnieje|nie ma|nigdy|never|usuni(e|ę)t[a-z]*|usun(a|ą)(c|ć)|relokow[a-z]*|przeniesion[a-z]*|dawn(y|a|e|iej)|zamiast|removed|deleted|renamed|moved|formerly|previously|no longer|does not exist|instead of)([^A-Za-z]|$)"
      example = "(np\\.|przyk(ł|l)ad|example|e\\.g\\.)"
      while ((getline ig < ignore_file) > 0) {
        if (ig ~ /\*$/) prefix[++np] = substr(ig, 1, length(ig) - 1)
        else exact[ig] = 1
      }
    }
    function ignored(w,    i) {
      if (w in exact) return 1
      for (i = 1; i <= np; i++) if (index(w, prefix[i]) == 1) return 1
      return 0
    }
    function placeholder(w) {
      if (w ~ /^(Foo|Bar|Baz|Xxx|Example|Nazwa|Name|Moduł|Modul|TODO|TICKET|RUN_ID|YYYY)/) return 1
      if (w ~ /(^|[a-z0-9_])Foo([A-Z0-9_]|$)/ || w ~ /(^|_)foo([A-Z0-9_]|$)/) return 1
      if (index(w, "Xxx") > 0 || w ~ /[a-z0-9]X$/) return 1
      if (w ~ /^My[A-Z]/ && is_example) return 1
      return 0
    }
    FNR == 1 { in_code = 0 }
    /^[ \t]*```/ { in_code = !in_code; next }
    in_code { next }
    {
      if (tolower($0) ~ neg) next
      line = $0
      gsub(/~~([^~]|~[^~])*~~/, "", line)
      is_example = (tolower(line) ~ example)
      rest = line
      while (match(rest, /`[^`]+`/)) {
        tok = substr(rest, RSTART + 1, RLENGTH - 2); rest = substr(rest, RSTART + RLENGTH)
        s = tok; off = 0
        while (match(s, /[A-Za-z0-9_]+/)) {
          w = substr(s, RSTART, RLENGTH)
          before = substr(tok, off + RSTART - 1, 1)
          after = substr(tok, off + RSTART + RLENGTH, 1)
          off += RSTART + RLENGTH - 1
          s = substr(s, RSTART + RLENGTH)
          if (length(w) < 4 || index(w, "__") > 0 || w ~ /_$/) continue
          if (index("{}<>*", before) > 0 && before != "") continue
          if (index("{}<>*", after) > 0 && after != "") continue
          if (placeholder(w) || ignored(w)) continue
          camel = (w ~ /^[A-Z][a-z0-9]+[A-Z][A-Za-z0-9]*$/ || w ~ /^[a-z]+[A-Z][A-Za-z0-9]*$/)
          snake = (w ~ /^[A-Z][A-Z0-9]*_[A-Z0-9_]+$/ || w ~ /^[a-z][a-z0-9]*_[a-z0-9_]+$/)
          if (camel || snake) printf "%s\t%s:%d\n", w, FILENAME, FNR
        }
      }
    }' $(cat "$tmp/docs")
) | LC_ALL=C sort -t "$(printf '\t')" -k1,1 >"$tmp/names"

cut -f1 "$tmp/names" | LC_ALL=C sort -u >"$tmp/unique"
LC_ALL=C comm -23 "$tmp/unique" "$tmp/known" >"$tmp/missing"

checked="$(wc -l <"$tmp/unique" | tr -d ' ')"
count=0
while IFS=$'\t' read -r name where; do
  if LC_ALL=C grep -qxF -- "$name" "$tmp/missing"; then
    printf 'NAME_MISSING %s %s\n' "${where#$root/}" "$name"
    count=$((count + 1))
  fi
done <"$tmp/names"

printf 'CHECKED %s NAME_MISSING %d\n' "$checked" "$count"
[ "$count" -eq 0 ]
