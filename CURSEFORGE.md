<!--
CurseForge project text for Compact Druid Bar.
- "Summary" goes in the short summary field (max ~255 characters).
- Everything below "Description" goes in the project description.
-->

# Summary

A compact, scalable druid bar for WoW Forever: powershift counter, clearcasting alerts, bleed timers, cooldowns, buffs and party buff tracking in one small block that keeps working in combat.

# Description

## Compact Druid Bar

Everything a druid needs in one small, scalable bar. Built for feral **powershifting**, works in every form, and made for **WoW Forever**: it keeps working in combat where many classic addons break.

### New in 1.2: party buffs

Turn it on in the options (Alerts page). When someone in your party misses **Mark of the Wild** or **Thorns**, the icon gets a pulsing red border, a count and a strip with every member in class color (red = missing, pulsing = almost gone). **Hover** it to see how long everyone's buff lasts, **click** it to buff the next one. Thorns goes to the tank and to names you add. Keeps tracking in combat from timers and your own casts.

### Features

- **Bars**: health and energy / rage / mana (switches with your form), combo points with a glow at 5
- **Powershift counter**: mana while shapeshifted, `x3` = shifts you can still afford, one mark per shift
- **Energy tick** and **GCD** sparks on the power bar
- **Clearcasting**: bar highlight, big pulsing icon, border flash and a sound of your choice (Blizzard's proc sound, 10 included sounds, SharedMedia or any sound ID)
- **Target debuffs**: Rip, Rake, Pounce, Faerie Fire, Demoralizing Roar, Moonfire, Insect Swarm, with a red blink when Rip/Rake are about to drop
- **Cooldowns** per form, plus mana potion and rune cooldowns
- **Buffs**: Mark of the Wild, Thorns, Tiger's Fury, Nature's Grasp and a **food buff reminder**
- **Caster view**: your Rejuvenation and Regrowth timers on a friendly target
- **Your own spells**: add cooldowns, buffs or debuffs per form, hide built-in ones

### Layout and profiles

- Classic gold look by default, or Classic polished, Flat or Soft
- One compact block, or detach any element; scale everything with the mouse wheel
- Unlocks with Blizzard's Edit Mode, dims out of combat, only shows spells you know
- **Profiles** per character, switching automatically by group or talent spec, shareable as a string
- Works on non-English clients

### Commands

`/cdb` options · `/cdb spells` add or hide spells · `/cdb unlock` / `/cdb lock` move mode · `/cdb reset` reset positions · `/cdb test` preview the clearcast alert

### WoW Forever restrictions

Forever hides health, power and auras from addons in combat. The bars are drawn by the game itself, the powershift counter uses game-side curves, and debuffs, Tiger's Fury and party buffs are timed from your own casts. A dodged cast or a buff from another player during a fight shows up once combat ends. Click-to-buff only works out of combat: the game doesn't let addons pick a target in combat.

### Feedback

Bugs or ideas: https://github.com/yungcheese/CompactDruidBar/issues
