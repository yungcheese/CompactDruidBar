<!--
CurseForge project text for Compact Druid Bar.
- "Summary" goes in the short summary field (max ~255 characters).
- Everything below "Description" goes in the project description.
-->

# Summary

A compact, fully scalable druid bar for WoW Forever: energy/rage/mana, combo points, a powershift counter, energy tick timer, clearcasting alerts, Rip/Rake timers, cooldowns and buffs, all in one small block.

# Description

## Compact Druid Bar

Everything a druid needs, in one small bar you can scale and place anywhere. Built for feral **powershifting**, but it adapts to every form.

Made for **WoW Forever** and its addon restrictions: it keeps working in combat where many classic addons break.

### Features

**Bars**
- Health and energy / rage / mana, switching with your form
- Combo points in Cat Form, with a glow at 5 points
- Mana while shapeshifted, with a **powershift counter** (`x3` = shifts you can still afford) and a mark for every shift's cost
- **Energy tick timer**: a spark runs across the energy bar and reaches the end on the next tick
- GCD spark on the power bar

**Clearcasting**
- Energy bar lights up, a large pulsing icon appears, plus a border flash
- Choose your sound: 10 alert sounds included with the addon (chimes, bell, shimmer, gong...), SharedMedia sounds from DBM/WeakAuras, or any SoundKit / FileDataID

**Timers and reminders**
- Your debuffs on the target: Rip, Rake, Pounce, Faerie Fire, Demoralizing Roar, Moonfire, Insect Swarm
- **Rip/Rake refresh warning**: the icon blinks red during its last 2 seconds
- Cooldowns per form (Dash, Nature's Grasp, Barkskin, Innervate, Bash, Feral Charge and more)
- Mana Potion and Demonic/Dark Rune cooldowns with item count
- Buff reminders for Mark of the Wild and Thorns, plus Tiger's Fury and Nature's Grasp timers
- **Add your own spells** (cooldowns, buffs, debuffs per form) and hide built-in ones

**Layout**
- Classic look by default: gold frame, Blizzard bar textures, combo point gems, classic icon borders; or pick Classic polished, Flat or Soft
- One compact block, or detach any element and place it on its own
- Scale the whole bar or each element separately (mouse wheel)
- Snaps to the screen center, exact X/Y position in the options
- Unlocks automatically in Blizzard's Edit Mode
- Dimmed out of combat
- Only shows spells you know, so it grows with you while leveling
- Minimap addon list entry, optional minimap button

### Commands

| Command | Action |
|---|---|
| `/cdb` | Options |
| `/cdb spells` | Add or hide spells |
| `/cdb unlock` / `/cdb lock` | Move mode |
| `/cdb minimap` | Toggle the minimap button |
| `/cdb test` | Preview the clearcasting alert |
| `/cdb reset` | Reset positions |

### About WoW Forever's restrictions

WoW Forever hides health, energy, mana and auras from addons during combat. Compact Druid Bar works around this:
- Bars and numbers are drawn by the game itself.
- The powershift counter uses game-side curves instead of addon math.
- The energy tick is derived from the rhythm of energy updates (it needs a few ticks to lock in).
- Rip, Rake and other debuffs, and Tiger's Fury, are timed from your own casts in combat. A missed or dodged cast can give a timer that is slightly off.

### Feedback

Found a bug or have an idea? Open an issue on GitHub: https://github.com/yungcheese/CompactDruidBar/issues
