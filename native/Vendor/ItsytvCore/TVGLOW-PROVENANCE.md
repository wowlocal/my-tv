# Vendored Apple TV protocol implementation

Upstream: https://github.com/nickustinov/itsytv-core

Pinned source revision: `5538245fc3baa030c7da90d919893b4bee64ca05`.

Copyright 2026 Nick Ustinov. Upstream explicitly identifies this package as MIT-licensed in its README. The retained MIT notice is from the same author's parent macOS project, https://github.com/nickustinov/itsytv-macos/blob/main/LICENSE, which uses this package. The snapshot's README refers to a LICENSE path that was absent at this revision.

Only runtime sources are vendored. Upstream tests and project instructions are omitted. App-level protocol integration tests use fake devices. SwiftProtobuf is pinned to 1.32.0, supporting the generated name-map API without the newer protoc/C++ toolchain submodules. SwiftSRP is pinned to the upstream lockfile's 2.2.0. Xcode's checked-in Package.resolved locks transitives.

TV Glow changes:

- The Apple TV credential service derives from the host app's bundle ID. Dev and Release therefore never use the upstream app's credentials or each other's credentials.
- Debug builds of TV Glow use private 0700/0600 sandbox files for development credentials, avoiding ad hoc signature Keychain prompts. They never migrate existing Keychain entries. Release keeps using Keychain.
- Pairing readiness is exposed so PIN entry waits for the TV challenge; disconnect clears a previous challenge.
- Intentional disconnect clears callbacks, preventing a cancelled connection from starting an unwanted reconnect.
- Client names and logging use the host TV Glow app identity.
- Companion and MRP reconnect retries (and the TVRC session fallback) run on the main queue instead of a global queue. Retrying `startMRPViaTunnel()` off the main thread raced `MRPManager.disconnect()` and crashed with EXC_BAD_ACCESS when iOS resumed the app.
- Subtitle and audio tracks (MRP language options). `ContentItem.pb.swift` and `CommandOptions.pb.swift` were regenerated, and `LanguageOption.pb.swift` was added. Each comes from the `.proto` files in `Proto/`, built with protoc 31.1 and protoc-gen-swift 1.32.0, matching the pinned SwiftProtobuf. Field numbers follow pyatv's MRP protobufs (ContentItem 5/6, CommandOptions 27, LanguageOption). The reconstructed `.proto` files, without the new fields, regenerate the original files byte for byte. `MRPManager` requests language options with the playback queue, publishes `languageOptions` and adds `setLanguageOption(_:enabled:)`. It also merges partial content-item updates instead of replacing the whole item, and keeps known tracks when a pushed queue omits them. `MediaCommand` adds `enableLanguageOption` / `disableLanguageOption`.

No private pairing credentials are included in this directory.
