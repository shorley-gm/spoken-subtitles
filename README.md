# Spoken Subtitles

Subtitles for the [Spoken](https://github.com/rusty-key/spoken-wow) voice player: what the NPC is saying, on screen, timed to the recording.

A separate addon on top of Spoken Player's public API (`API.lua`: `RegisterCallback`, `IsPaused`, `GetPlayerFrame`, `GetSettingsCategory`, `AddSettingsLink`, `IsCompatible`). It changes nothing in Spoken and needs nothing from its build pipeline.

## What it does (0.2.0)

- **Player style:** Spoken's own player (default) or the **talking head**: portrait in the Forever Remastered ring, name, quest title, the words and a thin progress line. It is a full player on Spoken's public API: click the portrait to pause/restart, click the name to skip, `+N` opens the waiting lines (click one to remove it), right-click for pause, skip, stop all, the queue, the clip's own actions (Report) and settings. Drag to move; size and lock in the settings.
- While the talking head is chosen, Spoken's window is hidden **for the session only** (an `OnShow` hook on `Spoken:GetPlayerFrame()`). Nothing in Spoken's settings is written, so switching back or disabling this addon brings Spoken's window straight back.
- **Portraits:** native 2D snapshots (`SetPortraitTexture`) captured on `CLIP_QUEUED` while the NPC is the dialog unit or target, cached per creature (32), masked round, refreshed on `UNIT_PORTRAIT_UPDATE`. No snapshot: the clip's fallback art, else a book. No 3D models.
- **Text:** client language. Read from the quest dialog (`GetQuestText` / `GetProgressText` / `GetRewardText` / `GetGreetingText` / gossip) on the dialog events, short retries after them, and on `CLIP_QUEUED`. Quest clips are matched by key (`<questID>-<accept|progress|complete>`); gossip and greeting only by a read from the last 5 seconds.
- **Timing:** estimated. Each cue gets its share of `clip.length` by character count, with small pauses for sentence and paragraph ends. Stage directions (`<...>`) are shown in grey and cost little time.
- **Where the words go:** inside the talking head, below Spoken's player, or at the bottom of the screen; each player style remembers its own choice. Hidden while the quest or gossip window is open, while paused, and when off.
- Quests only for words. Zones and books play in the talking head without words.

## Use

`/spsub` opens the settings (Spoken Player → Subtitles). Also:

```
/spsub head | spoken           player style
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

`Media/TalkingHeadRing.tga` is cut from Forever Remastered's `unit-normal-weighted-fr221.tga` (ring and level badge, the frame's bar joint rebuilt by angular interpolation). `TalkingHeadDisc` and `TalkingHeadMask` are generated circles.
