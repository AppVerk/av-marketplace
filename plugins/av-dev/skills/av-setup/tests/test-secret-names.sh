#!/bin/bash
# Tests for secret_names.sh (av_secret_name) and for one list: every script that decides whether
# a file is a secret uses av_secret_name, none keeps its own pattern list.
set -u
SCRIPTS="$(cd "$(dirname "$0")/.." && pwd)/scripts"
SKILLS="$(cd "$SCRIPTS/../.." && pwd)"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); printf 'FAIL: %s\n' "$1" >&2; }

# shellcheck source=../scripts/secret_names.sh
. "$SCRIPTS/secret_names.sh"

# --- 1. names that are secrets
for n in .env .env.local .env.production app.env config/.env.test \
  key.pem server.key AuthKey_ABC123.p8 Distribution.p12 cert.pfx release.jks app.keystore \
  apple.cer ca.crt ca.der putty.ppk AppStore_Distribution.mobileprovision Dev.provisionprofile \
  id_rsa id_rsa_backup id_dsa id_ecdsa id_ed25519 id_ed25519.old \
  .npmrc .netrc _netrc .pypirc .git-credentials .dockercfg auth.json \
  keystore.properties release-keystore.properties signing.properties \
  google-services.json GoogleService-Info.plist GoogleService-Info-Prod.plist \
  service-account.json firebase-service-account.json my_service_account.json \
  credentials.json client_secret_42.json secrets.yml secret.txt app-credentials.xml \
  SECRETS.YAML Credentials.JSON DISTRIBUTION.P12 path/with\ space/.env \
  tests/.env tests/fixtures/server.key AppTests/Distribution.p12 config/secrets/credentials.json \
  Secrets.xctestplan Credentials.xcscheme; do
  av_secret_name "$n" && ok || fail "secret not recognised: $n"
done

# --- 2. names that are not secrets: templates, public keys, code and docs, ordinary files
for n in .env.dist .env.example .env.sample .env.template parameters.yml.dist config.json.example \
  id_rsa.pub id_ed25519.pub SecretManager.swift secrets.md CredentialsForm.tsx credential_store.py \
  secret-rotation.sh KeychainSecret.m secrets.jq README.md package.json app.json Info.plist \
  environment.ts key.ts keyboard.swift monkey.txt distribution.md envelope.json \
  SecretScreen.storyboard Credentials.xib \
  N-FamilyTests/Fixtures/api/auth-login-bad-credentials.json tests/fixtures/client_secret.json \
  spec/support/secrets.yml src/__mocks__/credentials.json testdata/secret.txt AppUITests/secrets.json; do
  av_secret_name "$n" && fail "false secret: $n" || ok
done

# --- 2b. only directories inside the repo count: ROOT is cut before the test-directory rule
av_secret_name "/work/tests/fixtures/app/secrets.yml" "/work/tests/fixtures/app" && ok || fail "a repo under tests/: its secrets.yml must count"
av_secret_name "/work/tests/fixtures/app/secrets.yml" "/work/tests/fixtures/app/" && ok || fail "ROOT with a trailing slash"
av_secret_name "/work/app/tests/secrets.yml" "/work/app" && fail "tests/ inside the repo: not a secret" || ok
av_secret_name "/work/tests/app/.env" && ok || fail "no ROOT: env files still count"

# --- 3. the caller's nocasematch setting is kept
shopt -u nocasematch
av_secret_name ".ENV" >/dev/null
shopt -q nocasematch && fail "nocasematch left on after the call" || ok
shopt -s nocasematch
av_secret_name "readme.md" >/dev/null
shopt -q nocasematch && ok || fail "nocasematch turned off for a caller that had it on"
shopt -u nocasematch

# --- 4. one list: each user sources secret_names.sh and keeps no pattern list of its own
users="$SCRIPTS/scan.sh $SCRIPTS/adapters/php-symfony/adapter.sh $SCRIPTS/adapters/ios-xcode/adapter.sh
  $SCRIPTS/adapters/android/adapter.sh $SKILLS/av-docs-sync/scripts/docs_lib.sh"
for f in $users; do
  grep -q 'secret_names.sh' "$f" && grep -q 'av_secret_name' "$f" && ok || fail "does not use secret_names.sh: ${f#"$SKILLS"/}"
  grep -nE '\*\.(p12|pem|mobileprovision|keystore)\b|id_rsa\*' "$f" | grep -v '^[0-9]*:[[:space:]]*#' | grep -q . \
    && fail "keeps its own secret patterns: ${f#"$SKILLS"/}" || ok
done
grep -q 'docs_secret_excludes' "$SKILLS/av-docs-sync/scripts/check_names.sh" && ok || fail "check_names.sh does not exclude secrets through docs_secret_excludes"
grep -q ':(exclude,glob)\*\*/\*\.pem' "$SKILLS/av-docs-sync/scripts/check_names.sh" && fail "check_names.sh keeps its own secret globs" || ok

# --- 5. a missing secret_names.sh is an error, not a silent empty list
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts"
cp "$SCRIPTS/scan.sh" "$TMP/scripts/"
out="$(bash "$TMP/scripts/scan.sh" "$TMP" 2>/dev/null)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'secret_names.sh not found' && ok || fail "scan.sh without secret_names.sh: code $rc, $out"
mkdir -p "$TMP/skills/av-docs-sync/scripts"
cp "$SKILLS/av-docs-sync/scripts/"*.sh "$TMP/skills/av-docs-sync/scripts/"
out="$(bash "$TMP/skills/av-docs-sync/scripts/check_refs.sh" "$TMP" --root "$TMP" 2>/dev/null)"; rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q 'DOCS_ERROR secret_names.sh not found' && ok || fail "docs scripts without secret_names.sh: code $rc, $out"

printf 'PASS %d FAIL %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
