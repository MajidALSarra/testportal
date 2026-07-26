# 🦅 Brawl Legends

A **Brawl Stars–style** top-down arena brawler, built with pure HTML5 Canvas + vanilla JavaScript. No build step, no dependencies — just open `index.html`.

## The Brawlers

| Brawler | Animal | Role | Play style |
|---------|--------|------|------------|
| **Sagoory** | 🦅 Eagle | Sharpshooter | Fast and fragile. Rains rapid feather-darts from long range. **SUPER — Talon Dive:** launches forward through enemies, firing a fan of feathers. |
| **Hadoosh** | 🦏 Goofy two-legged rhino | Tank | Huge health, close-range shotgun spread. **SUPER — Rhino Charge:** an unstoppable charge that flattens and knocks back everything it hits. |
| **Saeedan** | 🐑 Sheep | Support | Balanced fighter that lobs wool bombs. **SUPER — Wool Bloom:** heals itself and bursts nearby enemies with a cloud of fleece. |

## How to Play

- **Move** — `W` `A` `S` `D` / arrow keys (or the left joystick on touch devices)
- **Aim & Shoot** — move the mouse and hold **left click** (or the right joystick)
- **SUPER** — press `Space` / `Q` when the bar is full (or tap the SUPER button)
- **Pause** — `P` / `Esc` / the ⏸ button

Hide in **bushes** 🌳 to go invisible, smash **crates** 📦 for heal / super power-ups, and survive escalating waves of enemy brawlers. Every takedown scores 100 points and charges your SUPER.

## Run it

Open the file directly:

```
open index.html      # macOS
xdg-open index.html  # Linux
```

Or serve it locally:

```
python3 -m http.server 8000
# then visit http://localhost:8000
```

Works on desktop (keyboard + mouse) and mobile (on-screen twin sticks).

## Project layout

```
index.html   — screens: menu, how-to-play, game, game-over
style.css    — all UI styling and the animated SUPER ring
game.js      — engine: brawler art, physics, AI, waves, input, rendering
```

All character art (the eagle, rhino, and sheep) is drawn procedurally with Canvas primitives — no image assets required.
