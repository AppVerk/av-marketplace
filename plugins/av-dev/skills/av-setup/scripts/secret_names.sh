# shellcheck shell=bash
# secret_names.sh - the one list of file names that look like secrets. Sourced, not run.
#
# Used by scan.sh (secret_like_files, the base of the permissions.deny proposal, and files
# the scan never reads), the stack adapters (files they never open) and av-docs-sync
# (docs_lib.sh: files whose content never enters a check). One list, so a new pattern
# protects everywhere at once.
#
#   av_secret_name PATH [ROOT]
#                           code 0 when the file name looks like a secret; ROOT (the repo root)
#                           is cut from PATH first, so only directories inside the repo count
#
# Secret: env files, private keys, certificates and signing stores, provisioning profiles,
# SSH keys, token configs (.npmrc, .netrc, auth.json), cloud and Firebase credentials, and any
# name with "secret" or "credential" that is not source code or a doc. Case does not matter.
# Not secret: templates (.dist, .example, .sample, .template, .tmpl at the end), public keys
# (.pub), and code, docs or Xcode UI files such as SecretManager.swift, secrets.md or
# SecretScreen.storyboard. Test plans and schemes may hold environment values, so
# Secrets.xctestplan counts. A name that only contains "secret" or "credential" does not count inside a
# test or fixture directory (tests/, fixtures/, testdata/, mocks/, *Tests/): there it is test
# data, e.g. auth-bad-credentials.json. Env files, keys and certificates count everywhere.
# Requires: bash 3.2+.

av_secret_name() {
  local p="$1" n="${1##*/}" rc=1 restore=""
  [ -z "${2:-}" ] || p="${p#"${2%/}"/}"
  shopt -q nocasematch || { shopt -s nocasematch; restore=1; }
  case "$n" in
    *.dist|*.example|*.sample|*.template|*.tmpl|*.pub) rc=1 ;;
    .env|.env.*|*.env) rc=0 ;;
    *.pem|*.key|*.p8|*.p12|*.pfx|*.jks|*.keystore|*.cer|*.crt|*.der|*.ppk) rc=0 ;;
    *.mobileprovision|*.provisionprofile) rc=0 ;;
    id_rsa|id_rsa[._-]*|id_dsa|id_dsa[._-]*|id_ecdsa|id_ecdsa[._-]*|id_ed25519|id_ed25519[._-]*) rc=0 ;;
    .npmrc|.netrc|_netrc|.pypirc|.git-credentials|.dockercfg|auth.json) rc=0 ;;
    *keystore*.properties|*signing*.properties) rc=0 ;;
    google-services.json|googleservice-info*.plist|*service-account*.json|*service_account*.json) rc=0 ;;
    *secret*|*credential*)
      case "$n" in
        *.swift|*.m|*.mm|*.h|*.c|*.cc|*.cpp|*.hpp|*.php|*.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.py|*.rb) ;;
        *.kt|*.kts|*.java|*.scala|*.go|*.rs|*.cs|*.fs|*.dart|*.ex|*.exs|*.vue|*.svelte|*.twig) ;;
        *.html|*.scss|*.css|*.md|*.markdown|*.rst|*.adoc|*.sh|*.bash|*.zsh|*.awk|*.jq) ;;
        *.storyboard|*.xib|*.strings|*.stringsdict) ;;
        *) rc=0
           case "/$p" in
             */test/*|*/tests/*|*/spec/*|*/specs/*|*/fixtures/*|*/__fixtures__/*|*/testdata/*|*/test-data/*) rc=1 ;;
             */mocks/*|*/__mocks__/*|*Tests/*) rc=1 ;;
           esac ;;
      esac ;;
  esac
  [ -z "$restore" ] || shopt -u nocasematch
  return "$rc"
}
