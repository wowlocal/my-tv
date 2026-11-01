import Foundation

/// What the player on Apple TV lets the remote do right now. Empty when nothing is playing.
struct AppleRemotePlayback: Equatable {
    /// A player is up (playing or paused), so the Remote app's playback row shows.
    var active = false
    var canSkipBackward = false
    var canSkipForward = false
    var skipBackwardInterval = 10.0
    var skipForwardInterval = 10.0
    /// Apple TV reported subtitle state, so the subtitles button can switch them.
    var canToggleSubtitles = false
    /// Subtitles are showing (the player's own state when Apple TV reports it).
    var subtitlesOn = false

    var hasControls: Bool { active }

    /// Companion `_mcF` bits (pyatv's protocol notes; computed by Apple TV's rapportd).
    enum Flag {
        static let play: UInt64 = 0x1
        static let pause: UInt64 = 0x2
        static let skipForward: UInt64 = 0x200
        static let skipBackward: UInt64 = 0x400
    }

    /// `_mcs` values of Companion's caption settings commands (from Apple's rapportd): the
    /// fallback for Apple TVs that don't report the player's subtitles.
    enum Captions {
        static let alwaysOn = 2
        static let off = 3
    }

    /// Builds the row's state. `flags` are Companion's media-control flags, which follow the
    /// player on screen the way the Remote app does: they clear when you leave the player for
    /// the shows grid. Until Apple TV has sent any (nil), MRP's now-playing state stands in.
    /// Subtitles come from the player (`captionsEnabled`, Companion NowPlayingInfo) when Apple TV
    /// reports them, else from the system `captionSetting`. NowPlayingInfo's
    /// `hasValidCaptionOptions` isn't used: the TV app reports false even for shows with subtitles.
    static func make(flags: UInt64?, nowPlaying: Bool, mrpSkipBackward: Bool, mrpSkipForward: Bool,
                     skipBackwardInterval: Double = 10, skipForwardInterval: Double = 10,
                     captionsEnabled: Bool? = nil, captionSetting: Int?) -> AppleRemotePlayback {
        var playback = AppleRemotePlayback()
        if let flags {
            playback.active = flags & (Flag.play | Flag.pause | Flag.skipForward | Flag.skipBackward) != 0
            playback.canSkipBackward = playback.active && (flags & Flag.skipBackward != 0 || mrpSkipBackward)
            playback.canSkipForward = playback.active && (flags & Flag.skipForward != 0 || mrpSkipForward)
        } else {
            playback.active = nowPlaying
            playback.canSkipBackward = nowPlaying && mrpSkipBackward
            playback.canSkipForward = nowPlaying && mrpSkipForward
        }
        playback.skipBackwardInterval = skipBackwardInterval
        playback.skipForwardInterval = skipForwardInterval
        if let captionsEnabled {
            playback.canToggleSubtitles = playback.active
            playback.subtitlesOn = captionsEnabled
        } else {
            playback.canToggleSubtitles = playback.active && captionSetting != nil
            playback.subtitlesOn = captionSetting == Captions.alwaysOn
        }
        return playback
    }

    /// SF Symbols draws the interval only for these values; others get the plain arrow.
    static func skipSymbol(forward: Bool, seconds: Double) -> String {
        let base = forward ? "goforward" : "gobackward"
        let whole = Int(seconds.rounded())
        return [5, 10, 15, 30, 45, 60, 75, 90].contains(whole) && abs(seconds - Double(whole)) < 0.01 ? "\(base).\(whole)" : base
    }
}
