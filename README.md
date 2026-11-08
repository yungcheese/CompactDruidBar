# Compact Druid Bar (WoW Forever 1.60.1)

## Installeren
Kopieer de map `CompactDruidBar` naar:
`World of Warcraft\_forever_\Interface\AddOns\`
(standaard: `C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\`)

Start het spel (of `/reload`) en zet de addon aan in het AddOns-menu op het characterscherm.

## Commando's
| Commando | Wat |
|---|---|
| `/cdb` | Optiepaneel openen |
| `/cdb unlock` / `/cdb lock` | Verplaatsmodus aan/uit |
| `/cdb scale 1.2` | Schaal van het blok |
| `/cdb reset` | Posities en schaal terugzetten |
| `/cdb test` | Clearcast-weergave 3 sec testen (glow, icoon, geluid, flits) |

## Verplaatsen en schalen (ontgrendeld)
- **Slepen**: verplaatst het hele blok
- **Shift+slepen** op een onderdeel: maakt het los
- **Rechtsklik** op een los onderdeel: koppelt het weer vast
- **Scrollwiel**: schaalt het blok, of een los onderdeel apart

## Onderdelen
- Health, Energy/Rage/Mana (past zich aan per form)
- Combo points (alleen in Cat)
- Mana tijdens shapeshift met **xN** = aantal powershifts dat je nog kunt doen, plus streepjes per shift-kosten
- Energy-tick: wit streepje dat over de energy-bar loopt, met een tick als het rechts aankomt
- Clearcasting: energy-bar wordt lichtblauw, groot pulserend icoon, geluid en een rand-flits
- Target-debuffs (Rip, Rake, Pounce, FF / Demo Roar / Moonfire, Insect Swarm), cooldowns en buffs (MotW, Thorns, Omen, Tiger's Fury)
- Alleen spells die je kent worden getoond, dus de bar groeit mee tijdens het levelen

## Forever-beperkingen
Forever schermt sommige combat-informatie af voor addons. Daarom valt de addon terug in plaats van errors te geven:
- Kan de addon target-debuffs in combat niet herkennen? Dan toont hij al jouw debuffs op het target.
- Zijn je eigen buffs afgeschermd? Dan blijft de laatst bekende stand staan.
- Clearcasting werkt via de buff, met als reserve "je volgende spell kost 0".
