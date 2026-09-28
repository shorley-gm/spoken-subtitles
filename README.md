# Spoken Subtitles

Subtitles for the [Spoken](https://github.com/rusty-key/spoken-wow) voice player: what the NPC is saying, on screen, timed to the recording.

A separate addon on top of Spoken Player's public API (`API.lua`: `RegisterCallback`, `IsPaused`, `GetPlayerFrame`, `GetSettingsCategory`, `AddSettingsLink`, `IsCompatible`). It changes nothing in Spoken and needs nothing from its build pipeline.

## What it does (0.4.0)

- **Player style:** Spoken's own player (default) or the **cinematic band**: a soft dark band above the action bars with the quest icon, name, quest title, the words and a hairline with the cast spark. No portrait, because the target frame already shows the speaker; a small round face appears only when the speaker is *not* your target (zones and books show their own picture there). It is a full player on Spoken's public API: click the band to pause/resume, hover for Spoken's gold pause glyph and a skip arrow, `+N` opens the waiting lines above the band (click one to remove it), right-click for stop, queue, the clip's own actions (Report) and settings. Drag to move; size, face and lock in the settings.
- While the band is chosen, Spoken's window is hidden **for the session only** (an `OnShow` hook on `Spoken:GetPlayerFrame()`). Nothing in Spoken's settings is written, so switching back or disabling this addon brings Spoken's window straight back.
- **Portraits:** native 2D snapshots (`SetPortraitTexture`) captured on `CLIP_QUEUED` while the NPC is the dialog unit or target, cached per creature (32), masked round, refreshed on `UNIT_PORTRAIT_UPDATE`. No 3D models.
- **Text:** client language, read from the quest dialog on the dialog events, short retries after them, and on `CLIP_QUEUED`. Quest clips are matched by key (`<questID>-<accept|progress|complete>`); gossip and greeting only by a read from the last 5 seconds.
- **Timing:** estimated from each cue's share of `clip.length`, with small pauses for sentence and paragraph ends. Stage directions (`<...>`) are greyed and cost little time.
- **Words start with the voice**, quest window open or not (optional hiding in the settings). Paused, the band's words dim; on resume they restart with the line.
- With Spoken's player, the words can go below it or at the bottom of the screen; each style remembers its own choice.
- **Books:** every page the reader has open (`ITEM_TEXT_READY`) is remembered by title and page number, which Spoken Books shows as the clip's header and label. A page gets words once it has been on screen, before or while it is read out; HTML letters are reduced to plain text.
- **Zones:** Spoken Zones keeps its lore private, so `Data/Zones_<locale>.lua` carries a generated copy of the `full` text (what the recordings speak), keyed by clip key (`z:<mapID>`, `s:<mapID>:<area>`). Only English and the client's language are kept in memory. A text whose speech rate does not fit the recording (outside 8-22 characters a second) is not shown. Regenerate with `python tools/build_zone_text.py [SpokenZones folder]`.

## Install

Needs [Spoken Player](https://www.curseforge.com/wow/addons/spoken-player) and at least one of Spoken Quests, Spoken Books or Spoken Zones. Put the `SpokenSubtitles` folder into `Interface/AddOns` and restart the game.

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

## Package

```
python tools/package.py
```

Writes `dist/SpokenSubtitles-<version>.zip` (the `SpokenSubtitles` folder only, version from the TOC).

## Next

- Spoken-language text, shipped as our own data keyed by the corpus `fileName` (= clip key), with a length check that falls back to client text when a line was re-recorded.
- Pause detection in the recordings, only if the estimated timing drifts noticeably in play.

## Artwork

`Media/FaceRing.tga` is cut from Forever Remastered's `unit-normal-weighted-fr221.tga` (ring only, the frame's bar joint rebuilt by angular interpolation). `GlyphPause`/`GlyphPlay` are Spoken's own (MIT) pause/play glyphs. `BandShade`, `BandLine`, `FaceDisc` and `FaceMask` are generated. The spark and skip arrow are the client's own textures, referenced by path.
