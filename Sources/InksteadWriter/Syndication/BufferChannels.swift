import Foundation

/// Buffer fronts several networks, so its channels have to be named twice: once
/// in Inkstead's own vocabulary, which is what goes in a site's config and stays
/// there for the life of the site, and once in Buffer's, which is a third
/// party's internal value that can change under us.
///
/// The aliases below translate between the two. They are layered over a default
/// of passing the service through unchanged, so a network Buffer adds tomorrow
/// still resolves and still publishes; it just carries Buffer's own name until an
/// alias is added here.
///
/// Aliases are append-only. Once a token has been written into a site's
/// `inkstead-writer.json` it is a compatibility surface, not a naming choice, so
/// resolution accepts both the alias and the raw service name.
public enum BufferChannels {
    /// Inkstead's name for a service, keyed by Buffer's.
    static let aliasesByService: [String: String] = [
        "twitter": "x"
    ]

    /// Services Inkstead connects to directly, so offering them through Buffer
    /// would mean two paths to one account and a post arriving twice. Named by
    /// Inkstead's own vocabulary, matching `SyndicationProviderName`.
    static let nativelySupported: Set<String> = ["mastodon", "bluesky", "pixelfed", "flickr"]

    /// Services where a text-and-link post is not a sensible thing to send:
    /// they need video Inkstead never produces, or they publish by pushing a
    /// reminder to a phone rather than posting.
    static let unsupported: Set<String> = ["tiktok", "youtube", "youtubeshorts", "googlebusiness"]

    /// Services that carry a photo rather than a link, so only photo notes go to
    /// them. Instagram and Pinterest reject text-only posts.
    static let photoOnly: Set<String> = ["instagram", "pinterest"]

    /// Services built for long-form writing, which take the article itself
    /// rather than a headline pointing at it.
    ///
    /// These get the post's whole body with the link last, and they skip
    /// untitled notes: a one-line aside is not what someone opens LinkedIn to
    /// read, and sending it there would be posting to the wrong room.
    static let longForm: Set<String> = ["linkedin"]

    /// How much text a service accepts. Long-form bodies routinely run past
    /// these, so the body is trimmed and the link kept.
    static let characterLimits: [String: Int] = [
        "linkedin": 3000,
        "x": 280,
        "threads": 500
    ]

    public static func isLongForm(service: String) -> Bool {
        longForm.contains(token(forService: service))
    }

    public static func characterLimit(service: String) -> Int? {
        characterLimits[token(forService: service)]
    }

    /// Inkstead's token for one of Buffer's service values.
    public static func token(forService service: String) -> String {
        let normalized = service.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return aliasesByService[normalized] ?? normalized
    }

    /// True when a Buffer channel on this service matches the token's service
    /// part. Accepts Inkstead's alias and Buffer's raw name, so a token written
    /// by hand before an alias existed keeps resolving.
    public static func matches(token: String, service: String) -> Bool {
        let wanted = self.token(forService: token)
        return self.token(forService: service) == wanted
    }

    public static func isNativelySupported(service: String) -> Bool {
        nativelySupported.contains(token(forService: service))
    }

    public static func isUnsupported(service: String) -> Bool {
        unsupported.contains(token(forService: service))
    }

    public static func requiresPhoto(service: String) -> Bool {
        photoOnly.contains(token(forService: service))
    }

    /// Whether Inkstead offers this Buffer channel as a destination at all.
    /// Publishing to an unoffered service still works if someone writes the
    /// token by hand, because the decision here is about what to suggest, not
    /// about what the CLI will accept.
    public static func isOffered(service: String) -> Bool {
        !isUnsupported(service: service) && !isNativelySupported(service: service)
    }
}
