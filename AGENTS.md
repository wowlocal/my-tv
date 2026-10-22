# TV Glow project instructions

- Commit each completed, reviewable change and immediately push that commit to `origin`. A local commit alone does not complete a step. Report any push failure clearly and resolve it when possible.
- Repository: `https://github.com/wowlocal/my-tv.git`. Push completed changes to this repository through `origin`.
- Prioritize the native macOS SwiftUI app. Do not download iOS platforms or bootstrap a simulator unless Anna asks. Keep shared code suitable for a later iOS version.
- The app controls an LG C1 OLED and a Living Room Sonos Arc Ultra directly on the local network. Preserve independent TV and soundbar operation, live readback, and Keychain pairing storage.
- Opening, reconnecting and refreshing must only read device settings. Never apply a preset automatically.
- During live tests in Anna’s dark room, keep TV brightness at or below its initial level. It was 0% during the first session. For volume tests, read the initial level, lower it gently, then restore that initial level. Never use a loud test level.
- Keep pairing keys, `.state/`, `.venv/`, DerivedData, build products, personal Xcode settings and logs out of Git.
- Test with the Debug bundle ID and install it separately as `TV Glow Dev.app`. Never replace the production app with a Debug build. Keep development and production Keychain services isolated by bundle ID.
- Never use Sites, `chatgpt.site`, or `.openai/hosting.json`. Use local/LAN web previews unless Anna selects another provider.
- For any web launch, restart, stop, preview or changed usable URL, follow `/Users/anna/.agents/skills/record-deployment-links/SKILL.md`: bind phone previews to `0.0.0.0`, verify the physical-network LAN URL, save one enabled/pinned Snippets entry with only that URL, run the PID-bound watcher, and verify it with `snippets-cli get`. Native app launches do not need web hosting.
- Current web entry: Snippets keyword `app-tv-glow`. Preserve its last URL and mark it offline when the server stops.

## Native validation

From `native/`, build the `TV Glow macOS` scheme with `xcodebuild`, run its macOS unit tests for behavioral changes, verify the release signature, and inspect the installed app through the native UI. Use a clean app-bundle replacement when switching Debug/Release configurations; copying over an old bundle can leave debug dylibs that invalidate signing.

Tests must use fake devices. Real device tests require explicit, gentle actions and confirmed readback. Retain licenses when adapting third-party protocol code. Do not claim iOS delivery based solely on shared source or an unsigned build.
