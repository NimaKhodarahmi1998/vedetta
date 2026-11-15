# Vedetta · iPhone app
A guide for blind and low-vision pedestrians, for **The Big Hack 2026** (Codemotion, Napoli), challenge 03 **"FieldVision – When Sight Is Not Enough"** by Mare Group.

**Team Eclipse:** Nima Khodarahmi · Lorenzo Matrullo

The phone, worn on the chest, builds a live 3D map ahead of the walker (drawn as Gaussian splats). It names only what matters, keeps track of a person hidden for a moment, says clearly when it can't see, and switches the torch on in the dark. Italian and English. Any iPhone on iOS 18+ (the same iPhones as iOS 17), no LiDAR, no internet, no API keys.

The interface follows the web prototype and Apple's design: SF text styles, Apple's system colours in light and dark appearance, Liquid Glass on iOS 26 and Apple-style subtitles. The 3D map is minimal, like a car's driving view: shades of grey fading into fog, a faint path, and red only for danger. The code builds in Swift 6, with the main actor as the default.

<br>

## In breve (italiano)
**Vedetta** è una guida per chi non vede o vede poco. L’iPhone, all’altezza del petto, dice cosa c’è davanti mentre si cammina (persone, bici e auto, ostacoli, muri, gradini e scale) e **dice chiaramente quando non può fidarsi di ciò che vede**. Funziona senza rete, su un iPhone senza LiDAR, e nessun dato lascia il telefono. Non sostituisce il bastone o il cane: li affianca.

- **Primo avvio:** una breve guida parlata spiega come tenere il telefono e fa sentire i quattro suoni e il tocco lungo. Si riapre da «Come funziona».
- **I suoni:** tic ogni 2 s = vedo la strada · un colpo = qualcosa davanti · due impulsi forti = pericolo · lungo-lungo = non mi fido di ciò che vedo. Se il tic si ferma, la strada non è verificata.
- **Le frasi hanno una priorità:** un pericolo interrompe una frase meno importante, mai il contrario, e nessuna frase importante va persa.
- **Ammette quando non vede:** obiettivo coperto; troppo buio (prima lo dice, poi prova la torcia); superficie liscia; «Attenzione: non vedo il pavimento» dove il pavimento finisce.
- **Ricorda:** chi si nasconde per qualche secondo dietro un ostacolo resta la stessa persona, con lo stesso numero. Un **tocco lungo** segna un ostacolo, e Vedetta lo ricorda quando ci si torna vicino (con VoiceOver: azione «Segna ostacolo»).

### Cosa non vede
Pali sottili e oggetti sotto i 10 cm · scale in discesa viste dall’alto (si vede solo il primo gradino) · ciò che resta fuori dall’inquadratura · folla fitta, riflessi e controluce forti · con una sola fotocamera e senza LiDAR, le distanze sono stime. **Il bastone resta lo strumento principale.**

### Misurare
Ogni sessione scrive un file `.jsonl` (File › Sul mio iPhone › Vedetta).
- `python3 tools/analyze_log.py <file>`: tempi di reazione dopo ogni segno (triplo tocco sulla fotocamera), recuperi, persone ritrovate con lo stesso numero, frasi su gradini e scale, frasi in attesa o perse, fps al primo e all’ultimo minuto.
- `python3 tools/route_map.py <file>`: il percorso visto dall’alto, verde dove la guida era affidabile («visto»), giallo dove non lo era («non visto»).

### Licenze
Profondità: Depth Anything V2 Small (build Core ML di Apple), Apache-2.0. Persone e veicoli: **YOLO11n di Ultralytics, AGPL-3.0**, usato per il prototipo. Per un’app da distribuire, la strada è un rilevatore Apache-2.0 (RF-DETR-N o D-FINE-N) addestrato su dati CC BY, oppure la licenza Enterprise di Ultralytics. Tutto il resto (Vision, ARKit, Core ML, AVFoundation) è di Apple e gira sul telefono.

<br>

## Version
This repository holds the version submitted to the jury on 15 November 2026.

<br>

## Run it
1. Open `FieldVision.xcodeproj` (Xcode 26 or later).
2. Target **FieldVision** › Signing & Capabilities › **Team**: your Apple ID. If the bundle ID is taken, change it (e.g. `it.bighack.fieldvision.yourname`).
3. Plug in the iPhone (Developer Mode on), choose it at the top, press **⌘R**.
4. On the phone: every time it opens, the app asks «Vuoi avviare la guida?» (Start Guidance?), aloud too unless VoiceOver is on. Tap **Avvia** (Start) and allow the camera. The app speaks the iPhone's language: Italian, or English for any other.
5. For a natural voice, like the web prototype's: in Settings › Accessibility › Spoken Content › Voices › Italiano, download **Alice (Enhanced)** or a Premium voice. The app picks the best voice installed.

<br>

## Siri
Say **"Esco con Vedetta"** or **"I'm going out with Vedetta"** (also "Avvia Vedetta", "Guidami con Vedetta"). Siri asks whether to start, and the app opens already guiding.

Siri's built-in phrases always include the app's name. For just **"Ehi Siri, sto uscendo"**: in Shortcuts, tap **+**, add the Vedetta action **Avvia la guida** (Start Guidance) and name the shortcut **Sto uscendo** (or **I'm going out**).

Leaving the app by mistake while guiding pauses guidance, says how to come back and sends a notification, «Vuoi tornare alla guida?». Answer with **"Ehi Siri, torna a Vedetta"** (or "Riprendi Vedetta", "Back to Vedetta") or tap the notification: the app opens already guiding. iOS doesn't let an app reopen itself or keep listening once you've left, so the spoken answer goes through Siri. VoiceOver reads it, and so does Siri through AirPods with Settings › Notifications › Announce Notifications on.

<br>

## How it works
- **3D map:** ARKit tracks the phone in metres. Its feature points, a per-pixel depth model (Depth Anything V2 Small, Apple's Core ML build, Apache-2.0) scaled to metres with those points, and ARKit wall planes become coloured splats (Metal).
- **People and vehicles:** YOLO11n (Core ML) about 12 times a second. Each person, bike or car is placed in 3D by a ray through their feet to the floor. States: maybe → confirmed (3 of 5) → hidden (remembered 3 s, same number) → lost.
- **What's in the path:** wall («Muro davanti», again as «Muro davanti, vicino» under 1 m, with «Passaggio a sinistra/destra» when a doorway is seen from 1.5 m or more), obstacle («Ostacolo davanti») with beeps that speed up, fast movers («Bici veloce da destra!»). A "person" close by must show a body (Apple's body pose): a towel or a coat is not one. The walker's own legs and feet are not another person.
- **Low objects close by:** the walking corridor is cut into 20 cm slices up to 3.7 m and the floor height read in each; something clearly above the floor's own noise (from ~7 cm within 2 m) is «Ostacolo basso», with beeps.
- **Steps and stairs, out to 30 m and across the whole picture (70°):** a second depth pass looks at the floor band of the picture (from just above the horizon down, whatever the phone's tilt). Each column of the depth picture is read from near to far like a cane: flat stretches of floor, and what lies between them. A vertical riser between two flat stretches is a step up; a lower floor that starts behind a hidden strip is a step down; a surface climbing at 20–50° is a staircase seen from far away. Neighbouring columns must agree on a straight edge at least 60 cm wide, seen in three pictures, before anything is said. Edges are kept where they are in the world, so a step is still known when it drops out of the picture right in front of the feet. Spoken once early in metres, with the side («Scale in discesa a 12 metri, a sinistra»), then close by in paces («Gradino in salita, tra 4 passi»); anything going down once more at the edge («…, proprio davanti»). A drop whose treads can't be seen from far is named carefully: «Attenzione: scale o dislivello in discesa». Stairs going up are never called «Ostacolo» or «Muro», and are named only close by, when the 3D map confirms a real step (a 7–26 cm rise that stays up or climbs again), so tables, chairs and boxes are not stairs. Nothing is ever called «in salita» while points lie well below the floor ahead. Low objects from ~7 cm («Ostacolo basso», with beeps) still come from the close-range reader.
- **Dim light and darkness:** below a picture brightness of 70/255 both models get a brightened, de-noised copy of the picture (same geometry); daylight is untouched. "Too dark" now starts exactly where the torch switches on, so dim light is never declared unreliable while the torch stays off. With the torch on, steps are read wherever the picture is lit (torch or street lamps), and people or vehicles that are clearly lit count beyond the torch's 5 m.
- **Self-check:** light, picture contrast, ARKit tracking and a frame watchdog. It warns after 0.3 s, clears after 1 s and says why. In the dark it first says it can't see, then tries the torch («Provo con la torcia»); a picture that stays flat with the torch on is a covered lens, and a hand over a lit lens is «obiettivo coperto» straight away. With the torch, guidance goes on within 5 m.
- **VoiceOver:** the map reads as plain sentences, fast movers first («Una bici veloce sulla destra, a 6 metri. Un muro davanti a te, a 2 metri, con un passaggio a sinistra.»), and the camera as the last message. With VoiceOver on, the guide speaks through VoiceOver, in the person's own voice and speed, never over it; urgent lines cut in.
- **Logs:** every session writes a `.jsonl` file (Files › On My iPhone › Vedetta). `tools/analyze_log.py` turns it into numbers, `tools/route_map.py` draws the seen / not seen route; `TESTPLAN.md` lists the real-life runs.

<br>

## Files
- `FieldVision/App.swift`: the entry point.
- `FieldVision/Guidance/`: `GuideEngine` (the controls and what the screens show), `Guide` (what is said and when), and `Pipeline/`, the AR loop: ground, depth, detections, the path ahead, the map overlay and what it publishes.
- `FieldVision/Perception/`: camera maths, the self-check and the automatic torch, and the two Core ML models.
- `FieldVision/Tracking/`: identities, occlusion, what is worth saying.
- `FieldVision/Map/`: building the 3D map, and the Metal splat renderer (shader compiled on the phone).
- `FieldVision/Feedback/`: every spoken line in Italian and English, sounds, vibrations and the log.
- `FieldVision/Screens/`: the SwiftUI screens. `InterfaceText` holds every line of interface copy.
- `FieldVision/Siri/`: the Start Guidance intent and its Siri phrases, in Italian and English.
- `FieldVision/Perception/Floor/FloorSteps.swift`: steps, stairs and drop-offs out to 30 m (pure maths, no ARKit); `FieldVision/Guidance/Pipeline/GuidancePipeline+Floor.swift`: wiring it in, plus low objects close by.
- `FieldVision/Perception/Light/LowLight.swift`: the brightened picture in dim light, and the floor band.
- `tools/steps-sim/`: Mac simulation of the floor reader: synthetic streets (curbs, stairs both ways, ledges, ramps, walls, people, cars, dark and night scenes, phone tilted 0/8/20°) ray-cast into depth pictures with depth-model-like errors, then fed through the same code the app runs. `tools/steps-sim/run.sh --seeds=3` (about 2 minutes).

<br>

## License
AGPL-3.0, see `LICENSE`. Third-party models inside the app: YOLO11n © Ultralytics, AGPL-3.0; Depth Anything V2 Small (Apple's Core ML build), Apache-2.0. Everything else runs on Apple's frameworks (ARKit, Vision, Core ML, AVFoundation) on the phone.
