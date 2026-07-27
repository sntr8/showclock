# QLab OSC integration

## Transport

- Protocol: UDP
- QLab listens on port 53000 (default, configurable in app)
- App binds its own socket to port 53001 so QLab replies arrive on the same socket we send from (POSIX `bind` before `sendto`)

## Connection flow

1. Send `/workspaces` — QLab replies with workspace list (JSON)
2. Extract `uniqueID` from first workspace
3. Send `/workspace/{id}/connect [passcode]` — registers this client for feedback. If the workspace has an OSC passcode set (Workspace Settings → OSC), QLab **silently ignores every subsequent message** from this client until a correct passcode is sent here — there's no separate error for later queries, they just get no reply. `isConnected` is only set true once this `/connect` reply itself comes back `status: "ok"`; don't shortcut that on the `/workspaces` reply, or a bad/missing passcode looks identical to a working connection with a slow/broken cue feed.
4. Start 1-second poll: `/workspace/{id}/selectedCues`

## Reply format

QLab replies are addressed to `/reply` + the original query path, e.g. querying
`/workspaces` gets a reply addressed to `/reply/workspaces` — the path is embedded
in the OSC address, not passed as an argument.

- Argument 0 (string): JSON payload (the only argument)

JSON shape: `{"status": "ok", "data": [...], "address": "...", "workspace_id": "..."}`. On error, `status` is `"error"`.

## Getting next cue

`/workspace/{id}/selectedCues` returns the currently highlighted cue in the QLab cue list — this is the cue that fires on the next Go press, i.e. the "next song." This is independent of whether a cue is currently running: QLab keeps the playhead on whatever cue is selected regardless of its play state, so a cue can be both "active" and still be what's reported here.

Relevant fields in each data item: `listName`, `name`, `number`. There is no `displayName` field. The app prefers `listName` (the label QLab actually shows in the cue list, e.g. "1: Track1.mp3") since `name` — the custom name — is frequently an empty string.

## Known limitations

- Only connects to the first workspace found
- No reconnection on network drop (restart the connection via Settings → Connect)
- QLab must have OSC control enabled (Workspace Settings → OSC)
