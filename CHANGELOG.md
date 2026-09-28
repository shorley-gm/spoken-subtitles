# Changelog

## 0.4.1

- Fixed: lines could start paused (for example a new zone) with no sound. Spoken remembers a pause even after the paused line is gone; with the band there is no Spoken window to show it. A pause with nothing left to resume is now let go.
- Fixed: clicks on the world beside the band's words (an NPC, loot, the ground) paused the voice. Only the name row and the words take clicks now, and a fading band none.

## 0.4.0

First public release.

- Subtitles for Spoken Quests (quest accept, progress, complete; gossip and greetings), Spoken Books (every page that has been open) and Spoken Zones (zone and subzone lore, generated text under CC BY-SA 4.0).
- Two player styles: Spoken's own window with the words below it or at the bottom of the screen, or the cinematic band: a soft band above the action bars with name, title, the words and a progress line. Click to pause, hover for pause and skip, `+N` for the waiting lines, right-click for stop, queue, Report and settings.
- A small round face in the band only when the speaker is not your target.
- Words in the client's language, timed by an estimate from the recording's length.
- Settings under Spoken Player → Subtitles, or `/spsub`.
