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
- **Running attack** (agreed 2026-11-17): after moving 2 hexes, the
  standard attack becomes a running attack with +20%. It counts as the 1st
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
- **Blocking** costs no stamina.
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
- Hero: health 200, a stamina bar of 10 (starts full, +2 after a turn you attacked, +8
  after a turn with no attack; changed 2026-11-17), 2
  flasks healing 100 each (drunk on your turn,
  free). Attacks from next to the boss, as many as stamina pays for. Moving and attacking in
  any order.
- Block: shield 10 + armour (light 10, heavy 30); claymore has no shield.
  The Block button shows the damage you'll take.
- Attack damage (before the boss's block; buttons show what lands):
  Longsword: Slash 1 stamina 25, Heavy slash 2 stamina 35. Claymore: Swing 1 stamina 35, Heavy swing 3 stamina
  55; no shield. A weak arc adds 10. Bonuses are worked out on damage plus
  the weak bonus, then the boss's block comes off.
- Running slash / Running swing replace Slash / Swing after 2 hexes moved
  since your last attack that turn; same stamina.
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
