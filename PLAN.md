# GrimTactics (working title) - plan

A turn-based hex tactics game with a Dark Souls feel: one hero against a
boss, using some mechanics from the Dark Souls board game, made digital.
It is its own game, with its own names and content.

Step 1 is built (2026-11-14), unplayed. Everything marked (PLACEHOLDER) is
my guess, for Martin to change. Run it with play.bat.

## Agreed
- **One hero**, no party. Enemy numbers are set for one hero (PLACEHOLDER,
  Martin balances).
- **Hex tiles.** The boss faces one of 6 directions and turns 60 degrees at
  a time.
- **Two bars:** health and stamina, separate.
  - Stamina only partly refills at the start of your turn (changed
    2026-11-14: a full refill made attacking, moving and dodging every hit
    trivial). Attacks, extra steps and dodges spend it. What you leave
    unspent is what you have to dodge with on the boss's turn, and
    overspending leaves you short next turn too.
  - Dodges get dearer within one boss turn: the first costs 1, the second
    2, the third 3 (agreed 2026-11-14).
  - Every attack costs at least 1 stamina (agreed 2026-11-14).
  - As many attacks a turn as your stamina pays for, and a turn with no
    attack gives extra stamina back (agreed 2026-11-16: one attack and a
    dodge kept back every turn was too easy).
  - Health only goes down from hits and only comes back with a flask.
- **Attacks do set damage, no dice** (changed 2026-11-17: Dark Souls'
  predictable damage is better). Blocking takes a set amount off too
  (2026-11-17). No dice anywhere now.
- **Combos** (agreed 2026-11-17): the 2nd hit in a row does +10%, the 3rd
  +20%, then it starts again: the 4th is a 1st hit (2026-11-17). Weapon
  classes may have their own combos later. Moving or
  the end of your turn breaks the combo.
- **Two weapon sets** (agreed 2026-11-17), picked on the menu. Swapping
  costs 1 stamina on your turn and doesn't count as attacking, so it
  doesn't cut your stamina back. Swapping breaks the combo (PLACEHOLDER
  choice); a run before it still counts.
- **Running attack** (agreed 2026-11-17, changed 2026-11-18): a skill of its
  own: run at least 2 hexes to the boss, then hit with +20%. It counts as the 1st
  hit of a combo, so the next hit is +10% again.
- **Dodging is a timing check, one per attack.** A small window pops up
  with a bar that fills, speeding up as it nears the sweet spot. Tap in the
  sweet spot and the attack misses you completely; miss it and you take the
  full hit. Later, the window could play the attack's animation instead.
- **Dying:** back to the bonfire, the rooms' enemies come back, and your
  souls drop where you died. Get back there without dying again to pick
  them up; die first and they're gone. No limit on deaths.

## From the board game (to confirm)
- **Moving:** every step costs 1 stamina, no free first step (changed
  2026-11-17).
- **Weapons** have a few attack options, each with a stamina cost and damage.
  Block takes a set amount off the hit's damage.
- **Defending** (changed 2026-11-18): against each boss attack you block,
  dodge or take the hit.
  - Block: 2 stamina (3 against a heavy boss attack), no skill check, takes
    the set block amount off. No stamina, no block.
  - Dodge: the timing check, 1 / 2 / 3 stamina within a boss turn.
  - Take the hit: the full hit, no stamina.
- **Heavy attacks are worth more per stamina** (2026-11-18), and a light
  costs 2, so a full 3-hit combo empties the bar. With +2 back after
  attacking, turns go attack, then reposition.
- **Boss arcs:** front (the 1 hex it faces), left and right (2 hexes each),
  back (1 hex). Further out, hexes on the line between two arcs count as
  both.
- **Boss attacks** hit whole arcs within a range. The boss only turns when it
  moves, never when it attacks, so you can be safe just by being in the
  right arc.
- **Weak arcs:** each boss attack leaves some arcs weak. Hitting from a weak
  arc adds extra damage.
- **Behaviour deck:** a few of the boss's cards are dealt and shuffled. When
  they run out they're played again in the same order, so you can learn the
  pattern.
- **Aiming (agreed 2026-11-14, instead of the board game's whiffing):** each
  card has a budget of turns and steps it can spend just before its attack
  to bring you into it, e.g. Overhead may turn once and step once. Stand
  further round than the budget reaches and it still misses. (Tried and
  turned down: the boss picking the best of its 4 cards each turn, which
  loses the pattern to learn.)
- **Heat up:** at a set health, one extra card is shuffled in.
- **Pushes:** some attacks push you a hex away from the boss.
- **The boss** takes up one hex, and you can't enter it.
- **Gone with the party:** aggro and taunt (the boss always goes for you).

## The dodge check (PLACEHOLDER details)
- You choose the hex you dodge to first (1 hex), then the window opens.
- The attack sets how hard it is: a narrower sweet spot and a faster bar for
  a quicker attack.
- The sweet spot is the same size whatever the armour (2026-11-17: all as
  hard as the old heavy armour); heavy armour fills the bar sooner, so
  there's less time to react.
- One tap. No half dodge.
- While the window is open the game waits for you.

## Steps
1. **One fight:** one hero, one boss, one small room (about 5-6 hexes
   across). Moving, attacking, blocking, the dodge check, flask, boss arcs,
   the behaviour deck and heat up. Dying just restarts the fight. Tests
   check it works. BUILT 2026-11-14, unplayed.
2. Bonfire, rooms of smaller enemies, souls dropped and picked up.
3. Levelling and gear.

## Look
- Minimal pixel art on black, 1-2 colours per character (PLACEHOLDER). The
  hero is drawn the same way as the boss (top down, holding the chosen
  weapon, turned to face the boss); the boss is drawn bigger. Hexes are
  radius 18. Sizes PLACEHOLDER.
- Only 2 facings drawn, the other 4 are mirror flips; nothing rotated.

## Platform
PC first, mouse clicks only (no hover-only info, no keyboard-only actions),
so the same layout can go onto a phone later. Phone: landscape (turns
with the phone), taps act as clicks, an Android export preset (arm64 APK,
debug-signed, build/GrimTactics.apk).

## Three modes to try (2026-11-18; my guesses, Martin to change)
Play opens a mode list (names PLACEHOLDER), then boss and equipment.
- **Stamina:** the game as it was, but the stamina left after paying for a
  dodge sets the dodge bar: 5-6 slow, 3-4 middle, 1-2 fast (times 1.2 / 1.0 /
  0.8, on top of the boss card's difficulty and the armour).
- **One attack:** no stamina. Move up to 3 hexes and attack once a turn,
  before or after moving; the running attack needs 2 of the 3 hexes. Block and dodge
  always there. The flask takes the turn's attack; swapping is free. No combos.
  The dodge bar is set by this turn's attack: longsword light slow, claymore
  light and bow middle, any heavy fast, no attack slow.
- **Turn order:** as One attack, plus speeds (FFX-style list, not FF7 bars):
  longsword 10, bow 8, claymore 6, boss 8. Whoever has waited least goes next
  (the hero on a tie), so a quick weapon sometimes gets two turns in a row.
  A strip of 8 squares under your health shows who goes next. Swapping changes
  your speed from your next turn. Armour doesn't change speed.

## Skills come from equipment (being discussed 2026-11-18)
Like Stoneshard: each piece of gear brings its own moves.
- Weapon: its light and heavy attack plus a move of its own. Longsword: the
  running attack. Claymore and bow: to decide.
- Shield: a better block (maybe its own slot; not with two-handed weapons).
- Armour: the dodge. Heavy armour keeps a dodge but with harder timing, a
  shorter dodge bar (agreed 2026-11-18; built already as the faster bar).
- Open: running attack on the longsword only? Shield its own slot?

## Menus (agreed 2026-11-17)

- Title: Play (plus the version and the update button).
- Then pick the boss (only the knight so far; "Knight" is a PLACEHOLDER
  name).
- Then equipment: Weapon 1, Weapon 2 and Armour slots with icons. Tapping a
  slot opens a grid of icons to pick from. Then Fight.
- Settings (from the title): Screen = Portrait (the default since 2026-11-17) or Landscape.
  Portrait puts the room on top and the panel under it. Saved on the
  device. On PC, portrait makes the window upright.
- After a win or a death you go back to the equipment screen (PLACEHOLDER
  choice).
- In a fight (2026-11-18): a cog top right opens Settings, with Main menu
  to leave the fight and Back to carry on.
- The fight view follows the hero: the hero stays mid-screen and the room
  moves around them (ready for a world map later). The boss's health and its
  card sit along the top of the screen.
- When the boss attacks, Block / Dodge / Take the hit come up in a pop-up in
  the middle of the screen (just clear of the hexes round the hero), and the
  dodge bar comes up in the same place.

## Gear for step 1 (agreed 2026-11-14, numbers PLACEHOLDER)
- **Longsword and shield:** one-handed sword, shield adds block.
- **Claymore:** two-handed, no shield, bigger hits.
- **Light armour / heavy armour:** to test the dodge window. Light = more
  time to react, less block; heavy = the bar fills sooner, more block.

## Magic (agreed 2026-11-14, not in step 1)
Board game style: spells cost stamina like any attack, magic damage is its
own type that goes against Resist instead of Block, Intelligence and Faith
decide what you can use. No separate spell bar.

## Step 1 as built (all numbers PLACEHOLDER)
- Room: 37 hexes (radius 3). The hero starts at the bottom edge, the boss in
  the middle facing it. The hero goes first.
- All damage and health were multiplied by 10 on 2026-11-17 so the combo
  percentages show.
- Hero: health 200, a stamina bar of 6 (starts full, +2 after a turn you attacked, +6
  after a turn with no attack, so a full bar; changed 2026-11-17), 2
  flasks healing 100 each (drunk on your turn,
  free). Attacks from next to the boss, as many as stamina pays for. Moving and attacking in
  any order.
- Block: shield 10 + armour (light 10, heavy 30); claymore has no shield.
  The Block button shows the damage you'll take.
- Attack damage (before the boss's block; buttons show what lands):
  Every weapon has a light attack and a heavy attack, no weapon-specific
  names (2026-11-18). Longsword: light 2 stamina 25, heavy 3 stamina 45.
  Claymore: light 2 stamina 35, heavy 4 stamina
  70 (changed 2026-11-18); no shield. A weak arc adds 10. Bonuses are worked out on damage plus
  the weak bonus, then the boss's block comes off.
- Bow (agreed 2026-11-18): light attack 3 stamina, 40 damage (PLACEHOLDER), from
  anywhere in the room, right next to the boss too (changed 2026-11-18). 10 arrows a fight
  (later: 10 from leaving the bonfire). Weak arcs and combos count; no
  running attack; no block.
- The running attack is its own skill (2026-11-18), in Skills: pick a hex
  next to the boss at least 2 hexes away; the hero runs there and hits
  (light attack +20%, costs the steps plus the light attack's stamina).
- Hero menu (2026-11-18): Attack > (light, heavy), Skills > (running
  attack), Items > (flask), Swap, End turn. Back returns to the top.
- Light armour: block 10. Heavy: block 30, the dodge bar fills in 0.75 of
  the time.
- Dodge check: the bar fills in 1.3 / 1.1 / 0.9 s (dodge difficulty 1-3),
  speeding up; the sweet spot starts 72% along and is 11 / 8 / 6% wide
  (the old heavy armour sizes). Click or Space to stop it.
- Boss (a knight with sword and shield): health 400, block 10, heats up at
  180. Card attacks are 10x what they were (Lunge 50, Overhead 80...). Deck of 4 dealt from 6 cards: Lunge, Sweep, Turn and cut, Overhead,
  Shield bash, Step back thrust. Heat up adds Leap or Flurry. Aim budgets
  (turns, steps): Lunge 1,0 after moving 2; Sweep 1,0; Turn and cut 1,0
  after spinning round; Overhead 1,1; Shield bash 2,1; Step back thrust 1,0
  after backing off; Flurry 1,1 each time. All attacks hit arcs. The next card
  is face down; the last one stays showing, and its weak arcs are tinted
  green on your turn.
- The boss can't be stood on, so a leap lands next to you rather than on
  you; moving towards you stops next to you and turns to face you.
- After the fight (win or lose), a click goes back to the gear choice.

## Questions for Martin
- The first boss: a placeholder knight for now. Yours to redesign.
- Should the next boss card be shown, or stay face down (board game)?
