#!/bin/bash
# Testy czarnej skrzynki dla adoption_diff.sh.
# Buduje repo ze starym setupem (agent, komenda), usuwa go i porownuje z nowym.
set -u
AD="$(cd "$(dirname "$0")/.." && pwd)/scripts/adoption_diff.sh"
PASS=0; FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }
has()  { grep -qF -- "$2" "$1" && ok || fail "$3"; }
hasnt() { grep -qF -- "$2" "$1" && fail "$3" || ok; }

R="$TMP/repo"
git init -q "$R" && git -C "$R" config user.email t@t && git -C "$R" config user.name t
mkdir -p "$R/.claude/agents" "$R/.claude/commands" "$R/.ai/overlays" "$R/.ai/workspace/plans" "$R/scripts"
cat >"$R/.claude/agents/reviewer.md" <<'EOF'
# reviewer
Uruchom `scripts/lint.sh` przed review.
Kategoria findings `ui-convention` i `layers`.
Zapisz dowod w `.ai/workspace/runs/RUN_ID/review.md`.
Przekaz do `old-implementer` przez `$ARGUMENTS`.
Krotki `ab` nie jest tokenem.
```sh
echo `ignorowane` w bloku
```
Status `REVIEW_OK` z `pipeline_state.py`.
EOF
printf '# plan\nSekcja `DATA_CONTRACT` w planie. Znowu `layers`.\n' >"$R/.claude/commands/feature plan.md"
printf '#!/bin/bash\n' >"$R/scripts/lint.sh"
printf '# CLAUDE\nZobacz `.ai/overlays`.\n' >"$R/CLAUDE.md"
printf '## Obowiązkowe sekcje planu\n- DATA_CONTRACT: pola odpowiedzi\n' >"$R/.ai/overlays/av-plan.md"
printf '## Jak sprawdzać osie\nlint: scripts/lint.sh; oś layers\n' >"$R/.ai/overlays/av-review.md"
printf 'ui-convention REVIEW_OK\n' >"$R/.ai/workspace/plans/2026-01-01-av-setup.md"
git -C "$R" add -A && git -C "$R" commit -qm init
git -C "$R" rm -q ".claude/agents/reviewer.md" ".claude/commands/feature plan.md"

# MARK: usuniete pliki z rewizji
out="$TMP/out.txt"
bash "$AD" --root "$R" --old-rev HEAD --deleted --new CLAUDE.md .ai --noise 'old\.implementer|old-implementer' >"$out"; rc=$?
[ "$rc" -eq 1 ] && ok || fail "kod 1 przy LOST: $rc"
has "$out" "LOST .claude/agents/reviewer.md ui-convention" "token tylko w workspace to LOST"
has "$out" "LOST .claude/agents/reviewer.md REVIEW_OK" "status bez sladu"
hasnt "$out" "scripts/lint.sh" "token obecny w nakladce"
hasnt "$out" "LOST .claude/agents/reviewer.md layers" "token obecny w nowym setupie"
hasnt "$out" "DATA_CONTRACT" "token z pliku ze spacja obecny"
hasnt "$out" "RUN_ID" "filtr RUN_ID"
hasnt "$out" "ARGUMENTS" "filtr ARGUMENTS"
hasnt "$out" "old-implementer" "filtr --noise"
hasnt "$out" "pipeline_state" "filtr pipeline_state"
hasnt "$out" " ab" "token krotszy niz 3 znaki"
hasnt "$out" "ignorowane" "linie plotu pominiete"
has "$out" "TOKENS 9 LOST 2 FILTERED 4" "podsumowanie"

# MARK: pliki z drzewa
printf 'Regula `KEEP_ME` i `scripts/lint.sh`.\n' >"$R/old.md"
bash "$AD" --root "$R" --old old.md --new CLAUDE.md .ai >"$out"; rc=$?
has "$out" "LOST old.md KEEP_ME" "plik z drzewa"
has "$out" "TOKENS 2 LOST 1 FILTERED 0" "podsumowanie pliku z drzewa"
bash "$AD" --root "$R" --old old.md --new CLAUDE.md .ai old.md >"$out"
has "$out" "LOST old.md KEEP_ME" "stary plik nie jest korpusem"
printf 'KEEP_ME\n' >>"$R/.ai/overlays/av-plan.md"
bash "$AD" --root "$R" --old old.md --new CLAUDE.md .ai >"$out"; rc=$?
[ "$rc" -eq 0 ] && ok || fail "kod 0 bez LOST: $rc"
has "$out" "TOKENS 2 LOST 0 FILTERED 0" "wszystko przeniesione"

# MARK: uzycie
bash "$AD" --root "$R" --new .ai >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "brak starych plikow: kod $rc"
bash "$AD" --root "$R" --deleted --new .ai >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "--deleted bez --old-rev: kod $rc"
bash "$AD" --root "$R" --old old.md >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "brak --new: kod $rc"
bash "$AD" --root "$R" --old-rev nie-ma --deleted --new .ai >/dev/null; rc=$?
[ "$rc" -eq 2 ] && ok || fail "zla rewizja: kod $rc"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
