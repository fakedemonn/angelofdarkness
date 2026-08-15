# AutoParry

Game-agnostic animation-driven auto parry for Roblox, with an animation
visualizer, an info logger, and a per-place timing database that writes to disk
the moment a timing is created.

Written as feature modules under `src/`, with a one-file build for convenience.

---

## Loading

Single file — nothing to configure:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/fakedemonn/roblox-autoparry/main/AutoParry.lua"))()
```

Or the modular build, which pulls each module out of `src/` at runtime:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/fakedemonn/roblox-autoparry/main/init.lua"))()
```

Both run the same code. Edit `USER` / `REPO` / `BRANCH` at the top of `init.lua`
if you rename the repo.

Menu keybind is `End`.

### Repo layout

```
init.lua                    module loader - fetches src/ in dependency order
build.js                    node build.js -> regenerates AutoParry.lua
AutoParry.lua               generated single-file build, do not edit
src/
  core/
    Config.lua              version, folder paths, services
    FS.lua                  executor filesystem shims + nested folder walker
    Util.lua                round, shortId, distance, facing, alive
    Input.lua               VirtualInputManager / keypress backends
    Latency.lua             round trip time
    State.lua               counters and the single "may we parry" gate
    Notify.lua              one notification entry point
  features/
    Store.lua               the timing database
    Log.lua                 info logger data + speed-curve recorder
    Entities.lua            where combat characters live, and who is a target
    Engine.lua              scheduling, hitbox gate, the parry itself
    Hooks.lua               Animator.AnimationPlayed listeners
  ui/
    Library.lua             LinoriaLib, window, tabs
    MainTab.lua             tab 1
    BuilderTab.lua          tab 2
    LoggerWindow.lua        Info Logger window
    VisualizerWindow.lua    Animation Visualizer & Editor window
    Wiring.lua              connects builder controls to the store
    Settings.lua            tab 3, themes and UI configs
  Runtime.lua               watermark, render loop, stats loop, unload
  Boot.lua                  folder setup, autoload, first animator sweep
README.md
```

Every module is `return function(ctx) ... end`. The loader builds one shared
context table, runs each module against it in dependency order, and each module
publishes what it exports onto `ctx` (`ctx.Store`, `ctx.Engine`, ...). No
globals, no shared upvalues — you can read any one file on its own.

Modules that load before `ui/Library.lua` read `ctx.Toggles` / `ctx.Options`
**inside** their functions rather than capturing them at load time, because the
UI does not exist yet when they run.

`src/` is the source of truth. `AutoParry.lua` is generated — after editing a
module, run `node build.js` to regenerate it.

### Requirements

- An executor with `writefile` / `readfile` / `isfile` / `isfolder` / `makefolder` / `listfiles`
- `VirtualInputManager`, or the `keypress` / `keyrelease` globals

If either is missing the script still loads and tells you which half is dead —
no filesystem means timings do not persist, no input backend means parry cannot
fire.

---

## How it works

Every `Animator` inside the configured container gets its `AnimationPlayed`
signal hooked. When a track starts:

1. The `AnimationId` is looked up in the timing database for this `PlaceId`.
2. Unknown IDs get a stub created from the track length and **written to disk immediately**.
3. Known and enabled IDs schedule a parry keypress.

The scheduling maths is the part that matters:

```
wait = (delay / 1000) - (RTT * compensation) - offset + jitter
```

The attacker's animation started roughly one one-way-delay ago, and your
keypress needs another one-way-delay to reach the server. Subtracting the full
round trip time puts the input on the server at the moment the hit lands. Ping
compensation is exposed as a percentage so you can back it off on unstable
connections.

Everything is revalidated at fire time — target still alive, animation still
playing, still in range — because a lot can change during a wind-up.

---

## Building timings

The intended loop is build-as-you-play:

1. **Builder** tab, turn on **Show Logger Window**.
2. Fight something. Every animation lands in the logger as
   `Time | Animation | ID | Enemy | Dist | Status`.
3. Click any row. That opens the visualizer, loads the rig, and fills the
   **Quick Edit Timing** panel.
4. Tune the numbers, hit **Save & Apply**, then **Add To Parry List**.

### Info Logger

| Status | Meaning |
|---|---|
| `NEW` | never seen, no timing saved |
| `KNOWN` | timing saved but not enabled |
| `IN AP` | timing saved **and** live on the parry list |

Status is read from the database every refresh, not cached on the row — so a
row logged as `NEW` flips to `IN AP` the moment you save a timing for it,
without having to re-trigger the animation. The whole row is tinted to match,
so a screen full of entries reads at a glance.

**Clear** empties the list. **Auto Create Timings** on the Builder tab makes a
stub for each new animation at 60% of the animation length, and **Save On
Create** flushes it to disk immediately. Stubs arrive **disabled** so a batch of
untuned guesses does not start parrying at random.

### Animation Visualizer & Editor

The viewport clones the attacking rig and replays the animation at the speed it
was actually played at you, not at 1x — which matters when the attacker has any
kind of speed modifier. If the original rig has despawned it falls back to
another live rig, then to your own character; the skeleton is what matters.

Controls: `Play` / `Pause`, `<<` and `>>` step one hundredth of a second, the
scrub bar is draggable, and **From Log** reloads the selected row. The red
vertical line on the scrub bar marks your current delay, so you can line it up
against the frame the hit actually connects. Readout is
`position / length (delay ms)`.

**Quick Edit Timing** writes straight into the database:

| Field | Meaning |
|---|---|
| Delay (s) | When the hit lands, from animation start. Stored as ms |
| Hitbox X / Y / Z | Box measured in the **attacker's** local space — X is their right, Z is forward |
| HSO | Hitbox size offset: studs added to every axis before the check |
| Max Dist | Hard distance cut-off, checked before the hitbox |
| Repeat | How many parries to fire, for multi-hit attacks |
| Rep Delay | Seconds between those repeats |
| Dodge Dir | Movement key held across the parry (`None` / Left / Right / Back / Forward) |

The hitbox is why there are three numbers instead of one radius: a wide
horizontal sweep and a narrow forward thrust have very different shapes, and
one distance value cannot describe both without false-firing on the other.

**Save & Apply** writes the fields and keeps the enabled flag as-is.
**Add To Parry List** / **Remove From Parry List** flips it. The label bottom-left
tells you which state you are in.

---

## Storage

```
AutoParry/
  timings/
    <PlaceId>/
      default.json           <- your timing database
      <other configs>.json
  settings/
    <PlaceId>/               <- LinoriaLib UI config (sliders, toggles)
  themes/                    <- LinoriaLib themes
```

Timings and UI settings are deliberately separate trees: the timing database is
the thing you actually build up over hours of play, and it should not be sat
next to files that a theme change can rewrite.

One database per place, so a build for one game never bleeds into another.
`default.json` autoloads if present. Folders are created segment by segment,
because plenty of executors will not create intermediate directories for you.

The JSON is plain and hand-editable:

```json
{
  "version": "1.0.0",
  "placeId": 4111023553,
  "timings": {
    "rbxassetid://12345678": {
      "id": "rbxassetid://12345678",
      "name": "Bounder",
      "delay": 420,
      "length": 0.7,
      "minDistance": 0,
      "maxDistance": 85,
      "holdTime": 120,
      "enabled": true,
      "ignoreEnd": false,
      "note": "",
      "hitbox": { "X": 11, "Y": 10, "Z": 30.5 },
      "hso": 3,
      "repeatCount": 1,
      "repeatDelay": 0.35,
      "dodgeDir": "None"
    }
  }
}
```

Configs saved by an older build load fine — missing fields get backfilled from
the template on load, so upgrading never means rebuilding a database by hand.

`ignoreEnd` has no UI toggle — set it in the JSON for attacks whose animation
stops before the hit lands, and the fire-time "is it still playing" check gets
skipped for that timing.

---

## Options

**Main tab**

| Option | What it does |
|---|---|
| Parry Key | Key sent to parry. Default `F` |
| Hold Time | How long the key is held |
| Ping Compensation | Percent of RTT subtracted from the delay |
| Manual Offset | Positive parries earlier, negative later |
| Cooldown | Minimum gap between two parries |
| Entity Source | `Auto` checks Live, Characters, Enemies, Mobs, NPCs then falls back to workspace |
| Only When Targeted | Requires an `ObjectValue` named `Target` on the entity pointing at you |
| Require Facing | Dot product gate on the attacker's look vector |
| Skip If Key Held | Does not fight your own manual input |
| Randomise Offset | Jitter so every parry is not frame-identical |
| Miss Chance | Chance to intentionally drop a parry |

---

## Notes

- `Entity Source` set to `Custom` uses the **Folder Name** input. That input is
  not inside a dependency box on purpose — LinoriaLib's `Depbox:Update` only
  evaluates dependencies whose element type is `Toggle`, so a dropdown
  dependency would never hide anything.
- The parry is a keypress, not a remote call. Remote-level parrying is possible
  but needs per-game reverse engineering of the remote names and argument
  shapes; this script does not guess at them.
- Re-sweeps animators on respawn and whenever you change the entity source.
