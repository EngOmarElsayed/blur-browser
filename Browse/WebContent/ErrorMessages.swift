import Foundation

// MARK: - Browsing Error

enum BrowsingErrorCategory: String {
    case noInternet
    case dnsFailure
    case timeout
    case serverError
    case sslError
    case generic
}

struct BrowsingError {
    let category: BrowsingErrorCategory
    let message: ErrorMessage
    let errorCode: Int
    let errorDomain: String

    /// Classify an NSError into a browsing error with a random message
    static func from(_ error: NSError) -> BrowsingError? {
        // Never show error page for cancelled requests
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            return nil
        }

        let category = classify(error)
        let message = ErrorMessageBank.randomMessage(for: category)

        return BrowsingError(
            category: category,
            message: message,
            errorCode: error.code,
            errorDomain: error.domain
        )
    }

    /// Classify from an HTTP status code
    static func fromHTTPStatus(_ statusCode: Int) -> BrowsingError? {
        guard statusCode >= 500 else { return nil }
        let message = ErrorMessageBank.randomMessage(for: .serverError)
        return BrowsingError(
            category: .serverError,
            message: message,
            errorCode: statusCode,
            errorDomain: "HTTP"
        )
    }

    private static func classify(_ error: NSError) -> BrowsingErrorCategory {
        guard error.domain == NSURLErrorDomain else { return .generic }

        switch error.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed:
            return .noInternet
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
            return .dnsFailure
        case NSURLErrorTimedOut:
            return .timeout
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid, NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return .sslError
        default:
            return .generic
        }
    }
}

// MARK: - Error Message

struct ErrorMessage {
    let emoji: String
    let title: String
    let subtitle: String
}

// MARK: - Error Message Bank

enum ErrorMessageBank {

    static func randomMessage(for category: BrowsingErrorCategory) -> ErrorMessage {
        let messages: [ErrorMessage]
        switch category {
        case .noInternet:   messages = noInternet
        case .dnsFailure:   messages = dnsFailure
        case .timeout:      messages = timeout
        case .serverError:  messages = serverError
        case .sslError:     messages = sslError
        case .generic:      messages = generic
        }
        return messages.randomElement()!
    }

    // MARK: - No Internet

    private static let noInternet: [ErrorMessage] = [
        ErrorMessage(
            emoji: "📡",
            title: "The internet took a coffee break",
            subtitle: "Your connection wandered off. Check your WiFi or try yelling at your router."
        ),
        ErrorMessage(
            emoji: "🏝️",
            title: "You're on a digital island",
            subtitle: "No connection detected. Are you in a cave? A submarine? Check your network."
        ),
        ErrorMessage(
            emoji: "🐌",
            title: "Your WiFi is on vacation",
            subtitle: "It sent a postcard saying it'll be back soon. Maybe restart your router?"
        ),
        ErrorMessage(
            emoji: "🔌",
            title: "Someone tripped over the cable",
            subtitle: "We can't reach the internet right now. Make sure you're connected to a network."
        ),
        ErrorMessage(
            emoji: "🛸",
            title: "Connection abducted by aliens",
            subtitle: "Your network signal vanished into thin air. Check your WiFi settings."
        ),
    ]

    // MARK: - DNS Failure

    private static let dnsFailure: [ErrorMessage] = [
        ErrorMessage(
            emoji: "🔍",
            title: "This address doesn't exist in any known universe",
            subtitle: "We looked everywhere. Double-check the URL — there might be a typo."
        ),
        ErrorMessage(
            emoji: "🗺️",
            title: "Even GPS can't find this server",
            subtitle: "The domain name didn't resolve to anything. Is the URL spelled correctly?"
        ),
        ErrorMessage(
            emoji: "👻",
            title: "This site is a ghost",
            subtitle: "The server name doesn't exist. It might have been moved or you have a typo."
        ),
        ErrorMessage(
            emoji: "🏚️",
            title: "Nobody lives at this address",
            subtitle: "DNS couldn't find a server with that name. Check the URL and try again."
        ),
        ErrorMessage(
            emoji: "🧭",
            title: "Our compass is spinning",
            subtitle: "We can't figure out where this domain points. Verify the address is correct."
        ),
    ]

    // MARK: - Timeout

    private static let timeout: [ErrorMessage] = [
        ErrorMessage(
            emoji: "⏳",
            title: "We waited. And waited. And gave up.",
            subtitle: "The server took too long to respond. It might be overloaded or temporarily down."
        ),
        ErrorMessage(
            emoji: "🦥",
            title: "This server is slower than a sloth on melatonin",
            subtitle: "The connection timed out. The server might be busy — try again in a moment."
        ),
        ErrorMessage(
            emoji: "⏰",
            title: "Time's up, server didn't show",
            subtitle: "We rang the doorbell but nobody answered. The server might be overwhelmed."
        ),
        ErrorMessage(
            emoji: "🐢",
            title: "A turtle could've delivered this faster",
            subtitle: "The request timed out. Check your connection or try again later."
        ),
        ErrorMessage(
            emoji: "💤",
            title: "The server fell asleep on us",
            subtitle: "No response within the time limit. It might be napping or overloaded."
        ),
    ]

    // MARK: - Server Error

    private static let serverError: [ErrorMessage] = [
        ErrorMessage(
            emoji: "🔥",
            title: "The server is having an existential crisis",
            subtitle: "Something went wrong on their end. Not your fault — try again later."
        ),
        ErrorMessage(
            emoji: "💀",
            title: "The server said 'nah' and went to sleep",
            subtitle: "A server error occurred. The site's team probably already knows about it."
        ),
        ErrorMessage(
            emoji: "🤖",
            title: "The robots running this site are on strike",
            subtitle: "Internal server error. Give it a minute and hit retry."
        ),
        ErrorMessage(
            emoji: "🌋",
            title: "The server just erupted",
            subtitle: "Something catastrophic happened on the other end. Try again shortly."
        ),
        ErrorMessage(
            emoji: "🎰",
            title: "Server rolled a critical failure",
            subtitle: "The site's backend hit an error. It's not you, it's definitely them."
        ),
    ]

    // MARK: - SSL / Security Error

    private static let sslError: [ErrorMessage] = [
        ErrorMessage(
            emoji: "🕵️",
            title: "Something sketchy is going on here",
            subtitle: "The security certificate for this site is invalid or untrusted. Proceed with caution."
        ),
        ErrorMessage(
            emoji: "🔒",
            title: "The security guard said no entry",
            subtitle: "This site's SSL certificate has a problem. It might be expired or misconfigured."
        ),
        ErrorMessage(
            emoji: "🚨",
            title: "Your connection isn't private",
            subtitle: "The certificate couldn't be verified. Someone might be tampering with the connection."
        ),
        ErrorMessage(
            emoji: "🛡️",
            title: "Trust issues detected",
            subtitle: "We can't verify this site is who it says it is. The certificate looks suspicious."
        ),
        ErrorMessage(
            emoji: "⛔",
            title: "Nope, not safe to go in there",
            subtitle: "SSL handshake failed. The site's security setup is broken or untrusted."
        ),
    ]

    // MARK: - Generic / Unknown

    private static let generic: [ErrorMessage] = [
        ErrorMessage(
            emoji: "🤷",
            title: "Something broke and we're not sure what",
            subtitle: "An unexpected error occurred while loading the page. Try again?"
        ),
        ErrorMessage(
            emoji: "👾",
            title: "A wild error appeared!",
            subtitle: "Something went wrong but we can't pinpoint what. Retry might do the trick."
        ),
        ErrorMessage(
            emoji: "🪄",
            title: "The page vanished into thin air",
            subtitle: "We couldn't load this page for reasons unknown. Give it another shot."
        ),
        ErrorMessage(
            emoji: "🧩",
            title: "A piece of the puzzle is missing",
            subtitle: "Something didn't connect properly. Check the URL or try reloading."
        ),
        ErrorMessage(
            emoji: "💫",
            title: "The internet got dizzy",
            subtitle: "An error occurred that we didn't expect. Refresh and hope for the best."
        ),
    ]
}
