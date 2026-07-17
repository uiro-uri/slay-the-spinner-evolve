# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

"Slay the Spinner" is a small Flask web game inspired by beyblade-style battles combined with a
roguelike branching map (à la Slay the Spire). The player customizes a spinning "Object" with
physical properties (mass, radius, decay, restitution, rps), walks a branching node map, and fights
enemies in a 2D physics simulation rendered client-side as CSS keyframe animations generated
server-side.

There is no build system, package manifest, or test suite in this repo — it's a single Flask app
with server-rendered Jinja2 templates and vanilla JS/CSS on the frontend.

## Running the app

```bash
pip install flask numpy
python app.py
```

The app runs with Flask's built-in dev server (`debug=True`) on the default port. There is no
`requirements.txt`/`pyproject.toml` — the only third-party dependencies are `flask` and `numpy`.

Set `SECRET_KEY` in the environment for real deployments; it falls back to `'default_secret_key'`
otherwise (see `app.py`).

There are no linting, formatting, or test commands configured in this repo.

## Architecture

### Request flow (game loop)

The game is a state machine driven by Flask `session` and traversed through four routes in
`app.py`, in this order:

1. **`GET /`** (`index`) — title screen.
2. **`GET/POST /map`** (`map`) — renders the branching node map (`MapTree`). POST advances the
   player to a chosen node, spawns an `Enemy` scaled to the current map step
   (`Enemy.get_random_enemy((map_tree.current_step+1) // 2)`), stores it in the session, and
   redirects to `/simulation`.
3. **`GET/POST /simulation`** (`simulation`) — GET shows the pre-battle setup; POST runs the
   physics battle (`simulation.run_simulation`) between the player's `Object` and the enemy's
   `Object`, then renders the animated result. Whoever's rotation speed (`rps`) hits zero first
   loses.
4. **`GET/POST /reward`** (`reward`) — after a win, offers 3 random `CustomPart`s (weighted by
   rarity); POST applies the chosen part to `session['object1']` and redirects back to `/map`.

`GET /reset` clears the session and returns to `/`.

All game state (`object1`, `map_tree`/`map`, `enemy`) is persisted in the Flask session as plain
dicts via each class's `map()`/`from_map()` serialization pair — there is no database. When
deserialization fails (`TypeError`, e.g. stale/incompatible session schema), routes redirect to
`/reset` rather than crash.

### Core domain classes

- **`object.py` — `Object`**: the physical stats of a spinning top (mass, radius, decay,
  restitution, rps). Also defines `Wall`, a static line-segment obstacle used for wall-collision
  physics in the simulation (`detect_collision`, `reflect`). Walls are hardcoded in the
  `/simulation` route, not stored in session.
- **`enemy.py` — `Enemy`**: pairs an `Object` with position/velocity and a `level` (1-5, higher
  level = stronger stats). `ENEMY_LIST` is a hardcoded roster; `get_random_enemy(level)` picks one
  matching the requested level (falls back to a random level if `None`).
- **`custom_part.py` — `CustomPart`**: player-facing upgrades. Each part declares which
  `update_*` method(s) it triggers (`update_mass`, `update_radius`, `update_decay`,
  `update_restitution`, `update_rps`) via matching attribute names set in its constructor kwargs
  (e.g. a part with `mass_value`/`mass_calculation` triggers `update_mass`). `CUSTOM_PARTS_DICT` is
  the hardcoded catalog; `get_random_keys(n)` samples without replacement, weighted by rarity
  (`common`/`rare`). To add a new part, add an entry to `CUSTOM_PARTS_DICT` and, if it needs new
  behavior, a new `update_*` method plus its dispatch entry in `update_methods`.
- **`maptree.py` — `MapTree`**: procedurally generates the branching route the player walks.
  Nodes are keyed by a synthetic id `step*10 + column` (e.g. node `23` = step 2, column 3); each
  node's `arrows_to_next` (`"left"`/`"straight"`/`"right"`) determines which node ids in the next
  step it connects to (`+9`/`+10`/`+11`). `create_map_tree()` retries generation
  (`while not success`) until the random tree satisfies reachability constraints for the
  penultimate step's fixed nodes (81/82/83). Steps are fixed at 0 (start), 1-8 (branching), 9
  (goal).
- **`simulation.py` — `run_simulation`**: the physics core. Steps two objects forward in time
  (`time_step` increments up to `simulation_time`), applying friction (via `decay`), gravity toward
  a fixed origin, elastic object-object collisions (with an extra rotational-speed transfer effect
  scaled by a `violent` constant), and wall collisions/reflection. `rps` (rotation speed) decays
  naturally each tick and drops further on collisions; the first object whose `rps` reaches ~0 loses.
  Returns position histories for both objects (used to build CSS animation keyframes in `app.py`),
  `rps` timelines, stop times, and collision points.

### Frontend

`templates/*.html` are server-rendered Jinja2 templates styled with Bootstrap 5 (via CDN) plus
inline `<style>`/`<script>` blocks — no separate static JS/CSS build. Notable patterns:

- `map.html` renders the node tree as an HTML table computed from `MapTree.map()`, then uses
  inline JS to `fetch()` `POST /map` when the player clicks a reachable node.
- `simulation.html` receives pre-computed CSS `@keyframes` strings (`frames1`/`frames2`, built by
  `generate_keyframes()` in `app.py`) and injects them directly into `<style>` to animate the two
  objects along their simulated trajectories.
- `reward.html` similarly uses `fetch()` to `POST /reward` with the chosen part id.

### Localization

Code comments and some in-app strings are in Japanese; templates/UI copy are primarily in English.
Preserve the existing language of comments/strings you're editing rather than translating wholesale.
