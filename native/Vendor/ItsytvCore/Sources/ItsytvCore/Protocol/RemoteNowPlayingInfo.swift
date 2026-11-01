import Foundation

/// The caption state Apple TV sends to remotes in the Companion `NowPlayingInfo` event
/// (`NowPlayingInfoKey`: a keyed archive of TVRemoteCore's `TVRCNowPlayingInfo`).
/// Only the two caption keys are read; everything else in the archive is skipped.
public struct RemoteNowPlayingInfo: Equatable, Sendable {
    /// Subtitles are showing in the player on screen.
    public var captionsEnabled: Bool?
    /// The player on screen has subtitles to switch.
    public var hasValidCaptionOptions: Bool?

    public init(captionsEnabled: Bool? = nil, hasValidCaptionOptions: Bool? = nil) {
        self.captionsEnabled = captionsEnabled
        self.hasValidCaptionOptions = hasValidCaptionOptions
    }

    /// Decodes the archive. Returns nil when it can't be read.
    public static func decode(_ data: Data) -> RemoteNowPlayingInfo? {
        guard let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        let delegate = SkipUnknownClasses()
        unarchiver.delegate = delegate
        unarchiver.setClass(ArchivedNowPlayingInfo.self, forClassName: "TVRCNowPlayingInfo")
        let root = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? ArchivedNowPlayingInfo
        unarchiver.finishDecoding()
        guard let root else { return nil }
        return RemoteNowPlayingInfo(captionsEnabled: root.captionsEnabled, hasValidCaptionOptions: root.hasValidCaptionOptions)
    }
}

/// Stands in for `TVRCNowPlayingInfo`; its encoder writes these keys as NSNumbers.
@objc(TVGlowArchivedNowPlayingInfo)
private final class ArchivedNowPlayingInfo: NSObject, NSCoding {
    let captionsEnabled: Bool?
    let hasValidCaptionOptions: Bool?

    init?(coder: NSCoder) {
        captionsEnabled = (coder.decodeObject(forKey: "captionsEnabled") as? NSNumber)?.boolValue
        hasValidCaptionOptions = (coder.decodeObject(forKey: "hasValidCaptionOptions") as? NSNumber)?.boolValue
    }

    func encode(with coder: NSCoder) {}
}

/// Any other class in the archive (metadata, images) decodes to an empty placeholder.
@objc(TVGlowArchivePlaceholder)
private final class ArchivePlaceholder: NSObject, NSCoding {
    init?(coder: NSCoder) { super.init() }
    func encode(with coder: NSCoder) {}
}

private final class SkipUnknownClasses: NSObject, NSKeyedUnarchiverDelegate {
    func unarchiver(_ unarchiver: NSKeyedUnarchiver, cannotDecodeObjectOfClassName name: String,
                    originalClasses classNames: [String]) -> AnyClass? {
        ArchivePlaceholder.self
    }
}
