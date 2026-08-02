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

Once `totalRemainingSeconds` does reach zero, the revert to the plain clock isn't instant — `QLabManager.remainingReachedZeroAt` records the moment it first hit zero, and `isShowingPlainClock` waits `AppSettings.overtimeHoldSeconds` (Cmd+, → Overtime, default 60s) past that before switching. If a genuinely unplanned encore gets fired afterward (as long as it's a cue QLab already knows about — see `hasSeenCuePosition` above), `totalRemainingSeconds` goes back above zero on the next poll, `remainingReachedZeroAt` clears, and the countdown/overtime view resumes — nothing about the hold is "sticky" past that point.

## Detecting when QLab itself disappears

UDP gives no disconnect signal — quitting QLab looks identical to a silent dropped packet. `QLabManager` tracks `lastReplyAt`, updated on *any* successfully parsed message from QLab (not just ones that dispatch somewhere). The poll timer checks it every tick: if more than 5 seconds have passed with `isConnected` still true, `markDisconnected()` fires (status → "Connection lost", all per-cue/cue-list state cleared) and the same timer's existing "no workspace → resend `/workspaces`" branch takes over, so a relaunched QLab gets picked back up automatically without the user re-clicking Connect.

## Remaining time (Settings only, not shown on the clock)

`totalRemainingSeconds` is the current cue's remaining time plus every armed, playable (Audio/Video/Mic) cue still ahead of it in the whole cue list — the operator's rest-of-show estimate, not just what's playing this instant. It needs three different pieces of QLab state stitched together:

- **The full cue order.** `/workspace/{id}/cueLists/uniqueIDs` returns the entire nested cue tree (bare `cueLists` gave no reply at all in testing — likely too large a payload for a single UDP datagram on a show of any real size; the `uniqueIDs` variant is small enough to always come back). Unlike `runningOrPausedCues` below, this endpoint reliably reports the *true* structure, so "cues" is empty if and only if a cue is an actual leaf — `buildCueOrder` flattens it depth-first into an ordered leaf list plus an ID→index lookup (a Group's index is its first descendant leaf's, since selecting a Group means everything in it is about to play).
- **Per-cue static info**, fetched once and cached forever (doesn't change): `/cue_id/{id}/type` and `/cue_id/{id}/duration` — no `/workspace/{id}/` prefix, unlike the workspace-listing queries above. `armed` is re-queried every poll instead, since an operator can arm/disarm live.
- **What's actually playing right now**, from `runningOrPausedCues` (see below) — gives live `actionElapsed` for whichever leaf(s) are mid-playback.
- **Every ancestor cue's `mode`** in each relevant leaf's containing-cue chain (not just its immediate parent — a Timeline group's own children are frequently wrapper Groups, e.g. one sub-Group per track for individual fades, so the *leaf's* immediate parent often isn't the Timeline group itself), fetched once and cached forever via `/cue_id/{id}/mode`. Needed to detect Timeline groups — see below.
- **Each leaf's own `continueMode`**, fetched once and cached forever, via `/cue_id/{id}/continueMode`. Needed to detect auto-continue chains — see below.

**Where to start summing from is the subtle part.** QLab typically advances the playhead (`selectedCues`) to the *next* cue immediately on Go, before the cue that just fired has finished playing — so `selectedCueID`'s position in the cue order can already be one step ahead of what's still actually audible. Starting the sum only from there silently skips the currently-playing cue's own shrinking remaining time, and the total stops ticking down while something is running (this shipped once — the fix is to start from whichever is earlier: the selected index, or the index of any cue actually known to be playing via `activeCueElapsed`).

**End of show is the same problem in reverse.** Once the very last cue in the list finishes, with nothing armed after it to keep something selected, QLab reports *neither* a selected cue nor anything playing — `selectedIndex` and `activeIndices` are both empty. Defaulting that to index 0 (a reasonable-looking fallback, since it's also what "genuinely hasn't started yet" looks like) re-sums the *entire, already-played* show as "remaining," which shipped once as a real bug: Settings showed the full show length as remaining right as the last cue ended, and — worse — `totalRemainingSeconds` could then never reach zero, which permanently blocked the overtime-hold grace period (see below) from ever completing. `hasSeenCuePosition` disambiguates the two: it's set the first time a real position is found, so an empty selection only defaults to 0 *before* that (truly pre-show); afterward it means "played through to the end," and the start index is `cueOrder.count` — one past the end — so the sum is correctly zero.

`runningOrPausedCues` nests Group cues around their actual playing children — a running Group can appear with an *empty* `cues` array of its own, so "leaf = empty cues array" is the wrong signal there specifically (unlike `cueLists/uniqueIDs` above); `type != "Group"` is the reliable signal for this endpoint (`flattenRunningLeafCueIDs` recurses through Groups and only collects non-Group `uniqueID`s).

Many non-audio/video cue types (MIDI, network, fade-target, etc.) return `0`/`0` for elapsed/duration — harmless, since the sum only includes cues whose cached `type` is Audio/Video/Mic. Disarmed cues are skipped (`cueArmed[id] ?? true` — default true while an armed-state reply is still in flight, so a network hiccup briefly overestimates rather than hiding real remaining time).

**Cues that start together (multiple tracks per cue) count once, not per track.** QLab has two distinct, commonly-used ways to build a "several tracks, one Go press" cue, and both are handled:

1. **Timeline groups.** QLab's Group cue `mode` property (`/cue_id/{id}/mode`, values `0`–`6`) is `3` for "Timeline" — the mode where every child cue starts simultaneously when the Group fires, e.g. stereo stems or a click track alongside a backing track nested inside one Group. `buildCueOrder` flattens those children into consecutive leaves in `cueOrder` and records each leaf's *entire* ancestor chain (`ancestorChain`), not just its immediate parent — a real show hit exactly this: the Timeline group's direct children were each an individual per-track wrapper Group (for per-track fades), so the tracks' immediate parents were four different sub-Groups, not the Timeline group itself, and the first version of this fix (immediate-parent-only) missed it completely, still summing every track independently. `timelineClusterRoot(for:)` walks the whole chain and uses the *outermost* Timeline-mode ancestor found, so leaves nested arbitrarily deep under wrapper Groups still cluster correctly as long as some ancestor up the chain is a Timeline group.
2. **Auto-continue chains.** No Group at all — flat, consecutive sibling cues in the cue list, where a cue's `continueMode` property (`/cue_id/{id}/continueMode`, `0`=Do Not Continue, `1`=Auto-continue, `2`=Auto-follow) is `1`: firing that cue immediately fires the next one in the list too. (Auto-follow, `2`, is excluded — that waits for the current cue to *finish* first, so it's genuinely sequential, not simultaneous.)

Either way, each leaf individually reports its own full track length via `duration` — so naively summing every leaf would multiply a single cue's length by its track count. `recomputeTotalRemaining` instead walks `cueOrder` once, merging a leaf into the previous leaf's cluster when `startsTogether` says they start at the same moment (same Timeline-mode parent, or the previous leaf's `continueMode == 1`), and adds only the longest remaining track in each cluster, since they all end around the same time. Leaves that don't start together (List/Playlist/Start First groups, or a cue with `continueMode == 0`/`2`) are summed individually as before, since those genuinely play one at a time. Cues that fire simultaneously *without* either of these two relationships (e.g. two independent, unrelated cues an operator has scheduled to overlap by hand) still each count in full — the fix only recognizes these two standard QLab mechanisms, so a heavily-overlapping show built without them will still over-estimate somewhat.

This *is* compared against the show end time in the UI (red "(overtime)" warning) — it's a genuine rest-of-show estimate, not just a snapshot of concurrently-playing cues.

## Known limitations

- Only connects to the first workspace found
- QLab must have OSC control enabled (Workspace Settings → OSC)
- `totalRemainingSeconds` only accounts for cue playback time — any manual pacing between cues (an operator waiting on a Go, on-stage banter) adds real time the estimate has no way to see, so the actual show typically runs *longer* than the number shown, not shorter. This is why Settings labels the projected end time "Ends earliest," not "Estimated end": the estimate is closer to a floor than an unbiased guess. (There's a separate, smaller bias in the *other* direction too — cues overlapping without using a Timeline group or auto-continue, see above — but the missing-pacing-time bias is the one that dominates in practice.)
