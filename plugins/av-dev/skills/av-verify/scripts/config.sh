#!/usr/bin/env bash
# config.sh - efektywny config av-dev: config zespolu z lokalnym nadpisaniem.
#
# Config zespolu: .ai/av.config.json (commitowany).
# Nadpisanie lokalne: <config>.local, domyslnie .ai/av.config.json.local
#   (gitignorowany, ustawienia jednej osoby albo jednej maszyny).
# Laczenie: obiekty rekurencyjnie, tablice i wartosci proste zastepuja,
#   null usuwa klucz.
#
# Uzycie:
#   config.sh [--root DIR] [--config PLIK]            efektywny config (JSON)
#   config.sh --sources [--root DIR] [--config PLIK]  pliki, klucze nadpisane, ostrzezenia
# Opcje:
#   --no-local   pomin nadpisanie lokalne
#   --out PLIK   zapisz efektywny config do pliku zamiast na stdout
# Wynik --sources: CONFIG <plik>, CONFIG_LOCAL <plik>|none, OVERRIDE <klucz>,
#   REMOVE <klucz>, WARNING <tekst>.
# Kody: 0 OK, 2 blad (brak configu, zly JSON, zle wywolanie).
# Wymaga: bash 3.2+, git, jq.

set -uo pipefail

fail() {
  printf 'CONFIG_ERROR %s\n' "$1"
  exit 2
}

command -v jq >/dev/null 2>&1 || fail "brak jq; zainstaluj jq (brew install jq)"

root_arg=""
config_arg=""
sources=0
no_local=0
out=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root) root_arg="${2:-}"; shift ;;
    --config) config_arg="${2:-}"; shift ;;
    --out) out="${2:-}"; shift ;;
    --sources) sources=1 ;;
    --no-local) no_local=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) fail "nieznany argument '$1'" ;;
  esac
  shift
done

if [ -n "$root_arg" ]; then
  root="$(git -C "$root_arg" rev-parse --show-toplevel 2>/dev/null || (cd "$root_arg" 2>/dev/null && pwd))"
else
  root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
[ -n "$root" ] || fail "brak katalogu root"

cfg="${config_arg:-$root/.ai/av.config.json}"
case "$cfg" in /*) ;; *) [ -f "$cfg" ] || cfg="$root/$cfg" ;; esac
[ -f "$cfg" ] || fail "brak $cfg; uruchom skill av-setup"
jq empty "$cfg" 2>/dev/null || fail "niepoprawny JSON w $cfg"
jq -e 'type == "object"' "$cfg" >/dev/null 2>&1 || fail "config $cfg nie jest obiektem JSON"

local_cfg="$cfg.local"
use_local=0
if [ "$no_local" -eq 0 ] && [ -f "$local_cfg" ]; then
  jq empty "$local_cfg" 2>/dev/null || fail "niepoprawny JSON w $local_cfg"
  jq -e 'type == "object"' "$local_cfg" >/dev/null 2>&1 || fail "config $local_cfg nie jest obiektem JSON"
  use_local=1
fi

# MARK: zrodla

if [ "$sources" -eq 1 ]; then
  printf 'CONFIG %s\n' "${cfg#$root/}"
  if [ "$use_local" -eq 0 ]; then
    printf 'CONFIG_LOCAL none\n'
    exit 0
  fi
  rel="${local_cfg#$root/}"
  printf 'CONFIG_LOCAL %s\n' "$rel"
  jq -r '
    paths(type != "object") as $p
    | ($p | map(tostring) | join(".")) as $k
    | if getpath($p) == null then "REMOVE \($k)" else "OVERRIDE \($k)" end
  ' "$local_cfg"
  case "$local_cfg" in
    "$root"/*)
      if git -C "$root" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
        printf 'WARNING %s jest sledzony przez git; usun go z repo (git rm --cached) i dopisz do .gitignore\n' "$rel"
      elif ! git -C "$root" check-ignore -q -- "$rel" 2>/dev/null; then
        printf 'WARNING %s nie jest w .gitignore; dopisz go, zeby nie trafil do commita\n' "$rel"
      fi
      ;;
  esac
  exit 0
fi

# MARK: laczenie

emit() {
  if [ "$use_local" -eq 0 ]; then
    jq . "$cfg"
  else
    jq -s '
      def merge($a; $b):
        if ($a | type) == "object" and ($b | type) == "object" then
          reduce ($b | keys_unsorted[]) as $k ($a;
            if $b[$k] == null then del(.[$k]) else .[$k] = merge($a[$k]; $b[$k]) end)
        else $b end;
      merge(.[0]; .[1])
    ' "$cfg" "$local_cfg"
  fi
}

if [ -n "$out" ]; then
  emit > "$out" || fail "nie moge zapisac $out"
else
  emit
fi
