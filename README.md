# R2K

A 1v1 basketball prototype for Roblox, inspired by 2K. It has dribbling with no input delay, a timed shot meter, steals, crossovers and a scoreboard.

## Run it

You need [Rojo](https://rojo.space) 7.4 or newer.

- `rojo build -o R2K.rbxlx`, then open `R2K.rbxlx` in Studio, or
- `rojo serve`, then connect from the Rojo plugin in Studio.

To play 1v1 locally, open the Test tab in Studio, set Clients and Servers to 2 players, and press Start.

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Shoot: hold, then release on the green line | E | X |
| Steal (when defending) | E | X |
| Crossover | Q | LB |
| Pass (goes where you face) | R | B |

On mobile, these controls appear as on-screen buttons.

## Why dribbling has no lag

- The server stores only who has the ball. Every client draws the ball in that player's hand on its own, so the ball never waits on the network.
- Every client also bends the ball handler's arms toward the ball, using Roblox's built-in IKControl. The dribble hand rides each bounce, and both hands hold the ball on a shot. No animation data crosses the network.
- Your own crossovers and shot windups show up instantly, and the server is told afterward.
- The ball only becomes a real physics ball, run by the server, when it's loose: shots, rebounds, passes and pokes. Nobody can fake a basket, and anyone near a pass can pick it off.
- The dribble runs on Roblox's synced server clock, so the server and every player work out the exact same ball position: side, bounce height, crossover and shot windup.
- Steals: pressing steal near the ball handler opens a reach that lasts a split second. The server checks real contact between your hands and the ball every frame, with no dice roll. Contact knocks the ball loose, and whoever gets there first keeps it. A ball low in its bounce slips under the reach, and crossing over away from the defender protects it.
- Shot odds come from timing and distance, like in 2K.

All tuning values live in `src/shared/Hoops.luau`.

## Tests

`lune run tests/hoops.spec` checks the shot math. Gameplay itself is tested in Studio.
