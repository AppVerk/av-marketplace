#!/usr/bin/env bash
# agent_grant.sh - resume a slot executor session with a permission a human approved.
#
# Usage:
#   agent_grant.sh --slot S --run-id ID --resume SESSION --grant G [--grant G ...] [--label L]
#                  [--root DIR] [--prompt-file P] [--dry-run]
# Grants, the session check and the result are those of agent.sh (see agent.sh --help);
# agent.sh itself rejects --resume and --grant.
#
# The human approval is the Claude Code prompt for this command: the plugin hook
# agent_guard.sh never lets this script run without one (in bypassPermissions it denies
# the call, and the human runs it with "!"). Never add this script, or a directory that
# holds it, to an allow rule in the settings.
# Requires: bash 3.2+, git, jq.

set -uo pipefail
# shellcheck source=agent.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/agent.sh"
