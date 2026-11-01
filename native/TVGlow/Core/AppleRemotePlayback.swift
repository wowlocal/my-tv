import Foundation

/// A subtitle track offered by the app playing on Apple TV.
struct SubtitleTrack: Equatable, Identifiable {
    let id: String
    let name: String
    let languageTag: String?
}

/// What the player on Apple TV lets the remote do while a show is loaded. Empty when idle.
struct AppleRemotePlayback: Equatable {
    /// Something is loaded (playing or paused).
    var active = false
    var canSkipBackward = false
    var canSkipForward = false
    var skipBackwardInterval = 10.0
    var skipForwardInterval = 10.0
    var subtitles: [SubtitleTrack] = []
    /// The subtitle track shown now; nil when subtitles are off.
    var subtitleID: String?
    /// The player's own default subtitle track.
    var defaultSubtitleID: String?

    var subtitlesOn: Bool { subtitleID != nil }
    /// Whether the row under the touch surface has anything to show.
    var hasControls: Bool { active && (canSkipBackward || canSkipForward || !subtitles.isEmpty) }

    /// SF Symbols draws the interval only for these values; others get the plain arrow.
    static func skipSymbol(forward: Bool, seconds: Double) -> String {
        let base = forward ? "goforward" : "gobackward"
        let whole = Int(seconds.rounded())
        return [5, 10, 15, 30, 45, 60, 75, 90].contains(whole) && abs(seconds - Double(whole)) < 0.01 ? "\(base).\(whole)" : base
    }
}

/// One audio or subtitle option, independent of the protocol library.
struct LanguageOptionInfo: Equatable {
    static let legibleType = 1
    static let forcedOnly = "public.subtitles.forced-only"

    var id: String
    /// 0 audible, 1 legible; nil when the player left it out (protobuf default: audible).
    var type: Int?
    var languageTag: String?
    var displayName: String?
    var characteristics: [String] = []

    /// Only an explicit legible type marks a subtitle. Audio is type 0, which protobuf may omit.
    var isLegible: Bool { type == Self.legibleType }
    /// Forced subtitles only translate foreign-language lines; they don't count as subtitles on.
    var isForcedOnly: Bool { characteristics.contains(Self.forcedOnly) }
}

struct LanguageGroupInfo: Equatable {
    /// Not used to find subtitles: players can set it on audio groups too, and treating
    /// audio as subtitles meant "subtitles off" switched the sound off.
    var allowsEmptySelection = false
    var defaultID: String?
    var options: [LanguageOptionInfo]
}

enum SubtitleChoice {
    /// The subtitle tracks among a player's options, the one enabled now and the player's default.
    static func resolve(groups: [LanguageGroupInfo], current: [LanguageOptionInfo]) -> (tracks: [SubtitleTrack], enabledID: String?, defaultID: String?) {
        var tracks: [SubtitleTrack] = []
        var defaultID: String?
        for group in groups {
            if defaultID == nil, let id = group.defaultID, group.options.contains(where: { $0.id == id && isSubtitle($0) }) { defaultID = id }
            for option in group.options where isSubtitle(option) && !tracks.contains(where: { $0.id == option.id }) {
                tracks.append(SubtitleTrack(id: option.id, name: name(of: option), languageTag: option.languageTag))
            }
        }
        return (tracks, shownSubtitles(in: current).first?.id, defaultID)
    }

    /// The selected options that are subtitles: what "subtitles off" disables. Never audio.
    static func shownSubtitles(in current: [LanguageOptionInfo]) -> [LanguageOptionInfo] {
        current.filter(isSubtitle)
    }

    private static func isSubtitle(_ option: LanguageOptionInfo) -> Bool { option.isLegible && !option.isForcedOnly }

    /// The track to turn on: the language picked last time, then the device's languages,
    /// then the player's default, then the first one.
    static func choose(from tracks: [SubtitleTrack], preferredTag: String?, defaultID: String?,
                       languages: [String] = Locale.preferredLanguages) -> SubtitleTrack? {
        if let preferredTag, let track = tracks.first(where: { $0.languageTag == preferredTag }) { return track }
        for language in ([preferredTag].compactMap { $0 } + languages) {
            let code = baseLanguage(language)
            if let track = tracks.first(where: { $0.languageTag.map(baseLanguage) == code }) { return track }
        }
        return tracks.first { $0.id == defaultID } ?? tracks.first
    }

    static func baseLanguage(_ tag: String) -> String {
        String(tag.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
    }

    private static func name(of option: LanguageOptionInfo) -> String {
        if let name = option.displayName, !name.isEmpty { return name }
        if let tag = option.languageTag, let name = Locale.current.localizedString(forIdentifier: tag) { return name }
        return option.languageTag ?? "Subtitles"
    }
}
