import Foundation

/// An audio or subtitle track the playing app offers (MediaRemote "language option").
public struct MediaLanguageOption: Hashable, Sendable {
    /// MPNowPlayingInfoLanguageOptionType: 0 audible, 1 legible (subtitles and captions).
    public static let legibleType: Int32 = 1

    public let identifier: String?
    /// nil when the player left the type out; protobuf's default then means audible.
    public let type: Int32?
    public let languageTag: String?
    public let displayName: String?
    public let characteristics: [String]
    /// The option exactly as received, sent back to enable or disable it.
    let message: MRP_LanguageOption

    init(_ message: MRP_LanguageOption) {
        self.message = message
        identifier = message.hasIdentifier ? message.identifier : nil
        type = message.hasType ? message.type : nil
        languageTag = message.hasLanguageTag ? message.languageTag : nil
        displayName = message.hasDisplayName ? message.displayName : nil
        characteristics = message.characteristics
    }
}

public struct MediaLanguageOptionGroup: Hashable, Sendable {
    public let allowsEmptySelection: Bool
    public let defaultOption: MediaLanguageOption?
    public let options: [MediaLanguageOption]

    init(_ group: MRP_LanguageOptionGroup) {
        allowsEmptySelection = group.allowEmptySelection
        defaultOption = group.hasDefaultLanguageOption ? MediaLanguageOption(group.defaultLanguageOption) : nil
        options = group.languageOptions.map(MediaLanguageOption.init)
    }
}

/// The tracks the current item offers and the ones selected now.
public struct MediaLanguageOptions: Hashable, Sendable {
    public let available: [MediaLanguageOptionGroup]
    public let current: [MediaLanguageOption]
}
