# Roblox Chaser NPC AI Script

Shadow Trail AI is a server-side Roblox horror game NPC script that adds pathfinding, player detection, chasing, wandering, stamina management, flashlight and sprint reactions, stuck handling, and controlled teleport recovery to a `ChaserNPC` model.

## Install

1. Create or use an NPC model named `ChaserNPC` inside `Workspace`.
2. Make sure the model contains:
   - A `Humanoid`
   - A `HumanoidRootPart`
   - A correctly welded body
3. Make sure the NPC body parts are unanchored and the `HumanoidRootPart` can move.
4. Insert `ChaserAI.server.lua` inside the `ChaserNPC` model.
5. Ensure floors and obstacles use appropriate collision settings so Roblox pathfinding can navigate the map.
6. For better server movement stability, set the NPC's network ownership to the server when needed.
7. Confirm that the NPC's `HumanoidRootPart` is positioned above a valid floor before starting the game.

## Use

Once the script is inside the NPC model, it runs automatically on the server.

The NPC will:

- Detect living players within 50 studs when it has line of sight.
- Chase detected players using Roblox `PathfindingService`.
- Recalculate paths when a path becomes blocked or the target moves.
- Jump and climb when supported by the generated path.
- Detect when it is stuck and attempt to repath.
- Wander around its starting position within a 45-stud radius when no player is being chased.
- Use a 90-point stamina system while chasing.
- Drain stamina during a chase and regenerate stamina while not chasing.
- Slightly change its wandering direction when it notices a nearby sprinting player or an active flashlight.
- Avoid immediately starting a chase from flashlight or sprint reactions.
- Attempt a safe teleport 20–30 studs from the target if the chase remains unreachable for 10 seconds.
- Enforce a teleport cooldown and check the destination for valid ground and collisions.

The script recognizes these optional sprint attributes on the `Player` or character:

- `IsSprinting`
- `Sprinting`

It recognizes these flashlight signals:

- `FlashlightOn` on the character
- `IsOn`, `FlashlightOn`, or `Enabled` on a character Tool named `Flashlight` or `Torch`

If your existing sprint or flashlight systems use different attribute names, update the detection functions near the top of `ChaserAI.server.lua`.

Gameplay values such as detection range, chase speed, stamina, wander radius, repathing, and teleport timing can be adjusted in the `CONFIG` table.

---

More Roblox script projects by EnderDevelopment: https://github.com/EnderDevelopment

Project page: https://dash.enderdevelopment.com/community/6f6d7b7b-ac30-4335-b3bc-2906791d3ab6?utm_source=github&utm_medium=readme&utm_campaign=auto_publish&utm_content=6f6d7b7b-ac30-4335-b3bc-2906791d3ab6
