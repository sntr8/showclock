# QLab OSC integration

## Transport

- Protocol: UDP
- QLab listens on port 53000 (default, configurable in app)
- App binds its own socket to port 53001 so QLab replies arrive on the same socket we send from (POSIX `bind` before `sendto`)

## Connection flow

1. Send `/workspaces` — QLab replies with workspace list (JSON)
2. Extract `uniqueID` from first workspace
3. Send `/workspace/{id}/connect [passcode]` — registers this client for feedback. If the workspace has an OSC passcode set (Workspace Settings → OSC), QLab **silently ignores every subsequent message** from this client until a correct passcode is sent here — there's no separate error for later queries, they just get no reply. `isConnected` is only set true once this `/connect` reply itself comes back `status: "ok"`; don't shortcut that on the `/workspaces` reply, or a bad/missing passcode looks identical to a working connection with a slow/broken cue feed.
4. Once connected, poll every second: `/workspace/{id}/selectedCues`, `/workspace/{id}/runningOrPausedCues`, and `/workspace/{id}/cueLists/uniqueIDs`

The 1-second poll timer actually starts immediately in `start()`, before step 1 even completes — not just after a workspace is found. Before that, each tick just resends `/workspaces` instead of the cue queries. This matters because the initial `/workspaces` send is a single UDP packet with no inherent retry; if it's lost (e.g. QLab's OSC listener isn't fully up yet at the exact moment the app launches), nothing would ever resend it and the app would sit on "Connecting..." forever without this. It shipped that way once — a manual click of the Connect button worked (because it called `start()` fresh) when auto-connect-on-launch didn't, which is what exposed the bug.

## Reply format

QLab replies are addressed to `/reply` + the original query path, e.g. querying
`/workspaces` gets a reply addressed to `/reply/workspaces` — the path is embedded
in the OSC address, not passed as an argument.

- Argument 0 (string): JSON payload (the only argument)

JSON shape: `{"status": "ok", "data": [...], "address": "...", "workspace_id": "..."}`. On error, `status` is `"error"`.

## Getting next cue

`/workspace/{id}/selectedCues` returns the currently highlighted cue in the QLab cue list — this is the cue that fires on the next Go press, i.e. the "next song." This is independent of whether a cue is currently running: QLab keeps the playhead on whatever cue is selected regardless of its play state, so a cue can be both "active" and still be what's reported here.

Relevant fields in each data item: `listName`, `name`, `number`. There is no `displayName` field. The app prefers `listName` (the label QLab actually shows in the cue list, e.g. "1: Track1.mp3") since `name` — the custom name — is frequently an empty string.

QLab still reports a cue as "selected" even while it's disarmed, but a disarmed cue won't actually fire on Go — so the app checks `armed` and shows nothing ("No cue selected") rather than a cue that won't really play next. `armed` is encoded inconsistently by QLab (sometimes a JSON bool, sometimes an int 0/1), so `isCueArmed` checks both.

## Detecting when the show is actually over

`/workspace/{id}/runningOrPausedCues` returns cues currently playing or paused (empty array if nothing is); `QLabManager.hasActiveCues` is `!data.isEmpty` from this reply. There's no fixed overtime timeout at all — `AppSettings.isShowingPlainClock` keeps the countdown/overtime view up for as long as `totalRemainingSeconds` (see below) is above zero, and without a QLab connection there's no way to know the show is over, so it just keeps running rather than guessing.

## Detecting when QLab itself disappears

UDP gives no disconnect signal — quitting QLab looks identical to a silent dropped packet. `QLabManager` tracks `lastReplyAt`, updated on *any* successfully parsed message from QLab (not just ones that dispatch somewhere). The poll timer checks it every tick: if more than 5 seconds have passed with `isConnected` still true, `markDisconnected()` fires (status → "Connection lost", all per-cue/cue-list state cleared) and the same timer's existing "no workspace → resend `/workspaces`" branch takes over, so a relaunched QLab gets picked back up automatically without the user re-clicking Connect.

## Remaining time (Settings only, not shown on the clock)

`totalRemainingSeconds` is the current cue's remaining time plus every armed, playable (Audio/Video/Mic) cue still ahead of it in the whole cue list — the operator's rest-of-show estimate, not just what's playing this instant. It needs three different pieces of QLab state stitched together:

- **The full cue order.** `/workspace/{id}/cueLists/uniqueIDs` returns the entire nested cue tree (bare `cueLists` gave no reply at all in testing — likely too large a payload for a single UDP datagram on a show of any real size; the `uniqueIDs` variant is small enough to always come back). Unlike `runningOrPausedCues` below, this endpoint reliably reports the *true* structure, so "cues" is empty if and only if a cue is an actual leaf — `buildCueOrder` flattens it depth-first into an ordered leaf list plus an ID→index lookup (a Group's index is its first descendant leaf's, since selecting a Group means everything in it is about to play).
- **Per-cue static info**, fetched once and cached forever (doesn't change): `/cue_id/{id}/type` and `/cue_id/{id}/duration` — no `/workspace/{id}/` prefix, unlike the workspace-listing queries above. `armed` is re-queried every poll instead, since an operator can arm/disarm live.
- **What's actually playing right now**, from `runningOrPausedCues` (see below) — gives live `actionElapsed` for whichever leaf(s) are mid-playback.

**Where to start summing from is the subtle part.** QLab typically advances the playhead (`selectedCues`) to the *next* cue immediately on Go, before the cue that just fired has finished playing — so `selectedCueID`'s position in the cue order can already be one step ahead of what's still actually audible. Starting the sum only from there silently skips the currently-playing cue's own shrinking remaining time, and the total stops ticking down while something is running (this shipped once — the fix is to start from whichever is earlier: the selected index, or the index of any cue actually known to be playing via `activeCueElapsed`).

`runningOrPausedCues` nests Group cues around their actual playing children — a running Group can appear with an *empty* `cues` array of its own, so "leaf = empty cues array" is the wrong signal there specifically (unlike `cueLists/uniqueIDs` above); `type != "Group"` is the reliable signal for this endpoint (`flattenRunningLeafCueIDs` recurses through Groups and only collects non-Group `uniqueID`s).

Many non-audio/video cue types (MIDI, network, fade-target, etc.) return `0`/`0` for elapsed/duration — harmless, since the sum only includes cues whose cached `type` is Audio/Video/Mic. Disarmed cues are skipped (`cueArmed[id] ?? true` — default true while an armed-state reply is still in flight, so a network hiccup briefly overestimates rather than hiding real remaining time).

This *is* compared against the show end time in the UI (red "(overtime)" warning) — it's a genuine rest-of-show estimate, not just a snapshot of concurrently-playing cues, though cues that fire simultaneously each count in full, so a heavily-overlapping show will over-estimate somewhat.

## Known limitations

- Only connects to the first workspace found
- QLab must have OSC control enabled (Workspace Settings → OSC)
