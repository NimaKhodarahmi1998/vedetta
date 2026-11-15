# Vedetta
Guide blind and low-vision pedestrians through the street with just an iPhone camera.

<br>

## Overview
Vedetta turns an iPhone worn on the chest into a guide that looks ahead while you walk. It builds a live 3D map of the street, speaks only what matters, and says clearly when it can't see. Everything runs on the phone, with no LiDAR, internet or account, in Italian and English. It works alongside a white cane or a guide dog, never in place of them.

Built by Team Eclipse, Nima Khodarahmi and Lorenzo Matrullo, for The Big Hack 2026, challenge "FieldVision – When Sight Is Not Enough" by Mare Group.

<br>

## How It Works
- **3D map:** ARKit tracks the phone in meters, and a depth model turns each picture into distances. The result is a live map drawn as Gaussian splats with Metal.
- **People and vehicles:** YOLO11n finds people, bikes and cars about 12 times a second and places each one in 3D. Someone who steps behind an obstacle is remembered for 3 seconds and keeps the same number when they reappear.
- **The path ahead:** walls, obstacles, low objects from about 7 cm, and steps and stairs out to 30 m are spoken with their side and distance. Something fast crossing the path interrupts everything else.
- **Self-check:** light, contrast, tracking and frame rate are checked all the time. When the picture can't be trusted, Vedetta says why and turns on the torch in the dark, rather than guessing.
- **Sound and touch:** a soft tick every 2 seconds means the street is being seen. One knock means something ahead, two strong pulses mean danger, and two long pulses mean the guide can't see.
- **Siri and VoiceOver:** say "I'm going out with Vedetta" to start. With VoiceOver on, the map reads as plain sentences and the guide speaks through VoiceOver.

<br>

## Requirements
- iPhone with iOS 18 or later. LiDAR isn't needed.
- Xcode 26 or later.

<br>

## Getting Started
1. Open `FieldVision.xcodeproj`.
2. In Signing & Capabilities, choose your team. If the bundle identifier is taken, change it.
3. Connect your iPhone with Developer Mode on, select it, then press Command-R.
4. Open Vedetta, tap Avvia (Start) and allow the camera.

For the most natural voice, download Alice (Enhanced) or a Premium voice in Settings › Accessibility › Spoken Content › Voices.

To see how Vedetta reads the street, open `website/index.html` in Safari or Chrome while connected to the internet.
