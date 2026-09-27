# Spoken Subtitles

Subtitles for the [Spoken](https://github.com/rusty-key/spoken-wow) voice player: what the NPC is saying, on screen, timed to the recording.

A separate addon on top of Spoken Player's public API (`API.lua`: `RegisterCallback`, `IsPaused`, `GetPlayerFrame`, `GetSettingsCategory`, `AddSettingsLink`, `IsCompatible`). It changes nothing in Spoken and needs nothing from its build pipeline.

## Prototype scope (0.1.0)

- **Text:** client language. Read from the quest dialog (`GetQuestText` / `GetProgressText` / `GetRewardText` / `GetGreetingText` / gossip) on the dialog events, short retries after them, and on `CLIP_QUEUED`. Quest clips are matched by key (`<questID>-<accept|progress|complete>`); gossip and greeting only by a read from the last 5 seconds.
- **Timing:** estimated. Each cue gets its share of `clip.length` by character count, with small pauses for sentence and paragraph ends. Stage directions (`<...>`) are shown in grey and cost little time, since they are mostly not spoken.
- **Display:** bottom-centre cinematic line, or below/above the player. Hidden while the quest or gossip window is open (the text is already there), while paused, and when off. Pause restarts at the first cue, because the player replays clips from the start.
- Quests only. Zones and books have no client text to read yet.

## Use

`/spsub` opens the settings (Spoken Player → Subtitles). Also:

```
/spsub screen | player | off   position
/spsub test                    sample line
/spsub move  /  /spsub lock    drag the screen line
/spsub debug                   the last text/timing decisions
```

## Tests

```
python tests/run.py
```

Real Lua 5.1 through Lupa, with a small WoW/Spoken mock (`tests/wow_mock.lua`).

## Next

- Spoken-language text and aligned timings, shipped as our own data keyed by the corpus `fileName` (= clip key), with a length check that falls back to client text when a line was re-recorded.
- Books (`ItemTextGetText`) and zones.
