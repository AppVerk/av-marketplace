# Target B Reference

Supporting reference material for the needs-decision end-to-end test
fixture. Linked from target-a.md.

## Emergency Rollback

To perform an emergency rollback, run `scripts/rollback.sh --env production`.
This restores the previous release without requiring a redeploy.

## Report Generation

Nightly reports are generated automatically by running
`scripts/generate-legacy-report.sh`. See the script for CLI flags.
