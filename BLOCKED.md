# BLOCKED — needs Arya's hands (2026-09-22 publish run)

Each heading is one decision or action only Arya can take. The publish check
(`scripts/check-published.sh`) carries every heading below into `PUBLISHED.md`, so nothing
here is silently dropped. Nothing in this file was faked or waited on; the queue continued.

## Real iPhone: install 0.8.0 OTA and exercise it
Apps tab → LeSearch AI → Install (0.8.0 is served OTA from the Mac daemon; cable +
`mesh apps install meshwatch` also works). Then try the remote keyboard, gestures, the Live
Activity and the Choose cards on the phone and on the watch. The unattended proof below used
a fresh simulator, never a physical device.

## Re-pair the real phone and watch to `pi`
Its token was rotated twice on 2026-09-22.

## Vercel AI Gateway card + rotate `AI_GATEWAY_API_KEY`
The key was pasted in chat once; it lives in `~/.config/secrets.env`. Add a card to the team
before fx / Jev can answer.

## CloudKit container decision for the Hundred app's friend sync

## Attended VNC credential flow on the live Mac (stage only)
ADR platform-shape §6 slice 2. Never driven unattended.
