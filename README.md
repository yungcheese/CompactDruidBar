# Compact Druid Bar

A compact, fully scalable druid bar for **WoW Forever** (client 1.60.1, interface 16001). Built for feral powershifting, but it adapts to every form.

## Features
- **Health** and **energy / rage / mana**: the bar switches with your form
- **Combo points** (Cat Form only)
- **Mana while shapeshifted** with a **powershift counter** (`x3` = shifts you can still afford) and a mark on the bar for each shift's cost
- **Energy tick timer**: a white spark runs across the energy bar and reaches the end on the next tick
- **Clearcasting alerts**: the energy bar lights up, a large pulsing icon appears, plus a sound and a border flash
- **Target debuffs** (Rip, Rake, Pounce, Faerie Fire / Demoralizing Roar / Moonfire, Insect Swarm), **cooldowns** and **buffs** (Mark of the Wild, Thorns, Tiger's Fury, Nature's Grasp), centered on one line
- **Rip/Rake refresh warning**: the icon blinks red during its last 2 seconds
- **Mana consumables**: cooldown and count of your best mana potion and Demonic/Dark Rune
- **Glow at 5 combo points** and a **GCD spark** on the power bar
- **Choose your clearcasting sound**: built-in alerts, SharedMedia sounds, or any SoundKit/FileDataID from [wago.tools/sounds](https://wago.tools/sounds)
- **Add your own spells** (cooldowns, buffs, debuffs per form) and hide built-in ones on the *Spells* options page
- Only shows spells you know, so it grows with you while leveling
- Dimmed out of combat

## Installation
Copy the `CompactDruidBar` folder to:
`World of Warcraft\_forever_\Interface\AddOns\`

Then restart the game (or `/reload`) and enable the addon in the AddOns menu on the character screen.

## Commands
| Command | Action |
|---|---|
| `/cdb` | Open the options panel |
| `/cdb spells` | Open the Spells page (custom + built-in spells) |
| `/cdb unlock` / `/cdb lock` | Toggle move mode |
| `/cdb scale 1.2` | Set the bar scale |
| `/cdb reset` | Reset positions and scale |
| `/cdb test` | Preview the clearcasting alert for 3 seconds |
| `/cdbdebug` | Show which values the client exposes (works in combat) |

## Moving and scaling (while unlocked)
- **Drag**: move the whole bar
- **Shift+drag** an element: detach it
- **Right-click** a detached element: attach it again
- **Mouse wheel**: scale the bar, or a detached element on its own

## WoW Forever addon restrictions
Forever applies the Midnight addon restrictions, so health, energy and mana are "secret" values for addons. Compact Druid Bar works around this:
- Bars and numbers are still drawn by the game itself.
- The powershift counter uses game-side curves instead of addon math.
- The energy tick is derived from the 2-second rhythm of energy updates.
- If target debuff IDs are hidden in combat, it shows all of your debuffs on the target instead.

## License
MIT
