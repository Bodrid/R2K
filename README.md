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

On mobile, these controls appear as on-screen buttons.

## Why dribbling has no lag

- The server stores only who has the ball. Every client draws the ball in that player's hand on its own, so the ball never waits on the network.
- Your own crossovers show up instantly, and the server is told afterward.
- When the ball is loose (shots and rebounds), the server runs its physics, so nobody can fake a basket.
- Shots and steals are dice rolls based on timing and distance, like in 2K. That hides lag better than exact hitboxes.

All tuning values live in `src/shared/Hoops.luau`.

## Tests

`lune run tests/hoops.spec` checks the shot math. Gameplay itself is tested in Studio.
