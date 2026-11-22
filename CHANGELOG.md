# Changelog

## Unreleased
- **Click to eat**: left-click the food buff icon to eat the food you picked; right-click to pick it from the food and drink in your bags (out of combat)
- The food buff icon is the classic Well Fed icon again
- **Mana tick timer** (caster): a light-blue spark on the mana bar reaches the end on your next mana tick (hidden when mana regenerates continuously)
- **5-second rule line** (caster): after a spell that costs mana, a light-blue line along the top of the mana bar shrinks over 5 seconds until spirit regen is back
- **Revelation** (WoW Forever weapon enchant): while your main hand has it, an icon in the buff row lights up with a pulsing gold border when Revelation procs; optional alert sound

## v1.2.0
- **Party buffs** (optional, Alerts page): while someone needs Mark of the Wild or Thorns, the icon gets a pulsing red border, a count and a strip with one segment per party member (your own subgroup in a raid), in class color. Red = missing, pulsing = almost gone (Mark of the Wild 2 min, Thorns 1 min), faded = out of range. Only shown while someone needs the buff; in combat (where other players' buffs can't be read) it keeps going on the buff timers, your own casts and deaths. Hover the icon to see how long everyone's buff still lasts. Out of combat, click the icon to cast it on the first member in range who needs it. Thorns goes to tanks (group role) and to the names you enter
- Removed the trainer helper and the level-up note
- Fixed: the food buff icon could show a Mark of the Wild paw, which looked like a second Mark of the Wild icon

## v1.1.1
- Same as v1.1.0, now also published automatically to CurseForge

## v1.1.0
- **Profiles**: save different layouts, choose one per character, switch automatically in raids, parties or by talent spec, and share layouts with an export/import string
- **Trainer helper**: at the class trainer a panel tells you what to buy for your role, what is optional and what you can skip (with the gold it saves). Utility spells where rank 1 is enough (Revive, Rebirth, Hibernate, Soothe Animal, Entangling Roots) go to "skip" from rank 2. Nothing is bought for you; set your role in the options or let it follow your talents
- **Level-up note**: tells you what's new at your trainer when you level up
- **Food buff reminder**: an icon in the buff row that turns red without a food buff and blinks in its last minute, plus a chat note when it runs out. "Well Fed" is recognized automatically; any other food buff (like the new WoW Forever foods) can be picked in the options
- **Caster view**: in caster form with a friendly target, the target row shows your Rejuvenation and Regrowth timers
- Powershift marks now count back from your current mana (each segment is exactly one shift) and use the measured mana cost of your shifts
- Nature's Grasp shows as one icon: its cooldown icon turns green with the buff timer while the buff is up
- Icons are evenly spaced; optional extra gap between groups
- Energy tick timer hides itself on clients where energy regenerates continuously (like WoW Forever)
- Spell and form names are read from the game, so the addon works on non-English clients
- Less CPU: bars update on game events instead of 20 times per second, spell lookups are cached

## v1.0.3
- The original Blizzard Clearcasting proc sound is back (also the druid alert variant) and is now the default sound
- Icons of the merged rows are spread evenly over the lines (e.g. 8 icons become 4 + 4 instead of three lines)
- New "Max icon lines" option: keep your icon size and let the lines stick out past the bar width
- Options split into clear pages with sections: General, Layout, Look, Alerts and Spells
- Tip on the Alerts page: the alert volume follows the chosen sound channel

## v1.0.2
- Combo points moved to the top of the bar
- "Alarm" game sound is back, and the original Blizzard spell proc sound is offered when SpellActivationOverlay is installed
- New look: "Classic gold frame" style (default) with Blizzard bar textures, gold accents, combo point gems, classic icon borders, a background panel and bar sparks; Classic polished, Flat and Soft styles available in the options
- New logo
- Clearcasting sounds are now shipped with the addon (10 original alert sounds), so they work on every client; also shared with other addons through SharedMedia
- Custom sound IDs report in chat when the client cannot play them
- Separate icon size per row (debuffs, cooldowns, buffs); Ctrl+mouse wheel on a row while unlocked
- Faerie Fire (Feral) and Pounce are now recognized by name, so they work even when the client uses different spell IDs

## v1.0.1
- Fixed the Faerie Fire (Feral) name on the Spells options page

## v1.0.0
First release.

- Health and energy/rage/mana bars that follow your form, combo points with a 5-point glow
- Mana while shapeshifted with a powershift counter and cost marks
- Energy tick timer and GCD spark
- Clearcasting alert: energy bar highlight, large icon, border flash and a selectable sound (built-in, SharedMedia or custom SoundKit/FileDataID)
- Target debuffs (Rip, Rake, Pounce, Faerie Fire, Demoralizing Roar, Moonfire, Insect Swarm) with a Rip/Rake refresh warning
- Cooldowns per form, Mana Potion and Demonic/Dark Rune cooldowns, buff reminders, Tiger's Fury and Nature's Grasp timers
- Custom spells and hiding built-in spells (/cdb spells)
- One compact block with detachable, individually scalable elements; center snapping, exact X/Y position, unlocks in Edit Mode
- Minimap addon list entry and optional minimap button
- Works with WoW Forever's combat restrictions (game-side curves, rhythm-based energy tick, cast-based timers)
