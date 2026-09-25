#!/usr/bin/env bash
# check_setup.sh - walidator setupu av-dev w repo (config, nakladki, role, skille rol).
#
# Wynik: linie SETUP_<KOD> <szczegoly>, na koncu CHECKED n ERRORS e WARNINGS w.
#   SETUP_CONFIG_MISSING      brak configu (ERROR)
#   SETUP_CONFIG_INVALID      config nie jest poprawnym JSON (ERROR)
#   SETUP_OVERLAY_MISSING     brak nakladki jednego z 5 skilli (WARNING)
#   SETUP_OVERLAY_SECTION     nakladka bez wymaganej sekcji (WARNING)
#   SETUP_ROLES_NONE          config bez "roles"; kazdy plik nalezy do implementer (WARNING)
#   SETUP_ROLE_INVALID        rola bez name, skill albo globs (ERROR)
#   SETUP_ROLE_SKILL_MISSING  brak .claude/skills/<skill>/SKILL.md (ERROR)
#   SETUP_ROLE_OVERLAP        plik sledzony pasuje do globow 2 rol (ERROR)
#   SETUP_ROLE_EMPTY          glob roli nie pasuje do zadnego pliku sledzonego (WARNING)
#   SETUP_UNOWNED_DIR         katalog top-level z plikami zrodel bez wlasciciela (WARNING)
#   SETUP_REF_MISSING         sciezka z backtickow w nakladce albo skillu nie istnieje (ERROR)
#   SETUP_REF_SKIPPED         brak av-docs-sync/scripts/check_refs.sh (WARNING)
#   SETUP_GATE_UNKNOWN        --gate X albo --only X spoza validation (ERROR)
#   SETUP_GLOB_COPY           skill roli albo nakladka kopiuje 3+ globy roli (WARNING)
#   SETUP_INTEGRATION_INVALID pole integracji niezgodne z manifestem szablonu (ERROR)
#   SETUP_TEMPLATE_MISSING    szablon ma zastosowanie (applies), a pliku w repo brak (WARNING)
#                             szablony: templates/<nazwa>/template.json albo AV_TEMPLATES_DIR
#   SETUP_LOCAL_TRACKED       <config>.local jest sledzony przez git (ERROR)
#   SETUP_LOCAL_IGNORE        .gitignore nie ignoruje <config>.local (WARNING)
#   SETUP_LOCAL_USED          informacja: kontrola dziala na configu z nadpisaniem lokalnym
#
# Config: efektywny (config zespolu z nadpisaniem <config>.local, skrypt
# av-verify/scripts/config.sh). --no-local sprawdza sam config zespolu.
#
# Tryb wlasciciela: dla kazdego pliku linia OWNER <plik> <wlasciciel>, gdzie
# wlasciciel (ostatnie pole) to nazwa roli, generated, unowned albo implementer.
# Kolejnosc: generatedPaths, potem roles (pierwsza wedlug order i kolejnosci
# w configu), potem unownedPaths, w przeciwnym razie implementer.
# Globy jak git pathspec :(glob): *, ?, **; sciezka bez gwiazdki pasuje tez
# do zawartosci katalogu. Pliki nie musza istniec.
#
# Uzycie:
#   check_setup.sh [--root DIR] [--config PLIK] [--no-local]
#   check_setup.sh [--root DIR] [--config PLIK] [--no-local] --owner <plik>...
# Kod wyjscia: 0 brak ERROR, 1 sa ERROR (w --owner: blad configu), 2 blad uzycia.
# Wymaga: bash 3.2+, git, jq, awk.

set -uo pipefail

root="."
config=""
owner_mode=0
no_local=0
owner_files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:-}"; shift ;;
    --config) config="${2:-}"; shift ;;
    --owner) owner_mode=1 ;;
    --no-local) no_local=1 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    -*) echo "USAGE nieznana opcja: $1"; exit 2 ;;
    *) if [ "$owner_mode" -eq 1 ]; then owner_files+=("$1"); else echo "USAGE nieznany argument: $1"; exit 2; fi ;;
  esac
  shift
done
command -v jq >/dev/null 2>&1 || { echo "USAGE brak jq; zainstaluj jq (brew install jq)"; exit 2; }
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "USAGE brak katalogu root"; exit 2; }
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo "USAGE root nie jest repozytorium git"; exit 2; }
[ -n "$config" ] || config="$root/.ai/av.config.json"
case "$config" in /*) ;; *) [ -f "$config" ] || config="$root/$config" ;; esac
if [ "$owner_mode" -eq 1 ] && [ "${#owner_files[@]}" -eq 0 ]; then echo "USAGE --owner wymaga listy plikow"; exit 2; fi

skill_dir="$(cd "$(dirname "$0")/.." && pwd)"
templates_dir="${AV_TEMPLATES_DIR:-$skill_dir/templates}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

checked=0; errors=0; warnings=0
err()  { errors=$((errors + 1)); printf 'SETUP_%s\n' "$*"; }
warn() { warnings=$((warnings + 1)); printf 'SETUP_%s\n' "$*"; }
finish() {
  printf 'CHECKED %d ERRORS %d WARNINGS %d\n' "$checked" "$errors" "$warnings"
  [ "$errors" -eq 0 ] && exit 0 || exit 1
}

# MARK: config

checked=$((checked + 1))
if [ ! -f "$config" ]; then
  [ "$owner_mode" -eq 1 ] && { for f in "${owner_files[@]}"; do printf 'OWNER %s implementer\n' "$f"; done; exit 0; }
  err "CONFIG_MISSING ${config#$root/}"; finish
fi
if ! jq empty "$config" >/dev/null 2>&1; then
  [ "$owner_mode" -eq 1 ] && { echo "SETUP_CONFIG_INVALID ${config#$root/}"; exit 1; }
  err "CONFIG_INVALID ${config#$root/}"; finish
fi

# MARK: nadpisanie lokalne

team_config="$config"
local_rel="${team_config#$root/}.local"
case "$team_config" in
  "$root"/*)
    if git -C "$root" ls-files --error-unmatch -- "$local_rel" >/dev/null 2>&1; then
      [ "$owner_mode" -eq 1 ] || err "LOCAL_TRACKED $local_rel jest w gicie; git rm --cached $local_rel"
    elif ! git -C "$root" check-ignore -q --no-index -- "$local_rel" 2>/dev/null; then
      [ "$owner_mode" -eq 1 ] || warn "LOCAL_IGNORE dopisz $local_rel do .gitignore"
    fi
    ;;
esac
config_sh="$skill_dir/../av-verify/scripts/config.sh"
if [ "$no_local" -eq 0 ] && [ -f "$team_config.local" ] && [ -f "$config_sh" ]; then
  if bash "$config_sh" --root "$root" --config "$team_config" --out "$tmp/config.json" >/dev/null 2>&1; then
    config="$tmp/config.json"
    [ "$owner_mode" -eq 1 ] || printf 'SETUP_LOCAL_USED %s\n' "$local_rel"
  else
    [ "$owner_mode" -eq 1 ] && { echo "SETUP_CONFIG_INVALID $local_rel"; exit 1; }
    err "CONFIG_INVALID $local_rel"; finish
  fi
fi

# rules: kind TAB name TAB glob; role w kolejnosci order, potem kolejnosci w configu
jq -r '
  ([.generatedPaths // [] | .[] | ["generated", "-", .]]
   + ([.roles // [] | to_entries[] | select(.value | type == "object")
       | {i: .key, o: (.value.order // 999), r: .value}] | sort_by(.o, .i)
       | map(.r as $r | ($r.globs // [])[] | ["role", ($r.name // "?"), .]))
   + [.unownedPaths // [] | .[] | ["unowned", "-", .]])[] | @tsv' "$config" >"$tmp/rules" 2>/dev/null

# matcher: rules + lista sciezek -> F path roles gen unowned; na koncu G role glob hits
match_paths() {
  awk -F'\t' '
    function g2re(g,   r, i, n, c) {
      if (g ~ /\/$/) g = g "**"
      r = "^"; n = length(g); i = 1
      while (i <= n) {
        c = substr(g, i, 1)
        if (c == "*") {
          if (substr(g, i + 1, 1) == "*") {
            if (substr(g, i + 2, 1) == "/") { r = r "(.*/)?"; i += 3; continue }
            r = r ".*"; i += 2; continue
          }
          r = r "[^/]*"
        } else if (c == "?") r = r "[^/]"
        else if (c == "^") r = r "\\^"
        else if (index(".+()|${}[]", c)) r = r "[" c "]"
        else r = r c
        i++
      }
      if (g !~ /[*?]/) r = r "(/.*)?"
      return r "$"
    }
    FNR == NR { n++; kind[n] = $1; name[n] = $2; glob[n] = $3; re[n] = g2re($3); hits[n] = 0; next }
    {
      p = $0; sub(/^\.\//, "", p); roles = ""; gen = 0; un = 0
      for (i = 1; i <= n; i++) {
        if (p !~ re[i]) continue
        hits[i]++
        if (kind[i] == "generated") gen = 1
        else if (kind[i] == "unowned") un = 1
        else if (index("," roles ",", "," name[i] ",") == 0) roles = roles (roles == "" ? "" : ",") name[i]
      }
      printf "F\t%s\t%s\t%d\t%d\n", p, roles, gen, un
    }
    END { for (i = 1; i <= n; i++) if (kind[i] == "role") printf "G\t%s\t%s\t%d\n", name[i], glob[i], hits[i] }
  ' "$tmp/rules" -
}

# MARK: tryb wlasciciela

if [ "$owner_mode" -eq 1 ]; then
  for f in "${owner_files[@]}"; do
    case "$f" in "$root"/*) f="${f#$root/}" ;; esac
    printf '%s\n' "$f"
  done | match_paths | awk -F'\t' '$1 == "F" {
    if ($4 == 1) o = "generated"
    else if ($3 != "") { o = $3; if (index(o, ",")) { print "WARNING nakladanie rol dla " $2 ": " o > "/dev/stderr"; sub(/,.*/, "", o) } }
    else if ($5 == 1) o = "unowned"
    else o = "implementer"
    print "OWNER " $2 " " o
  }'
  exit 0
fi

rel() { printf '%s\n' "${1#$root/}"; }
# MARK: szablony integracji

if [ "$owner_mode" -eq 0 ]; then
  docs_root="$(jq -r '.docs.root // ".ai"' "$config")"
  scripts_dir="$(jq -r '.paths.scripts // ".ai/scripts"' "$config")"
  for manifest in "$templates_dir"/*/template.json; do
    [ -f "$manifest" ] || continue
    checked=$((checked + 1))
    tname="$(jq -r '.name // empty' "$manifest")"
    validate="$(jq -r '.validate // empty' "$manifest")"
    if [ -n "$validate" ]; then
      while IFS= read -r problem; do
        [ -n "$problem" ] && err "INTEGRATION_INVALID $problem"
      done < <(jq -r "$validate" "$config" 2>/dev/null)
    fi
    applies="$(jq -r '.applies // "false"' "$manifest")"
    jq -e "$applies" "$config" >/dev/null 2>&1 || continue
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      target="${target//\{docs.root\}/${docs_root%/}}"
      target="${target//\{paths.scripts\}/${scripts_dir%/}}"
      [ -e "$root/$target" ] || warn "TEMPLATE_MISSING $target (szablon $tname); utworz z templates/$tname"
    done < <(jq -r '(.files // {})[]' "$manifest")
  done
fi

overlays_dir="$(jq -r '.paths.overlays // ".ai/overlays"' "$config")"

# MARK: nakladki

required_sections() {
  case "$1" in
    av-plan) printf '%s\n' "Pliki do przeczytania przed planem" "Obowiązkowe sekcje planu" ;;
    av-implement) printf '%s\n' "Role" "Obowiązkowe kroki" "Wybór trybu" "Bramki per etap" ;;
    av-review) printf '%s\n' "Jak sprawdzać osie" ;;
    av-verify) printf '%s\n' "Dobór bramki" "Interpretacja wyników" ;;
    av-docs-sync) printf '%s\n' "Mapa kod -> docs" "Znane fałszywe nazwy" ;;
  esac
}

: >"$tmp/docs"
for o in av-plan av-implement av-review av-verify av-docs-sync; do
  f="$root/$overlays_dir/$o.md"
  checked=$((checked + 1))
  if [ ! -f "$f" ]; then warn "OVERLAY_MISSING $overlays_dir/$o.md"; continue; fi
  rel "$f" >>"$tmp/docs"
  while IFS= read -r sec; do
    checked=$((checked + 1))
    awk -v s="## $sec" 'index($0, s) == 1 { found = 1; exit } END { exit !found }' "$f" ||
      warn "OVERLAY_SECTION $overlays_dir/$o.md \"$sec\""
  done < <(required_sections "$o")
done
for f in "$root"/.claude/skills/*/SKILL.md; do [ -f "$f" ] && rel "$f" >>"$tmp/docs"; done

# MARK: role

nroles="$(jq '(.roles // []) | length' "$config")"
git -C "$root" -c core.quotepath=off ls-files >"$tmp/tracked"
if [ "$nroles" -eq 0 ]; then
  checked=$((checked + 1))
  warn 'ROLES_NONE brak "roles" w configu; kazdy plik nalezy do implementer'
else
  while IFS=$'\037' read -r idx name skill nglobs; do
    checked=$((checked + 1))
    if [ -z "$name" ] || [ -z "$skill" ] || [ "$nglobs" -eq 0 ]; then
      err "ROLE_INVALID roles[$idx] wymaga name, skill i globs"; continue
    fi
    case "$skill" in *:*) continue ;; esac
    checked=$((checked + 1))
    sk="$root/.claude/skills/$skill/SKILL.md"
    if [ ! -f "$sk" ]; then err "ROLE_SKILL_MISSING $name .claude/skills/$skill/SKILL.md"; continue; fi
    checked=$((checked + 1))
    copies="$(jq -r --argjson i "$idx" '.roles[$i].globs[]' "$config" | while IFS= read -r g; do grep -qF -- "$g" "$sk" && echo x; done | wc -l | tr -d ' ')"
    [ "$copies" -ge 3 ] && warn "GLOB_COPY .claude/skills/$skill/SKILL.md kopiuje $copies globy roli $name; zakres plikow nalezy do configu (roles)"
  done < <(jq -r '(.roles // []) | to_entries[] | [.key, (.value.name // ""), (.value.skill // ""), ((.value.globs // []) | length)] | map(tostring) | join("\u001f")' "$config")

  impl="$root/$overlays_dir/av-implement.md"
  if [ -f "$impl" ]; then
    checked=$((checked + 1))
    copies="$(jq -r '.roles[].globs // [] | .[]' "$config" | while IFS= read -r g; do grep -qF -- "$g" "$impl" && echo x; done | wc -l | tr -d ' ')"
    [ "$copies" -ge 3 ] && warn "GLOB_COPY $overlays_dir/av-implement.md kopiuje $copies globy rol; tabela rol ma linkowac do configu (roles)"
  fi

  match_paths <"$tmp/tracked" >"$tmp/match"
  while IFS=$'\t' read -r _ name g hits; do
    checked=$((checked + 1))
    if [ "$hits" -eq 0 ]; then
      hint=""; case "$g" in *"{"*) hint=" (nawiasy {a,b} nieobslugiwane: kazdy wariant osobno)" ;; esac
      warn "ROLE_EMPTY $name $g$hint"
    fi
  done < <(awk -F'\t' '$1 == "G"' "$tmp/match")

  checked=$((checked + 1))
  awk -F'\t' '$1 == "F" && $4 == 0 && index($3, ",") { c[$3]++; if (c[$3] <= 5) l[$3] = l[$3] (c[$3] > 1 ? ", " : "") $2 }
    END { for (k in c) printf "%s\t%d\t%s\n", k, c[k], l[k] }' "$tmp/match" | LC_ALL=C sort |
  while IFS=$'\t' read -r pair count list; do
    printf 'SETUP_ROLE_OVERLAP %s %d: %s\n' "$pair" "$count" "$list"
  done >"$tmp/overlap"
  if [ -s "$tmp/overlap" ]; then errors=$((errors + $(wc -l <"$tmp/overlap"))); cat "$tmp/overlap"; fi

  checked=$((checked + 1))
  awk -F'\t' -v re='\\.(swift|php|ts|js|twig|py|kt|java|m|h|xib|storyboard|html|scss|css)$' '
    $1 == "F" && $3 == "" && $4 == 0 && $5 == 0 && $2 ~ re && index($2, "/") {
      n = split($2, parts, "/"); s = (n > 2) ? parts[1] "/" parts[2] : parts[1]
      print parts[1] "\t" s
    }' "$tmp/match" | LC_ALL=C sort | uniq -c |
    awk '{ c = $1; sub(/^[ ]*[0-9]+ /, ""); split($0, a, "\t"); printf "%s\t%d\t%s\n", a[1], c, a[2] }' |
    LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2nr |
    awk -F'\t' '
      $1 != top { if (top != "") printf "SETUP_UNOWNED_DIR %s %d plikow bez wlasciciela: %s\n", top, tot, d; top = $1; tot = 0; k = 0; d = "" }
      { tot += $2; k++; if (k <= 5) d = d (k > 1 ? ", " : "") $3 " " $2 }
      END { if (top != "") printf "SETUP_UNOWNED_DIR %s %d plikow bez wlasciciela: %s\n", top, tot, d }' >"$tmp/unowned"
  if [ -s "$tmp/unowned" ]; then warnings=$((warnings + $(wc -l <"$tmp/unowned"))); cat "$tmp/unowned"; fi
fi

# MARK: sciezki i bramki w nakladkach i skillach

refs="$skill_dir/../av-docs-sync/scripts/check_refs.sh"
if [ ! -s "$tmp/docs" ]; then :
elif [ -f "$refs" ]; then
  checked=$((checked + 1))
  ws="$(jq -r '.paths.workspace // ".ai/workspace"' "$config")"
  docs=(); while IFS= read -r d; do docs+=("$d"); done <"$tmp/docs"
  (cd "$root" && bash "$refs" "${docs[@]}" --root "$root" --workspace "$ws" 2>/dev/null) | awk '$1 == "MISSING"' >"$tmp/missing"
  while IFS= read -r l; do err "REF_MISSING ${l#MISSING }"; done <"$tmp/missing"
else
  warn "REF_SKIPPED brak av-docs-sync/scripts/check_refs.sh obok av-setup"
fi

jq -r '(.validation.gates // {}) | keys[]' "$config" >"$tmp/gates"
jq -r '(.validation.commands // {}) | keys[]' "$config" >"$tmp/cmds"
while IFS= read -r d; do
  grep -noE -- '--(gate|only)[ =]+[A-Za-z0-9_.,-]+' "$root/$d" 2>/dev/null | while IFS= read -r hit; do
    line="${hit%%:*}"; rest="${hit#*:}"
    flag="$(printf '%s' "$rest" | sed -E 's/^--(gate|only).*/\1/')"
    names="$(printf '%s' "$rest" | sed -E 's/^--(gate|only)[ =]+//; s/[.,]+$//')"
    printf '%s\n' "$names" | tr ',' '\n' | while IFS= read -r x; do
      [ -n "$x" ] || continue
      list="$tmp/cmds"; [ "$flag" = "gate" ] && list="$tmp/gates"
      grep -qxF -- "$x" "$list" || printf '%s:%s --%s %s\n' "$d" "$line" "$flag" "$x"
    done
  done
done <"$tmp/docs" >"$tmp/gate_unknown"
checked=$((checked + $(wc -l <"$tmp/docs")))
while IFS= read -r l; do err "GATE_UNKNOWN $l"; done <"$tmp/gate_unknown"

finish
