# Nearby Sync: Two-Mac Test Plan

Nearby sync is opt-in, encrypted and pairing-only (see `CHANGELOG.md`, "Security"). The protocol, trust store, validator and store merge are covered by unit tests; the MultipeerConnectivity transport, the macOS permission prompt and real networks are not. This plan covers exactly that gap. Run it on two real Macs before announcing the feature.

Mark each line `[x]` pass, `[!]` fail (add a note), `[-]` not applicable.

## 0. Setup

| | Mac A | Mac B |
|---|---|---|
| Model / macOS version | | |
| Build (DMG name + `shasum -a 256`) | | |
| Network (SSID, same subnet?) | | |

- [ ] Both Macs run the **same Release DMG**: `./scripts/build-dmg.sh`, copy `dist/Versoline-<version>.dmg` to Mac B.
- [ ] First launch on Mac B: `xattr -cr /Applications/Versoline.app` (ad-hoc signed, see README "Gatekeeper Note").
- [ ] Both Macs are on the **same Wi-Fi/LAN**, not a guest network. Guest networks and "client isolation" block device-to-device traffic and make every test fail for the wrong reason.
- [ ] Both have a few feeds, a few read articles and bookmarks, and the two libraries are **different** (at least one feed only on A, one only on B, one shared).
- [ ] Open the in-app console on both (Developer Console); keep category filter on **Network**. Handy logs: "Nearby sync started", "Authenticated nearby device", "Nearby device refused: ...".
- [ ] Sync is **off** on both at the start (Settings > Sync).

Container path used below: `~/Library/Containers/com.bezelye.Versoline/Data/Library/Application Support/Versoline/`

## 1. Permission and "off means off"

- [ ] 1.1 With sync never enabled, launch the app: **no** macOS "local network" prompt appears.
- [ ] 1.2 On Mac A run `dns-sd -B _versoline-sync._tcp` in Terminal: nothing is advertised while sync is off (Ctrl-C after ~10 s).
- [ ] 1.3 Turn **Sync with My Paired Macs** on (Mac A): macOS asks for local network access with the text "Versoline uses the local network only to sync with your own paired Macs...". Allow.
- [ ] 1.4 `dns-sd -B _versoline-sync._tcp` now lists the Mac; after turning sync off again it disappears within a few seconds.
- [ ] 1.5 **Deny path:** on Mac B deny the prompt (or switch Versoline off in System Settings > Privacy & Security > Local Network), enable sync. The app must not crash; the status stays "Looking for your paired devices...". Re-allow the permission, toggle sync off/on: it recovers.

## 2. Pairing, happy path

- [ ] 2.1 Both Macs: sync on, Settings > Sync > **Pair New Device**. Both show "Open Pair New Device on your other Mac too..." with a spinner.
- [ ] 2.2 Within roughly 10-30 s **both** screens show "Does <other Mac> show this code?" with a six-digit code.
- [ ] 2.3 The two codes are **identical**.
- [ ] 2.4 Click **Codes Match** on both: both show "<name> is now paired."; the other Mac is listed under **Paired Devices** with a pairing date.
- [ ] 2.5 Status dot turns green, "1 paired device(s) connected".
- [ ] 2.6 Files exist on both Macs and are owner-only: `ls -l sync-identity.json sync-trusted-devices.json` shows `-rw-------`.
- [ ] 2.7 Within a few seconds the **snapshot** arrives (section 5 checks the content). "Last Synchronized" is filled in.
- [ ] 2.8 Click **Done**: pairing UI returns to "Pair New Device".

## 3. Pairing, failure and attack paths

For each case afterwards confirm: **no** device appears under Paired Devices on either Mac, and no data was exchanged.

- [ ] 3.1 **One-sided pairing:** only Mac A opens Pair New Device. Mac B (sync on, not pairing) never shows a prompt. After 120 s Mac A shows "No device was found. Open Pair New Device on the other Mac too." and **Try Again** works.
- [ ] 3.2 **Codes differ / user rejects:** on Mac A click **Codes Match**, on Mac B click **They Differ**. Both end in a failure message (B: pairing cancelled, A: "The other device rejected the pairing."). Repeat with the roles swapped.
- [ ] 3.3 **Cancel mid-way:** start pairing on both, cancel on one before confirming. Neither Mac ends up paired.
- [ ] 3.4 **No answer:** show the codes and wait without clicking. The pairing fails by itself after about 2 minutes ("Pairing timed out.").
- [ ] 3.5 **Stranger with sync on, not pairing:** with A and B paired, a **third** Mac C (or a second user account) enables sync but does not pair. A and B show no prompt, C sees no devices, no data reaches C.
- [ ] 3.6 **Pairing window closed:** with A and B already paired and **not** pairing, a Mac C opens Pair New Device. Neither A nor B reacts; C eventually times out.
- [ ] 3.7 **Wrong code attempt (optional, two people):** pair A with B while a third Mac C is also in pairing mode. Each pairing screen must show a code for exactly one peer; if codes ever differ between two screens that think they are talking to each other, choose **They Differ**.

## 4. Reconnect and robustness (no prompts expected)

After 2.x, with A and B paired:

- [ ] 4.1 Quit and relaunch Versoline on B: reconnects to A within about 30 s, **no** pairing prompt, status green on both.
- [ ] 4.2 Quit and relaunch on A (the other direction).
- [ ] 4.3 Put B to sleep for a minute, wake it: reconnects on its own.
- [ ] 4.4 Turn Wi-Fi off on B for 30 s, on again: reconnects. Count shows 0 while disconnected.
- [ ] 4.5 Turn sync **off** on A: B shows 0 connected; A stops being discoverable (`dns-sd`). Turn it on again: reconnects.
- [ ] 4.6 Both Macs with sync on, relaunch **both at the same time**: they end up with a single connection, not two (the count says 1 on each).
- [ ] 4.7 A third paired Mac (optional): A, B, C pairwise paired; all three connected shows 2 on each.

## 5. What gets synced

Do these with A and B connected. After each, **relaunch the receiving Mac** to prove the change was saved to disk, not only applied in memory.

**Snapshot after first pairing (section 2.7)**
- [ ] 5.1 The feed that existed only on A appears on B and loads articles (and vice versa). The shared feed is **not** duplicated.
- [ ] 5.2 Folders from A appear on B; feeds that were in A's folder are in that folder on B.
- [ ] 5.3 Articles read on A show as read on B (for articles B also has).
- [ ] 5.4 Bookmarks from A appear on B. **Bookmarks that existed only on B are still there** (union, never removed).
- [ ] 5.5 Pinned feeds keep their pinned state.
- [ ] 5.6 Appearance/reader settings: change the colour palette and font size on A; B adopts them within a few seconds. Change them on B; A adopts them. No ping-pong (values settle).

**Live changes**
- [ ] 5.7 Mark an article read on A: B shows it read within about 2 s, unread counts match.
- [ ] 5.8 Mark all read in a feed on A: B follows.
- [ ] 5.9 Bookmark and un-bookmark an article on A: B follows both directions.
- [ ] 5.10 Add a new feed on A: it appears on B and fetches its articles.
- [ ] 5.11 Move a feed into another folder, and out of any folder, on A (Manage Folders or sidebar): B follows. Pin / unpin a feed: B follows.
- [ ] 5.12 Delete a feed on A **while connected**: it disappears on B.

**Deletions and edits while the other Mac is offline (last writer wins, 90-day deletion records)**
- [ ] 5.13 Disconnect B (quit the app). On A delete feed X, rename folder F, move feed Y into another folder, unpin feed Z. Reconnect B: all four changes appear on B, X does **not** come back, and A is unchanged afterwards.
- [ ] 5.14 Disconnect B. On A delete feed X. On B (still disconnected) **edit** X afterwards (pin it, move it). Reconnect: the newer change wins (the edit on B, so X is back on A). Repeat with the delete done **after** the edit: X is deleted on both.
- [ ] 5.15 Delete feed X on A, let it sync, then re-add the same URL on B. After syncing, X exists on **both** Macs (a re-add beats the older deletion).
- [ ] 5.16 Delete a folder on A: B loses the folder and its feeds are listed under uncategorized, not hidden.
- [ ] 5.17 Both Macs offline, rename the same folder differently on each, reconnect: both end up with the **same** name (the later rename).
- [ ] 5.18 (optional) Set Mac B's clock a few minutes wrong and repeat 5.14: results may follow the wrong clock but both Macs must still agree with each other.

**Known limitations (expected; record what you see)**
- [ ] 5.19 A Mac that stays offline for more than **90 days** can bring back a feed or folder that was deleted in the meantime.
- [ ] 5.20 Un-bookmarking an article on A while B is offline: the bookmark comes back on A after B reconnects (bookmarks are still union-only; planned separately).

## 6. Trust management

- [ ] 6.1 **Remove** B on A (Paired Devices > Remove > confirm). A drops the connection; B now cannot reconnect: B keeps looking, shows no prompt, no data flows, A never accepts.
- [ ] 6.2 B still lists A under Paired Devices (trust is per Mac). Remove A on B, then pair again (section 2): works.
- [ ] 6.3 **Identity change:** on A quit the app, delete `sync-identity.json` (simulates a reinstall), relaunch. B refuses A ("identity ... changed" in the console, no data). Remove A on B, pair again: works.
- [ ] 6.4 **Factory reset** on A (Settings > Storage, reset all data). Sync is off afterwards, A lists no paired devices, `sync-*.json` are gone, and A does not appear to B as an authenticated device until re-paired (B must remove the old A first).
- [ ] 6.5 Copy `sync-trusted-devices.json` from A to a third Mac: the third Mac still cannot sync (it lacks A's private key). Optional.

## 7. Resources and privacy

- [ ] 7.1 Sync **on**, idle for 10 minutes: CPU in Activity Monitor stays near 0 %, no growth in memory beyond a few MB.
- [ ] 7.2 Sync **off**: no Bonjour advertisement (`dns-sd`), no local-network traffic from Versoline.
- [ ] 7.3 Optional (Little Snitch / `nettop -p Versoline`): during sync the only extra connections are to the other Mac's **local** address; nothing to the internet beyond normal feed fetching.
- [ ] 7.4 Console **Copy** while paired: no `?token=` style query strings, no `user:pass@`, no `/Users/<your name>` in the pasted text.
- [ ] 7.5 With sync on and a large library (500+ articles, 100+ bookmarks) the initial snapshot completes in a reasonable time (note seconds) without the UI stalling, and the app logs no "Dropped an oversized or malformed message".

## 8. Regression with sync off

- [ ] 8.1 Normal use for a few minutes: refresh, read, bookmark, OPML export, search. Nothing mentions sync, no permission prompt.
- [ ] 8.2 Feeds refresh when the app comes to the front and **not** while it is hidden in the background (watch the console "Starting concurrent refresh" lines, or Activity Monitor network use).
- [ ] 8.3 System Settings > Accessibility > Display > **Reduce motion** on: animations become short fades, no springs/bounces.

## 9. Report template

```
Build: <DMG / commit>        Mac A: <model, macOS>        Mac B: <model, macOS>        Network: <type>
Failed checks: <ids + what happened + console lines>
Surprises: <anything not covered>
```

If a pairing check fails, collect: both consoles (Copy), the files listed in 2.6 (`ls -l` only, never share their contents: `sync-identity.json` holds a private key), and the exact step.
