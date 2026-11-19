# R2K

A 1v1 basketball prototype for Roblox, inspired by 2K. It has dribbling with no input delay, a timed shot meter, steals, crossovers and a scoreboard.

## Run it

You need [Rojo](https://rojo.space) 7.4 or newer.

- `rojo build -o R2K.rbxlx`, then open `R2K.rbxlx` in Studio, or
- `rojo serve`, then connect from the Rojo plugin in Studio.

To play 1v1 locally, open the Test tab in Studio, set Clients and Servers to 2 players, and press Start.

## Practice bot

Alone in a server, a practice bot in a red jersey joins and plays you to 21. It leaves when a second real player joins. Press **P** (D-pad up on a controller) to give it the ball at the top of the key, for defense practice.

It plays by the same rules as you:
- **Its actions:** it moves, shoots, steals and blocks through the same server checks your buttons go through, so it can't cheat.
- **It plays a beat behind:** it sees you about 0.2s late, like a person.
- **Offense:** it attacks the rim. When you're in its lane, it reads which side you're shading, crosses you away from its ball hand, and spins when you're tight. It steps back near the arc and pulls up only if that made space. It picks shots by their real odds, and its release timing lands around perfect, so it greens some and misses some.
- **Defense:** it stays between you and the rim, guarding where you're heading. Changes of direction beat it. It crouches into intense D once it's in front of you, swipes only when its reach would really touch the ball, and jumps at your set point, or at the takeoff of a layup or dunk.

Its brain is `src/server/Bot.luau`, a pure module. `lune run tests/bot.spec` plays hundreds of simulated possessions against it. Difficulty knobs (reaction time, steal and block rates, shot spread and so on) are in `Brain.SKILL` at the top of that file.

## Play against real people

A game starts as soon as two players are in a server. It's first to 21, with shots worth 2 or 3. After a make, the other player checks the ball at the top of the key. The winner gets a win on the scoreboard, and a new game starts. Alone in a server, you can shoot around while the screen says "Waiting for an opponent...".

To put it on Roblox:

1. In Studio, choose File → Publish to Roblox.
2. Set the server size to 2 players, so every server is one 1v1 and Roblox pairs up strangers for you. In the Creator Dashboard, go to your experience, then Places, then the start place, then Access. Set the max visitor count to 2, and set server fill to fill each server to the max if that option is offered. Studio has the same setting under Game Settings → Places. Roblox moves these menus around, so the names may differ.
3. Make the experience public in the Creator Dashboard, or keep it private and invite friends.

With more than 2 players in a server, it plays as cutthroat: everyone for themselves, and the ball goes to a random other player after a make.

## Controls

The controller layout follows 2K.

| Action | Controller | Keyboard |
|---|---|---|
| Move | Left stick | WASD |
| Sprint (turbo) | RT / R2 | Shift |
| Shoot: hold, then release on the green line | X / Square | E |
| Steal (on defense) | X / Square | E |
| Pass (goes where you face) | A / Cross | R |
| Block (jump, arms up) | Y / Triangle | F |
| Dribble moves | Right stick (pro stick, below) | Letter keys (below) |
| Escape moves (on offense), intense D (on defense) | Hold LT / L2 | Hold Ctrl |

**Pro stick:** flick the right stick and let go. Directions are relative to your ball hand, so they mirror when the ball is in your left hand.

| Right stick | Move | Key |
|---|---|---|
| Up (toward the basket) | Hesitation | V |
| Toward your other hand | Crossover | Q |
| Toward your ball hand, quick flick | In-and-out | C |
| Toward your ball hand, hold it | Side-step (with L2: escape) | H |
| Down and toward your other hand | Between the legs | Z |
| Down and toward your ball hand | Behind the back | X |
| Straight down | Stepback (with L2: escape) | G |
| Half circle | Spin (with L2: escape) | B |
| — | Double tween | T |

**Chaining:** press the next move while one is still going, and it starts the moment the current one ends, so cross into tween into stepback flows like 2K. A shot pressed mid-move goes up as soon as the move finishes.

**Facing:**
- **With the ball:** you always face the basket, unless you're sprinting.
- **Intense D (hold L2 on defense):** you drop into a stance and slide facing the ball handler. You move slower, but you contest shots from further away.

**Shots:** shoot near the rim to finish with a layup, or a dunk when very close. Further out, it's a jump shot. After you release, the screen says how your timing was: GREEN!, Slightly Early, Very Late, and so on.

**Mobile:** Shoot, Cross, Pass and Block appear as on-screen buttons. The other dribble moves are controller and keyboard only for now.

## Why dribbling has no lag

- The server stores only who has the ball. Every client draws the ball in that player's hand on its own, so the ball never waits on the network.
- Every client also bends the ball handler's arms toward the ball, using Roblox's built-in IKControl. The dribble hand rides each bounce, and both hands hold the ball on a shot. No animation data crosses the network.
- Your own crossovers and shot windups show up instantly, and the server is told afterward.
- The ball only becomes a real physics ball, run by the server, when it's loose: shots, rebounds, passes and pokes. Nobody can fake a basket, and anyone near a pass can pick it off.
- The dribble runs on Roblox's synced server clock, so the server and every player work out the exact same ball position. That covers side, bounce height, every dribble move's own path (under the legs, behind the back, around a spin) and the shot windup.
- Steals: pressing steal near the ball handler opens a reach that lasts a split second. The server checks real contact between your hands and the ball every frame, with no dice roll. Contact knocks the ball loose, and whoever gets there first keeps it. A ball low in its bounce slips under the reach, and crossing over away from the defender protects it.
- Blocks: everyone sees the blocker jump with arms up. Pressing block near the ball handler, or near a shooter while the shot is up, makes the ball live for contact until the animation ends. If the raised hands touch the ball, whether it's held up for a shot or already in the air, it's swatted away and the shot can't score. Anywhere else, block is just the animation.
- Shot odds come from timing and distance, like in 2K.

All tuning values live in `src/shared/Hoops.luau`, including the fixed camera (`CAMERA_HEIGHT`, `CAMERA_BACK`, `CAMERA_FOV`).

## Tests

`lune run tests/hoops.spec` checks the shot math. Gameplay itself is tested in Studio.

## Placeholder animations

The place includes R15 placeholder animations in `ServerStorage → PlaceholderAnimations`:

- **Basics:** JumpShot, Block, StealSwipe, SpinMove.
- **Dribble moves:** Crossover, BetweenLegs, DoubleTween, BehindBack, InAndOut, Hesitation.
- **Stepbacks and escapes:** Stepback, StepbackEscape, SideStep, SideStepEscape, SpinEscape.
- **Finishes:** Layup, Dunk (one hand), DunkTwoHand.

Dribble moves, Layup and Dunk start from the right hand. Each one also has a mirrored `_L` version for the left hand. They play in place: the game moves the character during stepbacks. Each move's ball path, meaning where the ball goes and which hand it ends in, is in `Hoops.MOVES`, timed to match its animation. They're generated by `lune run tools/placeholder-animations`, which writes `assets/animations/*.rbxmx`. Edit the poses there to change them.

To polish one in Studio:

1. Choose Avatar → Rig Builder → R15 → Block Rig.
2. Open Avatar → Animation Editor and click the rig. Make any new animation and save it once. This creates `ServerStorage → RBX_ANIMSAVES → Rig`.
3. Copy the placeholders from `PlaceholderAnimations` into `RBX_ANIMSAVES → Rig`.
4. In the Animation Editor, open ⋯ → Load and pick one. Polish it, then use ⋯ → Publish to Roblox and copy the asset ID.

Publish under the same account or group that owns the game. The game doesn't play these yet; send the IDs to wire them in.

## Same body for everyone

On spawn, the server puts every player on Roblox's default R15 body at default scale. Players keep their own clothes, accessories, skin colors and face. That default body is the one the animations and ball spots are calibrated to, so moves line up for everyone. If a spawned body doesn't match the calibrated rig, the server warns in Output.

## Calibrating the game to the animations

The game's ball spots are measured from the animations on the real rig (`tools/preview/r15-rig.json`), not guessed. That covers the dribble spot, every move's ball path, every shot's path (jump shot, layups, dunks), the block hands and the steal reach. Every shot carries the ball along its animation's hands while you hold shoot, then waits at the release point. The shot launches from wherever the ball is when you let go. The fitter refuses a release point that would be inside the shooter's head. After changing any animation:

1. `lune run tools/placeholder-animations` regenerates the animation files. Leg lengths come from the rig, so feet stay planted.
2. `lune run tools/preview/fit` measures the animated hands and rewrites those values in `src/shared/Hoops.luau`.
3. `lune run tests/hoops.spec` checks that the gameplay rules still hold.
4. Re-publish the changed animations in Studio with **Overwrite**, so their IDs stay the same.

## Previewing animations without Studio

`lune run tools/preview/pose [Name ...]` poses an R15 rig through each animation, using the game's own ball paths. It prints how far the game's arm IK has to pull each hand to the ball while a hand holds it, and whether the feet stay on the floor. Then `python3 tools/preview/render.py [Name ...]` (needs matplotlib) draws front, side and top filmstrips into `tools/preview/out/`.

The rig is a best guess unless `tools/preview/r15-rig.json` exists. To create it, press Play, wait until you've spawned and your body has been standardized, and run this in Studio's command bar. Replace `Rig` with your username, so it reads your character, which is the standard body every player gets. Save the printed line as that file. (The command reads both Motor6D joints and the newer AnimationConstraint joints.)

```lua
local r=workspace.Rig local j={} for _,m in r:GetDescendants() do if m:IsA("Motor6D") then table.insert(j,{name=m.Part1.Name,parent=m.Part0.Name,c0={m.C0:GetComponents()},c1={m.C1:GetComponents()}}) elseif m:IsA("AnimationConstraint") and m.Attachment0 and m.Attachment1 then table.insert(j,{name=m.Attachment1.Parent.Name,parent=m.Attachment0.Parent.Name,c0={m.Attachment0.CFrame:GetComponents()},c1={m.Attachment1.CFrame:GetComponents()}}) end end local s={} for _,p in r:GetChildren() do if p:IsA("BasePart") then s[p.Name]={p.Size.X,p.Size.Y,p.Size.Z} end end print(game:GetService("HttpService"):JSONEncode({hipHeight=r.Humanoid.HipHeight,sizes=s,joints=j}))
```
