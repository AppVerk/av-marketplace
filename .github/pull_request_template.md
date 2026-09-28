## Type of change

- [ ] Bug fix
- [ ] New feature / enhancement
- [ ] New plugin
- [ ] Documentation
- [ ] Other

## Description

<!-- What changed and why? -->

## Testing

<!-- How did you test this with Claude Code? Which project types did you test against? -->

## Checklist

- [ ] Follows existing plugin patterns and conventions
- [ ] Tested with Claude Code on a real project
- [ ] Version bumped in `plugin.json` (if modifying an existing plugin)
- [ ] OMP edition regenerated with `python3 scripts/build_omp_edition.py` and committed (if a plugin with an `omp/overlay/` entry, anything under `omp/`, or the generator changed)
- [ ] Delivery tests pass: `python3 omp/native/delivery/tests/test_route_task.py` and `bun test tests/delivery.test.ts` in `omp/native/delivery/` (if `omp/native/delivery/` changed)
- [ ] Plan review tests pass: `bun test tests/plan-review.test.ts` in `omp/native/plan-review/` (if `omp/native/plan-review/` changed)
- [ ] Claude hooks tests pass: `bun test` in `omp/claude-hooks/` (if `omp/claude-hooks/` or the hooks or scripts of a plugin with an OMP edition changed)
- [ ] No unrelated changes included
