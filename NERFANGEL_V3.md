# Nerfangel Hub V3.4 — BETA

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
