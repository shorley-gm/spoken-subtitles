# Spoken Subtitles

Subtitles for the [Spoken](https://github.com/rusty-key/spoken-wow) voice player: what the NPC is saying, on screen, timed to the recording.

A separate addon on top of Spoken Player's public API (`API.lua`: `RegisterCallback`, `IsPaused`, `GetPlayerFrame`, `GetSettingsCategory`, `AddSettingsLink`, `IsCompatible`). It changes nothing in Spoken and needs nothing from its build pipeline.

## What it does (0.3.0)

- **Player style:** Spoken's own player (default) or the **cinematic band**: a soft dark band above the action bars with the quest icon, name, quest title, the words and a hairline with the cast spark. No portrait, because the target frame already shows the speaker; a small round face appears only when the speaker is *not* your target (zones and books show their own picture there). It is a full player on Spoken's public API: click the band to pause/resume, hover for Spoken's gold pause glyph and a skip arrow, `+N` opens the waiting lines above the band (click one to remove it), right-click for stop, queue, the clip's own actions (Report) and settings. Drag to move; size, face and lock in the settings.
- While the band is chosen, Spoken's window is hidden **for the session only** (an `OnShow` hook on `Spoken:GetPlayerFrame()`). Nothing in Spoken's settings is written, so switching back or disabling this addon brings Spoken's window straight back.
- **Portraits:** native 2D snapshots (`SetPortraitTexture`) captured on `CLIP_QUEUED` while the NPC is the dialog unit or target, cached per creature (32), masked round, refreshed on `UNIT_PORTRAIT_UPDATE`. No 3D models.
- **Text:** client language, read from the quest dialog on the dialog events, short retries after them, and on `CLIP_QUEUED`. Quest clips are matched by key (`<questID>-<accept|progress|complete>`); gossip and greeting only by a read from the last 5 seconds.
- **Timing:** estimated from each cue's share of `clip.length`, with small pauses for sentence and paragraph ends. Stage directions (`<...>`) are greyed and cost little time.
- **Words start with the voice**, quest window open or not (optional hiding in the settings). Paused, the band's words dim; on resume they restart with the line.
- With Spoken's player, the words can go below it or at the bottom of the screen; each style remembers its own choice. Quests only for words; zones and books play without.

## Use

`/spsub` opens the settings (Spoken Player → Subtitles). Also:

```
/spsub band | spoken           player style
/spsub screen | player | off   where the words go (per style)
/spsub reset                   default positions and size
/spsub test                    sample line
/spsub move  /  /spsub lock    drag the screen line
/spsub debug                   the last text/timing decisions
```

## Tests

```
python tests/run.py
```

Real Lua 5.1 through Lupa, with a small WoW/Spoken mock (`tests/wow_mock.lua`) that models the public queue API (pause = stop, resume = replay, skip, remove, held reasons).

## Next

- Spoken-language text and aligned timings, shipped as our own data keyed by the corpus `fileName` (= clip key), with a length check that falls back to client text when a line was re-recorded.
- Books (`ItemTextGetText`) and zones.
- Ask Spoken for a small public call to suppress its window (`SetFrameSuppressed(owner, bool)`), replacing the `OnShow` hook.

## Artwork

`Media/FaceRing.tga` is cut from Forever Remastered's `unit-normal-weighted-fr221.tga` (ring only, the frame's bar joint rebuilt by angular interpolation). `GlyphPause`/`GlyphPlay` are Spoken's own (MIT) pause/play glyphs. `BandShade`, `BandLine`, `FaceDisc` and `FaceMask` are generated. The spark and skip arrow are the client's own textures, referenced by path.
