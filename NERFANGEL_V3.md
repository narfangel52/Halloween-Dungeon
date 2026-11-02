# Nerfangel Hub V3.5 — BETA

Preserves the existing v2 files. V3 is a separate experimental release, not a verified Dark Dungeon automation.

## Features
- Nerfangel branding; Portuguese interface; v2 statistics, limits, collection and sale controls.
- Separate Halloween and Dark profiles. Dark is an experimental structural adapter, with 10 rooms as a provisional profile.
- Stop all automations; configurable combat pause below a health threshold (does not heal); timeout without confirmed progress.
- Read-only diagnostic report printed to F9 and optionally copied to clipboard. No report upload.

## Dark Dungeon: first test
1. Join the Dark Dungeon manually and wait for the interior to load.
2. Select Dark Dungeon — BETA in the hub.
3. Open Nerfangel > Verificar estrutura Dark (sem iniciar).
4. If incompatible, use Gerar e copiar diagnóstico and provide the report for adaptation.
5. If compatible, test Speedrun with automatic replay OFF first. Structural compatibility does not establish gameplay correctness.

The user's in-game report established Workspace.DungeonRuns.D1_6620b3.01_Room3 and ReplicatedStorage.Dungeon_Engine.Remotes.Scene. V3.1 detects numbered rooms under DungeonRuns, chooses the run under the player's floor raycast (or exactly one nearby run), and binds Dungeon_Engine. It no longer requires Halloween's 01_StartingRoom or an Aggressors subfolder. Dark NPC searches use descendants of Animal_Live and restrict targets with a floor raycast into the bound run. Room inference uses the numbered ancestor of the floor beneath the player.

Door names and orientation, NPC Health attributes, loot folder behavior, and replay semantics remain unverified live. The diagnostic now prioritizes direct rooms, door/gate parts, prompts, NPC hierarchy and attributes. No arbitrary Request payload was invented or emitted. Entry remains manual. Both structural tests with observed names and isolated party-selection tests passed; no claim of a successful live clear.

## Research, 2026-10-31
Reviewed GitHub code search and repository metadata, ScriptBlox, Delta Scripts, and public game/community references. No well-rated, reviewable open-source Dark implementation was found in the searches performed. This is not an exhaustive statement about all repositories.

- [Lyrancy/polyloot-speedrun](https://github.com/Lyrancy/polyloot-speedrun): readable Halloween base; inspected README explicitly targets 18 Halloween rooms. 0 stars and 0 forks at inspection.
- [cosxdeced-bot/kaw0rufree](https://github.com/cosxdeced-bot/kaw0rufree): 0 stars and 0 forks at inspection; inspected files are obfuscated. Not imported or executed.
- [ScriptBlox LumaCore listing](https://scriptblox.com/script/EVENT-Poly-Loot-Lumacore-Autofarm-Halloween-Event-232139): Halloween beta described, external key loader, no work-status reports at inspection. Not imported.
- [Delta Scripts listing](https://delta-scripts.org/scripts/poly-loot-script-map-sweep-collectibles-resources-keyless/): map discovery, 0 likes at inspection; no Dark clear implementation established.
- [Official game](https://www.roblox.com/games/124032631078772/Poly-Loot).
- [Community Dark overview](https://polylootwiki.site/worlds/poly-loot-dark-dungeon/): describes 10 rooms, Voodoo Doll and level 150, attributed to developer announcements; not independently verified live.

## Validation
Luau syntax parsed; scoped GUI predicate and candidate detection exercised in an isolated Lua runtime with mocked objects. This does not test Roblox behavior. No external script was executed during research. No claim of successful Dark runs, boss kills or replay.

Original gameplay base attribution remains in source. Changes made under the user's stated authorization.


## V3.2: observed current-room exit groups
The latest user report shows 02_Room4.Door.DoorWood/DoorMetal/DoorMetal2/DoorBolts with CanCollide=false, while DoorFAKE, EntrySeal and trim stay collidable. V3.2 selects only the exact current-room Door group, requires all its physical pieces to be non-collidable, crosses gradually perpendicular to the door plane with floor checks and waits for progress confirmation. It does not disable collision on fake/closed doors.

Observed Scene events room {index,total,waves}, wave {room,wave,waves}, cleared {room,total}, unlock {room,final,yaw} and slam now update progress. A server-provided room index takes priority over inferred floor room. Dark targets must be over the current room, avoiding premature teleport to later-room enemies. Combat logic is otherwise preserved, with new target/weapon/enabled/HP/horizontal-distance/height/attack-count/no-damage telemetry.

Tests: isolated Door-group tests reject fake doors, closed pieces and the final room; actual extracted Scene-state branch tested against observed payloads; Luau syntax parsed. Live traversal and the reported damage failure still require user verification. A cleared server event does not establish who caused the damage.


## V3.3: align, then walk
Per user feedback, replaces the diagonal approach glide with a teleport to the current-room side of the doorway, followed by Humanoid:MoveTo straight through. Prefers the stationary DoorThreshold anchor, falling back to DoorWood. Checks floor on both endpoints and the current room at the approach point, validates accepted alignment and stops blocked walking. Combat code unchanged. Isolated geometry tested for four orientations and both player sides; no live traversal test claimed.


## V3.4: approach entirely on foot
User reported snapback immediately after the doorway-alignment teleport. Cause not proven. Removes all PivotTo/CFrame/velocity writes from Dark door traversal. Uses PathfindingService to reach the current-room alignment point, then ordinary Humanoid walking straight across. Two approach plans maximum, 30-second approach budget, per-waypoint timeouts, blocked-movement detection and three-second retry cooldown. Rejects approaches with waypoints outside the current room. Combat untouched. Isolated mocks cover successful navigation, wrong-room/closed-door/NoPath/cancellation and blocked navigation; live walking still requires verification.

Reference: https://create.roblox.com/docs/characters/pathfinding


## V3.5: temporary door walking speed
Adds Nerfangel-tab slider 16–40 studs/s, default 24, applied during Dark approach/crossing only. Does not slow a character already faster. Restores the original speed on completion, cancellation and exceptions, except if the game changed the speed meanwhile. Does not force speed repeatedly when the game overrides it. Combat unchanged. Mock tests cover success, failure, cancellation and game-side changes; live speed behavior still requires testing.


## V3.6: recover doorway approach after loot
When PathfindingService returns NoPath or no waypoints, tries bounded alternative walking routes: direct, through the position saved before collecting, and two axis-aligned routes. Recovery points must belong to the same run and room and be younger than 90 seconds. Each segment requires sampled floor in the current room and a clear collidable-body Blockcast; revalidates before walking. Existing cancellation, movement timeouts, open-door checks and speed restoration remain. Does not teleport to the doorway. Combat unchanged.

Validation: full Luau syntax parse; isolated route selection tests for direct/recovery paths, blocked routes, stale recovery points and different room/run; source comparison confirms combat unchanged. Actual post-loot traversal still requires Roblox testing.


## V3.16: world-farm controls and grounded combat recovery
Default regional step observation is 0.25 seconds based on user testing; slider remains 0.1–1.2. Main-world selection/status controls translated, with live target HP, horizontal distance, vertical difference and observed defeats per farm minute. After six seconds without an observed HP reduction and at least three attack requests (or a vertical gap above eight studs), optional recovery attempts the opposite side, then lateral ground points. Requires walkable floor, clear landing, proximity, current character/session/target, and eight seconds between attempts. Successful repositioning starts a recovery grace period without falsifying the last real HP-change timestamp. Target stays pinned. Stop now cancels outstanding Humanoid walking. Despawn alone is no longer counted as a defeat; observed zero-health targets are deduplicated.

Review scope: full-source Luau syntax analysis and targeted review of UI, lifecycle, regional selection/travel, combat/loot and counters. Dungeon movement/combat and regional selection compared unchanged. Isolated execution covered actual recovery helper for success, occupied ground, cooldown, cancellation and rollback, plus observed-death counting. This is not a live Roblox or exhaustive end-to-end test; no guarantee of server acceptance, kills or exact earned XP. Credits retained.


## V3.17: audit fixes, regional detours and hub grouping
Regional movement now plans PathfindingService waypoints as fallback when direct landing selection fails or a close-range wall blocks the final approach. Waypoints guide existing short checked teleports; the controller does not walk the route. Lateral/temporarily non-greedy movement is allowed along the planned route. Cache expires after 15 seconds, invalidates for character/target changes and moved targets, and validates landing, region bounds and session after planning. Keeps the same live target; NoPath still pauses/retries rather than guaranteeing traversal.

Main-world tab grouped into selection, execution/movement, status, loot, mapping and bosses. Farm/boss switches moved into their sections. Default pacing remains 0.25 seconds.

Audit corrections: independent Aggressors provider for single-target farm, post-yield cancellation checks in shared approach/collection/combat, cancellation generation for manual and automatic sale batches, weak notification/drop attempt tables, replaced scene cleanup subscription, asynchronous guarded sale-module loading with timed child waits, and exclusion of sale candidates when quest reservation data is unknown. Stop-all reflects auto-sell toggle state. A sent sale request cannot be undone. UI core loading still depends on external OasisUI; require itself can yield inside isolated sale initialization.

Validation: current full-source Luau syntax; reproduced old failures now reject extra teleports/prompt dispatch, abort remaining manual sale requests, and find world NPCs independently of Dark selection. Extracted route tests cover lateral detour, bounded steps, blocked landing, NoPath and cancellation. Integrated mocked wall traversal completed with two short steps. Missing sale dependency and unknown quest-state paths tested; 1000 temporary notification entries released. Existing dungeon navigation/combat compared unchanged. No live Roblox or visual hub test; actual map routing, dependency schema and Toggle UI behavior require in-game verification.


## V3.18: selected two-spawn mode
Optional mode restricts regional farm to two captured spawn markers of the selected species and area. Capture nearest mapped marker within 65 horizontal studs; reject duplicate markers, missing stable marker IDs and pairs farther than 600 studs. Changing area/species clears captures. Starting requires both captures; region rotation is enabled automatically and boss farming is unavailable in this mode. Prefer the other point after an observed defeat if both are alive; otherwise use the one available or wait for respawn. Strict NPC spawn-marker matching prevents unrelated nearby NPCs being acquired; captures last for the current script execution only. Clear/recapture stops enemy farming first.

Validation: full Luau parse; actual capture and selector functions mocked for duplicate rejection, distinct second capture, preservation after failed capture, exclusion of unselected closer NPC, living-target retention, both dead, new NPC instance with same marker, alternating preference and unknown marker rejection. Regional mode retained. V3.17 cancellation, sale, dependency, weak-registration and detour tests rerun successfully. Dungeon and movement helpers unchanged; in-game spawn mapping and new controls require user testing.


## V3.19: Infinite Tower BETA
Separate Tower tab using paths observed in the user's TowerRunV5 probe. Manual tower entry, automatic combat within the loaded TowerRuns arena, stable living-target retention, checked ground/landing and a 0.25-second post-move confirmation. Repositions after six seconds without observed damage. Reads variable wave counts from Tower_Engine.Remotes.Push; boss floors are multiples of five floors. Listens to server events without guessing RemoteEvent request payloads.

Advances only from the visible CLEARED result and exact NEXT FLOOR button/label, then confirms the exact READY button/label on the next intro. One dispatch per run/floor/screen; explicit manual retry control. Empty enemy lists never trigger advancement. Optional bounded end-of-floor collection, floor stop limit, progress and completed-floor counter. Stops on defeat, death, leaving tower or starting another farm; brief HUD replacement has a five-second grace. Existing dungeon and world algorithms retained, with mutual-exclusion hooks and Tower diagnostic lines. Replay floors may grant no rewards, drops or XP.

Validation: full-source Luau syntax parse and mocked execution of actual controller functions for exact UI paths, hidden UI, label guards, duplicate-click suppression, variable waves, stale-run rejection, duplicate intro, no-enemy waiting, completed-floor count, HUD grace and floor limit. Source read back after publishing. No live Roblox/executor test: movement, combat range, arena detection, loot and input compatibility require user testing.


## V3.20: Tower pair selection and optional aerial combat
User observer showed typical eight-stud vertical separation, downward facing and Greatsword x0.25 versus Crab Hammer x1 on floor 86. This observation does not reveal kill-aura implementation, establish multiple simultaneous hits or prove damage immunity.

Automatic weapon comparison restricted to owned Crab Hammer and Halloween/Pumpkin Greatsword Tools available in Character/Backpack. During first combat each floor, briefly equips both, waits 0.45 s per tool and reads visible TowerRunV5.Bar.Held.Mult. Chooses higher multiplier; retains original on equal bonuses. Missing/hidden readings restore original and defer retry; no base-damage/DPS comparison or guessed weapon classes. Does not materialize inventory items that are absent as Tools.

Optional aerial mode defaults OFF, height 4–12 (default 8). Uses owned one-attachment AlignPosition and AlignOrientation objects, bounded speed/force, clear landing-volume check and downward-facing orientation. Tracks the selected live Tower arena target; standard Tool:Activate attack only. Releases on no target, blocked clearance, phase exit, death, stop or unload, restoring captured AutoRotate/PlatformStand flags. No custom server attack calls or unknown third-party kill aura reproduced. Tower diagnostic includes aerial setting, height and weapon comparison.

Validation: full Luau parse; prior Tower UI/state mocked tests rerun; actual pair-selection functions tested for multiplier changes in both directions, per-floor cache, tie, missing readings and cancellation while equipping. Actual aerial tracker mocked for one-time owned object creation, target height, downward facing, repeated updates, blocked-volume cleanup and original humanoid flag restoration. Non-Tower code unchanged except version and diagnostics. Published source read back exactly. Real combat reach, flight stability and HUD update latency require Roblox testing.


## V3.21: Tower obstacles, target-facing flight and attack cadence
Aerial height defaults to 10 based on user testing. AlignOrientation now aims from the actual root position toward the current NPC, with a stable alternate up vector near vertical, rather than pointing vertically down throughout approach. Optional obstacle traversal defaults ON only while aerial combat is active: captures each character BasePart's original CanCollide, handles newly equipped and removed parts, reasserts noncollision before physics and restores original booleans/disconnects on release, phase exit, cancellation, stop or character change. Only local character parts are modified; world geometry remains unchanged. Noclip permits hovering at a point whose clearance overlaps a pillar. Stopping while overlapping geometry still requires in-game testing.

Optional continuous-attack mode defaults OFF; configurable 0.15–0.65-second requests (default 0.25). Retains Tool.Enabled, range, live target, current combat phase and cancellation guards. Uses Tool:Activate only and honors exposed positive numeric AttackCooldown/SwingCooldown/Cooldown up to ten seconds. No invented attack remote, multiple-target damage promise or cooldown bypass. Normal mode keeps existing cadence. Arena bounding boxes cached for one second with arena identity invalidation; weapon status text only written on change.

Validation: full Luau parse; Tower UI/wave/click/floor tests, paired-weapon and aerial tracker tests rerun. Actual noclip functions mocked for initial true/false flags, physics reassertion, new/removed parts, disconnection and cancellation restoration. Attack interval tests cover normal, continuous and exposed cooldown floors. Arena tests cover reuse, rejection outside bounds and replacement invalidation. Published source read back exactly. Pillar traversal, aiming, server-accepted attack frequency and safe collision restoration require Roblox verification.


## V3.22: hotbar equip fallback, Pumpkin preference, aerial teleport and proximity aura
User V3.20 report showed one or both weapons absent as Character/Backpack Tools. Tower now reads Data_Client.PlayerData read-only with a bounded replica wait, maps verified Inventory.Weapons item Id and serial through Hotbar slots, sends a matching number key only if needed, always releases it and confirms the actual equipped weapon identity. No guessed/default slot, purchase or equip RemoteEvent. Focused text boxes block fallback input. Existing loaded Tools still use Humanoid:EquipTool. If hotbar schema/virtual keyboard is unavailable, diagnostics explain the pending equip rather than claiming success.

Updated selection: Crab Hammer only if its confirmed multiplier exceeds x1 and the Pumpkin multiplier. No bonuses, ties or incomplete comparison prefer Halloween/Pumpkin Greatsword. This deliberately follows the user's default preference even when Hammer x1 and Pumpkin x0.25. Rechecks each floor; missing data retries after five seconds. Actual equipped identity checked after each swap, with cancellation/floor guards.

Aerial approach defaults to teleport above the selected live enemy instead of flying there. Maintains height 10, target-facing orientation, noclip and hover constraints; limits teleport attempts to 0.25 s and confirms arrival after the wait. Rejected arrival backs off 0.75 s. Toggle permits previous flight behavior. No server-authoritative movement bypass is claimed.

New proximity aura defaults OFF: scans living Aggressors inside the current Tower arena and a configurable 3D radius (default 12, range 4–18); activates the equipped weapon if an enemy is eligible and cadence/Enabled/session guards allow it. It does not invent a hit RemoteEvent, assign damage or guarantee simultaneous hits/all kills in the radius. Continuous-attack frequency remains a separate optional control. Diagnostics add slot discovery and aura status/count.

Validation: full Luau parse; actual Tower UI/wave/click tests rerun. Mocked actual V3.22 functions verify Pumpkin default including both weak/no-buff cases, Hammer advantage, tie, inventory-backed slot mapping, virtual key down/up, equipped confirmation, focused-chat and unknown-slot rejection; aerial direct teleport, steady hover, rejected arrival/backoff; aura distance in 3D, live-only and arena-only filtering. Published source read back exactly. Real hotbar schema, keyboard compatibility, replication delay, teleport acceptance and area damage remain in-game test items.


## V3.23: less-penalized weapon preference and R-menu diagnostic
Updated user preference supersedes V3.22's no-buff Pumpkin rule: always select the greater confirmed multiplier, including Crab Hammer x1 over Pumpkin x0.25; ties and incomplete readings still prefer Pumpkin. Existing hotbar/Tool discovery remains. The V3.22 diagnostic found Pumpkin slot 1 but no Hammer hotbar slot, so merely opening an unknown R menu would not identify a safe selection target.

Added separate Armas_R_Diagnostico.lua: 60-second passive observer of manual R openings, newly visible GUI labels/buttons and metadata, user Activated clicks, equipped Tools, matching owned weapon IDs and Hotbar entries. Excludes chat and Nerfangel UI; does not inject input, move, attack or send remotes. User should pause farming, open R, select Crab Hammer and then Pumpkin, and send the copied report. Automatic R-menu selection is pending observed UI paths and identities; it is not implemented in V3.23.

Validation: full Luau parses, Tower lifecycle/UI tests and actual V3.23 weapon/hotbar/teleport/aura mocked tests passed. Read-only probe checked for absence of gameplay input/movement/remote APIs. Both published files read back exactly. No live R-menu interaction test.


## V3.24: Tower model refresh and observed R-wheel equipment
The supplied R probe confirmed QuickSwitch.canvas.wheel with left/bottom/right/top frames and a Caption, manual Crab Hammer equipment, and display name Pumpkin Reaper Greatsword mapping to Tool WeaponId Halloween Greatsword. Tower now holds R, hovers only these four positions, checks the caption against the requested identity before releasing R, then waits for the actual equipped Tool. Releases/cancels held input on stop, phase/character changes, errors, missing selection and focus/chat conflicts. Loaded Tools and verified Hotbar slots remain available, including general weapon IDs. No guessed equip RemoteEvent.

Reorganized six sections: farm/entry/retry, best weapons, enemy profiles, movement/unstick, collection/attacks, progress. F8 start/stop configurable F6–F10. Automatic attacks and aerial mode default ON within activated Tower Farm; teleport above targets remains default, fly speed configurable when flying. Profiles discovered by Animal plus Tier; enabled flag, priority 1–10 and height 2–35. Higher priority can preempt; equal priority retains the current target. Server run attributes exclude NPCs from other parties. Height can be relative to the enemy or arena ground; lie-flat and face-enemy controls retained. Unstick triggers after configurable no-damage duration, temporarily enables scoped noclip and descends to 2.5 studs until target change/death; original collision and Humanoid state restored.

Auto Best Weapon multi-select uses owned registry weapon groups when class metadata exists, otherwise owned item IDs. Compares actual visible per-floor multipliers, selects the greatest and prefers Pumpkin on ties. Unavailable or inaccessible weapons produce diagnostics, not a fabricated successful swap. Multiple copies deduplicate by item ID. Failed alternatives are not retried continuously once a usable winner is measured for the floor; explicit retry and next floor allow another pass.

Tower-specific Collect filter: all-items default or selected item IDs, from registry and observed drops. Collects a bounded one-drop opportunity during waves and up to four seconds after clear, with arena, phase and cancellation checks. Unknown identities are skipped by filtered mode. Collection count is labeled attempts rather than confirmed pickups.

Optional entry is experimental and OFF by default: only acts on identified Infinite Tower/TowerGate proximity prompts and exact visible START NEXT FLOOR/NEXT FLOOR/ENTER TOWER buttons under Tower-named game GUIs. Rejects arena/leave/exit/buy/revive prompts. Near-door mode never teleports; separate launch-anywhere switch permits approach to a loaded identified door and verifies arrival. Unrecognized controls remain manual and are included in diagnostics. Selecting best+1 is delegated to the game's recognized next-floor action and is NOT yet verified in live play. No fabricated tower-start request or arbitrary floor request.

Optional defeat repetition defaults OFF: only retries explicit free retry labels in a recognized defeat result, waits for respawn, never purchases revive, and does not reenter after a healthy manual exit. Unsupported defeat titles/buttons require diagnostics. Existing clear/READY state cycle, dynamic wave counts and floor stop remain. Missing HUD/death/entry waits are bounded.

Validation: full-source Luau parse and 11 actual-function mocked scenarios (audit/test_tower324.py, requires lupa): R caption alias/selection/equipment/cancel/focus; owned groups and measured scores; profile priority, exclusion, run and aura filtering; per-enemy height, relative floor, teleport and unstick descent; filter/cancel during loot; defeat retry/manual-exit distinction; near/far entry permission and unknown prompt refusal; actual HUD one-click/empty-wave/dynamic-wave/clear/floor-limit cycle; sustained unstick; general verified hotbar key release; forced noclip with original true/false restoration. Main source read back exactly after publishing. No live executor test: virtual R cursor behavior, Tower door/result UI matching, next-best floor, attack reach at high altitude and drop-ID schemas require user validation. Non-Tower gameplay algorithms unchanged; version and diagnostics updated.


## V3.25: integrated passive gameplay recorder
New Gravador de diagnóstico tab. Starts automatically with Tower Farm by default or manually while playing. Continuous until stopped/unloaded by default; optional 1–15 minute timer (configured default 5 minutes when enabled), sample interval 0.5–3 s (default 1 s). Ring retention: last 900 samples and 1,000 events; event total counters disclose overflow. At most 180 event/button connections, bounded serializer depth/table entries/strings and fixed change-cache keys. Starting another recording replaces the prior in-memory report.

Observes local character position/look/up/velocity/health/state, equipped weapon attributes, Tower phase/floor/waves/run/target/arena, up to 24 nearby NPCs and their health/run/position, scoped Tower/QuickSwitch visible text/buttons, up to 15 nearby drops, and inbound Tower/Dungeon/Halloween events. Does not read chat, passwords, arbitrary keyboard input, other scripts' source or hidden server state; no upload or external telemetry endpoint. Position jumps are labeled sampled displacements rather than proof of rollback. Passive wrappers report Tower airTrack movement/confirmation, R selection outcomes and UI click attempts while preserving original return arity/values; PRO.log return preserved. Recorder does not initiate gameplay actions. Existing gameplay source is identical except version strings; wrappers and new UI appended.

Controls: start/stop, optional timer, copy full report, copy last 60 events, save .txt into executor file workspace only if writefile exists and user clicks save. Clipboard or F9 fallback. User must submit report to ChatGPT; no automatic transmission. Copy/save before reload or exit. Observed click origin is not asserted to be manual versus scripted. This is diagnostic recording, not a video or an autonomous proof of correctness.

Validation: full-source Luau parse; all 11 V3.24 behavioral scenarios rerun successfully. audit/test_recorder325.py executes actual recorder functions with mocks: chronological ring overwrite/retention, cyclic/depth/string bounds, change deduplication, sample contents, wrapped return arity and log result, event overflow, full/summary serialization, observer disconnection and stopped-write refusal, new-session reset, timed stop and auto-start return preservation. Published source read back exactly. Live Roblox timing, virtual input and real observations remain for user testing.


## V3.26: fixed-center Tower farm and observed height exposure
Main project update; independent Tower Simple file unchanged. Center mode defaults ON in Tower / Movement: holds fixed arena-floor center X/Z, starts 10 studs above the floor, aims at approaching NPCs and attacks with the normal equipped-weapon flow. Does not chase distant mobs, use the legacy dive/unstick behavior, or collect during waves in this mode. Post-clear collection and NEXT FLOOR/READY remain. Disable center mode to use the prior pursuit controller.

Center anchor uses nearest matching floor arena bounding-box X/Z plus confirmed downward raycast on arena geometry. NPC _GroundY median (same run) supplies floor reference; root height used only as fallback. Bounded ray retries reject higher decorative surfaces; unsupported floor geometry leaves the farm waiting with a diagnostic message instead of guessing. Anchor cache invalidates by arena/run/floor. Arrival checked after 0.25 s, rejection backs off; shared owned flight objects preserve original collision/Humanoid restoration. Only nearby allowed live NPCs within six horizontal studs are attack candidates; priorities and run filtering retained. Position never follows NPC X/Z. R/Hotbar weapon comparison remains and can run while mobs approach.

Optional HP-loss response defaults ON: raises height by two studs on observed local HP loss, at least three seconds between raises, up to configured ceiling (default 16). Does not automatically lower or dive if higher altitude stops hits. User may disable it/reset the adjustment. Manual base height is never forcibly lowered by the adaptive ceiling. No immunity or proven per-species safe height is claimed; ranged enemies may stay away or hit at any tested height. Prolonged nearby target without observed NPC HP decrease prompts height/weapon adjustment.

Live catalog records Animal/Tier/AttackType and numeric attack-range-related attributes only when actually present; no invented Beach mob data. Retains up to 40 observed variants. Diagnostic/recorder include effective height, fixed anchor, local HP-loss events, per-height sampled exposure, observed NPC HP decreases and species descriptors. HP loss is not attributed to a particular mob; NPC HP loss is not proof that our weapon caused it. Zero recorded damage over a sample interval does not prove immunity. Live Roblox testing is required to establish practical height/reach balance for the Beach enemies in the user's run.

Validation: full Luau parse; five new actual-function mocked scenarios in audit/test_tower_center326.py: confirmed floor versus decorative Y/cache; fixed X/Z and facing, rejected arrival/cancellation; proximity, priority/exclusion/run guards; HP adjustment cooldown/ceiling and live species catalog; waiting without chase/dive/combat collection and attacking after approach. Existing eleven Tower scenarios, recorder tests and independent Tower Simple tests rerun. Existing Tower tests explicitly use pursuit mode when exercising that controller. Published source read back exactly. No live Roblox or authoritative server attack-reach test.
