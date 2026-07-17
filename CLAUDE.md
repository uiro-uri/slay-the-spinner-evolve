# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository.

## Project overview

"Slay the Spinner" is a Beyblade-style battler crossed with a Slay-the-Spire-style branching map
and rarity-weighted roguelike upgrades. Two spinning tops collide in a sloped stadium; whoever's
rotation speed (`rps`) runs out first loses.

The game is being **rebuilt in Godot 4** targeting browser (HTML5 export) and Steam (native
export). The Godot project lives in `godot/`.

`archive/flask-prototype/` holds the original Flask implementation. **It is frozen reference
only — do not extend it.** It validated the game design, but it computed physics server-side per
HTTP request and replayed the result as CSS `@keyframes`, which is not a real-time client game and
cannot ship to a browser or Steam.

## Working on the Godot project

Godot 4.x is required; the same binary is both the editor and the headless CLI.

```bash
scripts/verify.sh           # everything (see below)
scripts/verify.sh --quick   # skip the rendering checks
```

**Do not launch the Godot editor with sudo.** It makes `godot/.godot/` root-owned, after which
imports fail with permission errors, `.import` files get rewritten to `valid=false`, and you
silently get builds with the font and translations missing. Recover with
`sudo rm -rf godot/.godot`. `verify.sh` stage 0 detects this.

### Verification

Exit codes are not trusted here — a build with the font and translations missing exited 0. Each
stage of `scripts/verify.sh` has a substantive pass criterion:

| Stage | Criterion |
|---|---|
| 0. preflight | `godot/.godot` is ours and writable (the sudo accident above) |
| 1. import ×2 | the **2nd** run has no errors (the 1st legitimately errors: `.translation` files and the font aren't generated yet at boot) |
| 2. tests | exit code **and** the completed-test count — a GDScript runtime error aborts a function without failing the run |
| 3. headless run | no errors from `--quit-after` |
| 4. export ×3 | exit code, a `.pck` size floor, **and** that the Web preset's `variant/thread_support` is off — enabling it makes Godot demand SharedArrayBuffer, which needs COOP/COEP headers that GitHub Pages cannot serve, so the game would break in production only |
| 5. native render | launch the **exported** Linux binary, capture via `--write-movie`, assert non-blank |
| 6. web render | Chromium on the served export: no JS errors, canvas non-blank |

Stage 5 deliberately runs `build/linux/slay-the-spinner.x86_64`, not `--path godot`. Running the
project only proves the editor can play it from source; a broken binary/pck pairing would sail
through. What ships is the export, so the export is what gets launched.

Stages 5 and 6 leave `build/verify/native.png` and `build/verify/web.png` to eyeball.

Tests live in `godot/tests/`; `run_tests.gd` is the entry point. When adding a test suite, add its
name to `EXPECTED_TESTS` — the runner cross-checks that every suite ran to completion, because a
GDScript runtime error silently aborts just that function and would otherwise report success.

### Architecture

State flows through an autoload singleton and scene swaps, replacing the prototype's Flask session
and routes:

- **`autoloads/GameState.gd`** — one run's state (player stats, map tree, pending enemy, acquired
  parts). In-memory only; no save/resume, matching the prototype's session dying on restart.
- **`scenes/main/Main.gd`** — swaps screens under `ScreenHolder` and owns all routing decisions.
  Screens emit signals about what happened; they never decide where to go next.
- **`scenes/title/`**, **`scenes/map/`**, **`scenes/battle/`** — the screens.
- **`scripts/core/spinner_physics.gd`** — the physics, as pure static functions with no Node or
  scene dependency, so headless tests call them directly.
- **`scripts/core/spinner_stats.gd`** — `SpinnerStats`: mass, radius, friction, restitution, rps.
- **`scripts/data/map_tree.gd`** — branching map generation, keyed by `Vector2i(step, column)`.
- **`scripts/data/enemy_roster.gd`** — enemy table and which level appears at which step.

### Physics: it is deliberately fake

**Conservation laws do not hold system-wide and must not be treated as design constraints.**
`spin_kick` converts rotation into linear motion, so energy increases. The momentum/energy tests
exist only to check that the *elastic-collision formula itself* was written correctly — they are
not laws the game must satisfy. If tuning wants an inelastic collision, change the test.

The force pulling tops toward the center is **the stadium's slope**, not gravity and not a spring.
`StageShape.DISH` (linear in displacement) is a parabolic bowl; `StageShape.CONE` is a constant
slope. Both are selectable because which one feels right is an open question.

**Do not attempt numerical comparison against `archive/flask-prototype/simulation.py`.** `Vector2`
components are 32-bit while GDScript's `float` and numpy are 64-bit, and collisions amplify the
divergence exponentially — exact agreement is impossible and chasing it builds a test that can
never go green. The prototype's *numbers* are discarded outright; only the shape of the formulas
carried over. Tuning is judged by feel, and every tunable is an `@export` so it can be changed in
the Inspector.

Tests therefore assert direction, monotonicity, and other value-independent properties that survive
tuning. Map generation is tested by generating many maps and checking invariants (no dead ends, no
dangling arrows, no orphans, no crossing arrows), with a seedable RNG so a failure is reproducible.

### Localization

Bilingual (Japanese/English) from the start. All UI strings are keys resolved through
`godot/translations/strings.csv`; `Control` nodes auto-translate their `text`. A missing key renders
as the key itself, which is how you spot gaps.

The bundled Noto Sans JP is load-bearing: Godot's default font has no CJK glyphs and Japanese
renders as tofu (□). `run_tests.gd` asserts the default font actually has Japanese glyphs, because
the `.pck` size check does not catch this (the font ships regardless of whether it's referenced).

Comments and commit messages are in Japanese. Keep the existing language of what you edit.

**Do not put explanatory comments in `godot/project.godot`** — Godot regenerates the file whenever
settings are written and strips them.

## Shipping

The web build deploys to GitHub Pages from `main` via `.github/workflows/pages.yml`, gated on
`scripts/verify.sh` going green — the same script, not a CI-only reimplementation.

For Steam, see `docs/steam.md`. GodotSteam is deliberately **not** vendored yet — without an App ID it cannot
initialize, so it would be an untestable 50MB+ binary in the repo. When it goes in, every Steam call
must sit behind an availability guard: the same codebase ships to browser (no Steam API), native
without Steam, and native under Steam.

## Conventions

- Build output goes to `build/` at the repo root, deliberately outside `godot/`. Inside it, Godot
  rescans the exported PNGs as project resources.
- Commit `export_presets.cfg` and `.import` files; `.godot/`, `build/`, and `*.translation` are
  generated.
