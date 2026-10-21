# Writing extensions

An extension is a plugin that builds on an av-marketplace plugin through a contract that plugin publishes. You write it as an ordinary plugin in your own repository and publish it from your own marketplace. Users add your marketplace next to av-marketplace and install from both.

| Plugin | Extension point | Contract | Since |
|---|---|---|---|
| [QA](plugins/qa.md) | Desktop drivers that run DESKTOP scenarios | 1 | qa 3.1.0 |

## Repository layout

One repository can hold both the plugin and the marketplace that publishes it:

```text
my-extension/
├── .claude-plugin/
│   ├── plugin.json        # the plugin manifest
│   └── marketplace.json   # the catalog that lists this plugin
├── skills/
│   └── <skill>/
│       └── SKILL.md
└── README.md
```

Claude Code reads `.claude-plugin/marketplace.json`. OMP reads `.omp-plugin/marketplace.json` when a repository has one and falls back to the Claude path, so one catalog serves both tools.

Claude Code lists a plugin's skills as `<plugin>:<skill>`. OMP lists a skill from your plugin under the `name` in its frontmatter, without a prefix. The av-marketplace OMP editions add a prefix to their own skills at build time; that build does not touch your plugin. A contract that finds skills by name, as QA does for drivers, accepts both forms.

## The plugin manifest

```json
{
  "name": "my-extension",
  "version": "0.1.0",
  "description": "What the extension does and which plugin it extends.",
  "dependencies": ["qa@av-marketplace"]
}
```

`qa@av-marketplace` makes Claude Code resolve `qa` in av-marketplace. A bare `"qa"` is looked up in your own marketplace, where it does not exist. Leave out a version range: Claude Code resolves ranges against `<plugin>--v<version>` git tags, and av-marketplace does not publish them. Put the minimum version of the plugin you extend in your README.

## The marketplace catalog

```json
{
  "name": "my-extension",
  "owner": { "name": "Your Name" },
  "allowCrossMarketplaceDependenciesOn": ["av-marketplace"],
  "plugins": [
    {
      "name": "my-extension",
      "source": "./",
      "description": "What the extension does and which plugin it extends.",
      "version": "0.1.0",
      "category": "testing"
    }
  ]
}
```

`"source": "./"` points at the repository root, where the plugin lives. `allowCrossMarketplaceDependenciesOn` lets Claude Code install a dependency from av-marketplace. Without it, Claude Code installs your plugin and leaves the dependency out, unless the user already has it.

Keep `version` equal to the one in `plugin.json`. When OMP upgrades all plugins, it compares only catalog entries that declare a version, and `claude plugin tag` checks that the two values agree.

## Installation instructions for your README

Users add av-marketplace before installing your plugin. Claude Code installs a dependency only from a marketplace it already knows; without av-marketplace it installs your plugin, warns that `qa` is missing, and your plugin does not load. In Claude Code:

```text
/plugin marketplace add AppVerk/av-marketplace
/plugin marketplace add <owner>/<repo>
/plugin install <plugin>@<your-marketplace>
```

Claude Code installs `qa` along with your plugin. OMP installs only the plugins named on the command line, so its instructions list both:

```sh
omp plugin marketplace add AppVerk/av-marketplace
omp plugin marketplace add <owner>/<repo>
omp plugin install qa@av-marketplace <plugin>@<your-marketplace>
```

## Trying it locally

Both tools accept a local directory as a marketplace, so you can install your working copy before you push it:

```sh
claude plugin marketplace add AppVerk/av-marketplace
claude plugin marketplace add /path/to/my-extension
claude plugin install my-extension@my-extension
```

Claude Code reads a plugin from a local marketplace in place, so an edit takes effect at the next session start or after `/reload-plugins`. For a single session you can also skip the install and start `claude --plugin-dir /path/to/my-extension`. `qa` then has to be installed already, or loaded with a second `--plugin-dir` that points at `plugins/qa` in a clone of av-marketplace (Claude Code 2.1.242 or later matches that local copy to `qa@av-marketplace`).

OMP copies the plugin into its cache when it installs it:

```sh
omp plugin marketplace add AppVerk/av-marketplace
omp plugin marketplace add /path/to/my-extension
omp plugin install qa@av-marketplace my-extension@my-extension
```

After an edit, run `omp plugin install --force my-extension@my-extension` to refresh the copy.

`claude plugin validate --strict .claude-plugin/plugin.json`, `claude plugin validate --strict .claude-plugin/marketplace.json` and `claude plugin validate --strict skills` check the manifest, the catalog and the skills.

## Releasing

Bump `version` in `plugin.json` and in the catalog entry together, along with any version your contract asks for (a QA driver repeats it in its manifest), and tag the commit. OMP compares versions when it looks for updates, so a change shipped under an old version does not reach OMP users who upgrade.

## QA desktop drivers

A desktop driver lets `/qa:run` test a desktop app headless in the background. The QA tester writes a script of input steps. The driver builds the app, runs it without a visible window, feeds it the steps tick by tick and returns PNG frames and the app's log. qa 3.1.0 and later support contract 1.

### How QA finds a driver

A driver plugin ships a skill named `qa-desktop-driver-<driver>`. The skill's directory holds the manifest `qa-desktop-driver.json`, the guide `SKILL.md` (the skill itself) and the driver's code.

`/qa:create-plan` and `/qa:run` list every available skill whose name, after an optional `<plugin>:` prefix, starts with `qa-desktop-driver-`. They load each one and take two absolute paths from it, the manifest and the guide. Write them in `SKILL.md` like this:

```markdown
Driver: <driver> (contract 1)
Driver manifest: ${CLAUDE_SKILL_DIR}/qa-desktop-driver.json
Driver guide: ${CLAUDE_SKILL_DIR}/SKILL.md
```

Claude Code expands `${CLAUDE_SKILL_DIR}`. OMP leaves it as written, and QA then resolves `skill://<name>/qa-desktop-driver.json` and `skill://<name>/SKILL.md` instead, so keep those two file names.

QA registers each driver for the run from its manifest. Registration fails when the manifest sits inside the repository under test, is not a JSON object, has keys other than exactly the four below, names another contract, has an invalid driver name or version, or points `entry` outside its own directory. It also fails when a second manifest claims a driver name that is already registered. An app whose driver is not registered gets `NEED_INFO kind=tool` with `Missing: desktop-driver:<driver>`.

Users choose the driver per app in `.av/config.toml`:

```toml
[qa.desktop.app]
driver = "<driver>"
package = "."
```

[Desktop apps configuration](plugins/qa/configuration.md#desktop-apps) lists the other keys and their defaults.

### The manifest

```json
{"contract": 1, "driver": "<driver>", "version": "0.1.0", "entry": "driver.py"}
```

| Key | Rule |
|---|---|
| `contract` | `1` |
| `driver` | `[a-z][a-z0-9-]{0,39}`, the name users write in `driver = "…"` |
| `version` | `[0-9A-Za-z.+-]{1,40}` |
| `entry` | a relative path without `..` to a Python 3.11+ script inside the manifest's directory that uses only the standard library |

The entry script may start other programs, such as the toolkit's build tool or a separate host process that drives the app.

### Phases

For every DESKTOP script, QA runs `[sys.executable, <entry>, <phase>, …]` for the phases below in order. Each phase runs with the repository root as its working directory and `PWD`, with QA's environment minus every `QA_*` and `STORE_*` variable, with stdin from `/dev/null`, and in its own session. When a phase times out or the run is interrupted, QA sends SIGTERM to the phase's whole process group and SIGKILL 5 seconds later.

| Phase | Arguments | What the driver does | Timeout | Result when it fails |
|---|---|---|---|---|
| `check` | `--repo R` | Says whether the driver can test this repository: exit 0 and print exactly one JSON object, `{"result": null}` when it can, `{"result": "tool-missing", "detail": "<tool>"}` or `{"result": "unsupported", "detail": "<one line>"}` | 60 s | `host-failed` for any other output, a non-zero exit or the timeout |
| `prepare` | `--repo R --cache C` | One-time setup, under the lock `C/.lock`. QA writes `C/.prepared` after a success and skips the phase for the rest of the run | 300 s | `host-build-failed`, with the first line of `C/prepare.log` that is not a comment as the detail |
| `build` | `--repo R --cache C --package P --out G` | Builds the configured `package` `P` into `G` | 300 s | `build-failed`, with the first line of `build.log` as the detail |
| `run` | `--repo R --cache C --guest G --steps S --out A --width W --height H --deadline N -- <args…>` | Starts `G`, executes the steps in `S` and writes `A/result.json`, one PNG per shot and `A/guest.raw.log` with the app's stdout and stderr; stops the app and itself after `N` seconds | 120 s, with `N` = 135 | `timeout`; `host-failed` when `result.json` is missing or breaks the schema. `handshake-failed` is retried once |

`C` is a cache directory QA keeps per run and driver, and `A` holds the run's artifacts. QA keeps `check`'s stderr and everything the other phases print in logs. A failed `prepare` or `build` reports the first line of its log as the detail, so print the cause first. Write nothing to the repository: keep build output in `G` and scratch files in `C`.

### The steps file

`S` holds `{"steps": [...]}`. Each step is an object with exactly one action:

| Step | What the driver does |
|---|---|
| `{"wait": N}` | advances N ticks |
| `{"key": "<Key>", "ticks": T}` | presses the key, advances T ticks (default 2), releases it, advances 1 tick |
| `{"hold": "<Key>"}` / `{"release": "<Key>"}` | presses or releases the key; it takes effect at the next advanced tick |
| `{"type": "<text>"}` | types each character and advances 1 tick after it |
| `{"move": [x, y]}` | moves the cursor |
| `{"click": [x, y], "button": "left"}` | moves, presses, advances 1 tick, releases, advances 1 tick; `button` is `left` (the default), `right` or `middle` |
| `{"scroll": [dx, dy]}` | scrolls the wheel and advances 1 tick |
| `{"shot": "<name>"}` | renders the current frame to `A/<name>.png` |

QA validates the script before the driver sees it, including step and tick limits, shot names and coordinates. It also replaces every `type_env` step with a `type` step in the driver's private copy, so the driver never sees that action. Keys are W3C `KeyboardEvent.code` values such as `KeyA`, `Digit1` and `Enter`; the driver checks them and reports an unknown one as `invalid-script`, with that step's index in `step`. Coordinates are window pixels of the `W`×`H` screen from `--width` and `--height`. The arguments after `--` are the configured app arguments followed by the scenario's own. Pass them to the app unchanged, without a shell.

### result.json

`run` writes one JSON object with at least these keys. QA ignores other keys, and an integer field never accepts a boolean.

| Key | Value |
|---|---|
| `result` | one of the results below |
| `detail` | string or null |
| `step` | index of the step the result refers to, or null |
| `exit_code` | the app's exit code, or null |
| `ticks` | ticks advanced |
| `tps` | ticks per second the app asked for; -1 when its ticks follow rendered frames |
| `scale` | PNG pixels per window pixel, or null |
| `screen` | `[width, height]` |
| `shots` | a list of `{"name", "file": "<name>.png", "tick"}`; every file must exist in `A` |

The `result` values:

- `completed`: every step ran and the app did not fail, after which the driver stopped it. An exit with code 0 after the last step also counts.
- `guest-exited` with `exit_code` 0 and the detail `guest terminated itself`: the app quit through its toolkit's normal quit path while the steps ran. Report an intentional quit this way and no other.
- Any other `guest-exited`: the app crashed, exited with a non-zero code, ended with an error or exited before the driver connected. `detail` says which, for example `guest exited 3 before connecting`, and `exit_code` is set when known.
- `handshake-failed`: the app started, but the driver could not connect to it. QA retries once.
- `host-failed`: the driver itself failed.
- `invalid-script`: the driver rejected the step in `step`.
- `timeout`: the driver's own deadline or no-progress limit ended the run.

### The guide

QA's planner, config-author and tester read the driver's `SKILL.md`. The tester relies on it for the app's tick rate, for how the app's drawing coordinates map to window pixels and for the driver's limits. The guide should also tell the config-author how to recognise an app the driver can run, which `package` to propose and which flags belong in `args`, and list the key codes the driver accepts and the tools it needs on `PATH`.

### Testing a driver

Test the entry script with the standard library's `unittest`. For an end-to-end check, install the driver, configure an app in a sample repository with `driver = "<driver>"`, and run `/qa:run` with a DESKTOP scenario. [Desktop apps](plugins/qa.md#desktop-apps) in the QA guide has an example scenario to adapt.

## Official extensions

An official AppVerk extension also lives in its own repository, but av-marketplace lists it in its catalog, so users install it with `@av-marketplace`. Maintainers register one as `CLAUDE.md` describes under "Marketplace registration". No official extension exists yet.
