# FieldVision iPhone app: real-life test
**IT.** Ogni prova salva un registro sul telefono. Tocca tre volte la fotocamera nel momento esatto in cui succede la cosa vera (copri l'obiettivo, la persona sparisce dietro l'auto, la bici attraversa). Lo script misura quanto ci mette l'app a reagire.
**EN.** Every run saves a log on the phone. Triple-tap the camera at the exact moment the real thing happens (lens covered, person disappears behind the car, bike crosses). The script measures how long the app takes to react.

<br>

## Setup
- iPhone at chest height, camera facing forward (a lanyard or chest strap, or held against the chest). Volume up; the sounds play even in silent mode.
- Start in a well-lit place and move the phone slowly for 2–3 s so ARKit finds the ground.
- The app speaks the iPhone's language. Switch it in Settings › General › Language & Region to do the same runs in both languages at least once.

<br>

## Runs (5 each if time allows)
| # | Do this (triple-tap the camera when it happens) | Expect | Write down |
|---|---|---|---|
| 1 | Cover the lens with your hand, then uncover after 5 s | «Guida non affidabile: obiettivo coperto», long buzz every 4 s, then «Guida di nuovo attiva» | delay from the tap; any miss |
| 2 | Walk into a dark stairwell or room, then back into the light | Torch on by itself: «Buio: accendo la torcia. Vedo solo vicino.» + click-click; guidance goes on within ~5 m. Back in the light, within ~5 s: «Torna la luce: spengo la torcia.» (it blinks off for ¼ s every 5 s to check) | time to torch on; time to torch off; any on/off flicker in normal light |
| 3 | A teammate stands in your path at 2, 4 and 6 m (tape measure) | «Persona davanti»; the camera label shows the distance | label distance vs tape |
| 4 | The teammate walks behind a parked car or pillar for 2–3 s | «Persona nascosta, a sinistra/destra», then «Persona riapparsa» with the **same number** on its label | number kept? delay |
| 5 | Someone runs or cycles across your path 4–6 m ahead | «Veloce a destra/sinistra!» + two strong pulses | delay; did it fire? |
| 6 | Walk towards a pole, bin or bollard | «Ostacolo davanti» + faster beeps | at what distance; misses on plain poles |
| 7 | Walk through a busy area | «Molta gente davanti» once, then quiet | how much it talks |
| 8 | Normal 2-minute walk, nothing special | only the tick | any false «non affidabile» |
| 9 | Walk slowly towards a plain wall | «Muro davanti» around 2–5 m, «Muro davanti, vicino» under 1.2 m, beeps faster under 2 m | distance when it speaks vs tape |
| 10 | Face a wall with an open door to one side, 2–3 m away | «Muro davanti. Passaggio a sinistra/destra» | correct side? |
| 11 | Busy room with people seated at desks (like the 16:21 recording) | few lines; no «Veloce» for people sitting; «nascosta» only for people in front of you | spoken lines per minute |
| 12 | Walk towards a single step up, then a curb down | «Gradino in salita, a 2 passi» / «Gradino in discesa…» + two low taps; «proprio davanti» when close | at how many paces; was the direction right? |
| 13 | Walk towards a staircase going up, then stand at the top of one going down | «Scale in salita…» / «Scale in discesa…» (down interrupts other lines) | never called «Muro»? |
| 14 | Put a box (~20 cm) and then a shoe (~10 cm) in your path | «Ostacolo basso, a 2 passi» + faster beeps | distance; the shoe is the hard one |
| 15 | Walk up a gentle ramp, and on a plain flat floor | nothing about steps | any false «Gradino» |
| 16 | Start 25–30 m from a staircase going up, walk to it | «Scale in salita a 25/30 metri» early, then «Scale in salita, a 5 passi»; the map shows SCALE ↑ where they are | distance when first said (tape or count paces); never «Ostacolo»/«Muro» |
| 17 | A staircase or curb off to one side, 15–20 m ahead | «… a sinistra/destra» once; no close warning if you walk past | side right? said only once? |
| 18 | Top of a staircase going down, approached from 15 m | «Attenzione: scale o dislivello in discesa» early, close warning in paces, «proprio davanti» at the edge | at how many paces |
| 19 | Same as 12 and 16 at dusk or in a dim street, then in the dark with the torch | steps still named; in the dark from about 5 m (torch reach), or farther where street lamps light the floor | first distance in dim light vs daylight; any false «Gradino» in the dark |

<br>

## Get the numbers
1. On the iPhone: Files › On My iPhone › FieldVision › share the `fieldvision-….jsonl` file to the Mac.
2. `python3 tools/analyze_log.py fieldvision-….jsonl`
3. It prints: camera FPS, detector speed, how long guidance was reliable, false warnings per minute, the delay after every mark, and every spoken line.

Pitch line, only with your own measured numbers: «Misurato sull'iPhone, senza rete: avviso in __ s, __ falsi allarmi al minuto, __ occlusioni su __ con lo stesso ID.»
