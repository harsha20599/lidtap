# Product
<!-- impeccable:product-schema 1 -->

## Platform
Native macOS (SwiftUI + AppKit), menu bar utility. The schema has no `macos` value; the closest guidance is the native-Apple (ios) reference, applied with macOS conventions.

## Users
MacBook users (Apple Silicon, M2 or later, or M1 Pro/Max) who want a few physical shortcuts on their screen: people in back-to-back video calls, people who live across several desktop Spaces, people who keep music playing while they work. They are at their desk or on a sofa with the laptop open, often mid-task, and want an action without reaching for the keyboard.

## Product Purpose
Turn a gentle tap on a zone of the laptop display into an action (switch Space, play/pause, next/previous track, new note, open an app, Privacy Guard), with no touch hardware.

## Positioning
The laptop already contains the sensor: the motion sensor in the base feels the whole machine twist about the hinge when the lid is tapped. LidTap learns, per machine, what a tap in each zone feels like. No other product turns the existing display into tap zones without extra hardware.

## Operating Context
- Always-on menu bar app; the menu panel is opened for a glance, a toggle, or a quick change.
- Settings window is used to assign actions, calibrate, and inspect how well taps are recognised.
- Calibration is a full-screen, two-minute task done once (and topped up).
- Privacy Guard is used under social pressure (someone walks up mid-call) and must be instant and calm.

## Capabilities and Constraints
- Zones are coarse (2×2, 2×3, 3×3); accuracy is measured and shown honestly (cross-validated), never claimed.
- Undocumented motion sensor; accuracy changes with lid angle and surface.
- Needs Accessibility (key events) and sometimes Input Monitoring; Automation for Google Meet tabs.
- Ad-hoc signed build; macOS 14+ deployment, running on macOS 27.

## Brand Commitments
Name: LidTap. Voice: calm, plain, exact. Words: "zone", "tap", "bump" (something that isn't a tap), "calibrate", "Privacy Guard".

## Evidence on Hand
Real recorded taps (60, 2×2) with 95% cross-validated accuracy. No user testimonials, no usage statistics: never fake them.

## Product Principles
1. The screen is the interface: every surface shows the zones where they physically are.
2. Every tap gets an answer: done, ignored (and why), or not sure.
3. Honest numbers: accuracy is measured on taps the model never saw.
4. Native first: a Mac user should know every control without learning it.
5. Privacy Guard is instant, total, and undoable with one tap or click.

## Accessibility & Inclusion
WCAG AA contrast in light and dark; full keyboard reach in Settings; VoiceOver labels on every zone and status; Reduce Motion replaces ripples and scaling with crossfades; state is never carried by colour alone.
