# Profile: frontend in a backend repo (Node, TypeScript, Tailwind, E2E)

Use it as an add-on when the scan found `package.json` in a subdirectory of a repo with another stack. Example: a `web/` client in a backend repo or `tests/E2E/` with Playwright.

## Detection
- `id: node` from the scan with `dir` other than `.`.
- `frontend_hints`: `tailwindcss`, `typescript`, `vite`, `webpack`, `@playwright/test`.

## Commands and gates
- Asset build: the `build` script from `package.json` in that directory, with the `cwd` field in the config.
- When the build overwrites files tracked by git (e.g. `public/build/`), do not put it in `quick`. It changes the tree, so earlier evidence becomes STALE. Put it in `full` as the last command.
- E2E: a separate `e2e` gate with a `precheck` for a running environment (docker, app server, an API mock like WireMock). `needs` describes how to start it.
- Do not put E2E in `quick`. It takes long and needs an environment.

## Docs
- `frontend.md`: view layout, components, styles, asset build.
- `js-reference.md` or a section in `frontend.md`: TS pages, patterns, helpers.
- `e2e-testing.md`: running, fixtures, API mocks, selectors (`data-testid`).

## Review axes
| Axis | What to check |
|---|---|
| View consistency | the same components and classes as in similar views |
| TS | types, no globals, fetch error handling |
| Accessibility | labels, focus, contrast |
| E2E | stable selectors (`data-testid`), no sleeps |

## Visual verification
When the team compares screens with a reference (Figma, existing views), describe it in the `av-verify.md` overlay: how to take screenshots, where to save them (`<paths.workspace>/screenshots/`), what to compare them with.
