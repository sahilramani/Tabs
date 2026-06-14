//
//  SubscriptionKeywordCatalog.swift
//  Tabs
//
//  PRIVACY: This is a hard-coded, on-device lookup table. There is no remote
//  catalog fetch — adding brands means editing this file, not calling an API.
//
//  This file is deliberately the *only* place you need to touch to teach the
//  scanner new merchants. Add a `BrandRule` and the parser picks it up.
//

import Foundation

/// One matching rule for a known subscription merchant.
struct BrandRule: Hashable {
    /// The canonical, user-facing name we store (e.g. "Disney+").
    let displayName: String

    /// Lowercased substrings that, if present in a line, indicate this brand.
    /// Multiple aliases handle how merchants appear on statements
    /// (e.g. "amazon prime", "amzn prime").
    let aliases: [String]

    init(_ displayName: String, aliases: [String]? = nil) {
        self.displayName = displayName
        // Default alias is the lowercased display name itself.
        self.aliases = (aliases ?? [displayName]).map { $0.lowercased() }
    }
}

/// A modular, extensible registry of subscription merchants to look for.
///
/// To extend detection later, append to `defaultRules` (or inject a custom
/// catalog into `LocalStatementScannerService`).
struct SubscriptionKeywordCatalog {

    let rules: [BrandRule]

    init(rules: [BrandRule] = SubscriptionKeywordCatalog.defaultRules) {
        self.rules = rules
    }

    /// Returns the first brand whose any alias appears in `line` (case-insensitive),
    /// or `nil` if the line mentions no known merchant.
    func matchedBrand(in line: String) -> BrandRule? {
        let haystack = line.lowercased()
        return rules.first { rule in
            rule.aliases.contains { haystack.contains($0) }
        }
    }

    /// The clean, curated display name for a known brand on this line (if any).
    /// Used by the generic detector to prettify known merchants and to *boost*
    /// confidence — it is no longer a gate for detection.
    func knownDisplayName(in line: String) -> String? {
        matchedBrand(in: line)?.displayName
    }

    // MARK: - Generic-detector signals

    /// Substrings that mark a line as NOT a subscription (one-off purchases,
    /// transfers, fees, P2P, etc.). A line containing any of these is dropped
    /// before it can become a candidate — this is what kills false positives
    /// like "AMAZON MKTPLACE PMTS".
    static let negativeKeywords: [String] = [
        "mktplace", "mktp", "marketplace",      // marketplace purchases (Amazon etc.)
        "pmts", "ppd id", "ccd id", "web id",   // ACH payment descriptors
        "atm", "withdrawal", "cash withdrawal",
        "deposit", "transfer", "xfer",
        "payment thank you", "thank you-", "automatic payment", "online payment",
        "bill pay", "billpay", "epay",
        "zelle", "venmo", "cash app", "cashapp", "paypal transfer",
        "e-check", "echeck", "check #", "check no",
        "interest", "dividend", "refund", "reversal", "returned item", "credit voucher",
        "overdraft", "late fee", "service charge", "wire transfer", "payroll", "direct dep",

        // Statement-summary furniture: balances, totals, dues, card-program
        // noise. These lines recur on every statement and would otherwise
        // masquerade as monthly subscriptions.
        "new balance", "previous balance", "ending balance", "beginning balance",
        "statement balance", "total balance", "balance of", "balance transfer",
        "minimum payment", "payment due", "total payment", "total payments",
        "payments and credits", "total credits", "total fees", "fees charged",
        "annual fee", "membership fee waived",
        "cash advance", "daily cash", "installment",
        "amount due", "past due", "credit limit", "credit line", "available credit",
        "purchase interest", "penalty apr", "variable apr", "interest charge",
        "billing period", "billing cycle", "closing date", "opening date",
        "trans date", "post date", "transaction date",
        "rewards balance", "points earned", "cash back earned",
        "total new charges", "total financed", "total remaining", "total daily",
        "annual percentage", "customer service", "account number", "page ",

        // Loans, leases, and rent are obligations, not subscriptions.
        "base rent", "lease payment", "loan payment", "principal", "escrow",
    ]

    /// Returns true if the line looks like a non-subscription transaction.
    func isExcluded(_ line: String) -> Bool {
        let haystack = line.lowercased()
        return SubscriptionKeywordCatalog.negativeKeywords.contains { haystack.contains($0) }
    }

    /// Substrings that *suggest* a recurring subscription even for an unknown
    /// merchant, so a single-statement charge can still surface.
    ///
    /// Deliberately narrow: each entry is a word banks print on genuinely
    /// recurring charges. Broad cues ("monthly", "member", ".com/bill") were
    /// removed after testing against real statements — they match summary
    /// lines, bank footers, and every per-order "AMZN.COM/BILL" descriptor.
    static let subscriptionHints: [String] = [
        "subscription", "subscriptn", "subscr", "recurring",
        "membership", "renewal", "autopay", "auto pay",
    ]

    /// Returns true if the line carries a subscription-like cue.
    func hasSubscriptionHint(_ line: String) -> Bool {
        let haystack = line.lowercased()
        return SubscriptionKeywordCatalog.subscriptionHints.contains { haystack.contains($0) }
    }

    /// The shipped brand list. Grouped by category purely for readability.
    static let defaultRules: [BrandRule] = [
        // Streaming video
        BrandRule("Netflix"),
        BrandRule("Hulu"),
        BrandRule("Disney+", aliases: ["disney+", "disney plus", "disneyplus"]),
        BrandRule("HBO Max", aliases: ["hbo max", "hbomax", "max.com"]),
        BrandRule("YouTube Premium", aliases: ["youtube premium", "youtubepremium", "google youtube"]),
        BrandRule("Paramount+", aliases: ["paramount+", "paramount plus", "paramountplus"]),
        BrandRule("Peacock"),
        // Marketplace purchases ("AMAZON MKTPLACE PMTS") are dropped by
        // negativeKeywords before brand matching, and the detector's
        // single-charge amount cap filters out big one-off orders, so bare
        // "amazon prime" is safe to match — it's how the annual membership
        // renewal appears ("AMAZON PRIME T45830NQ3 AMZN.COM/BILL").
        BrandRule("Amazon Prime", aliases: [
            "amazon prime",
            "amzn prime",
            "prime video",
            "amazonprime",
            "amazon.com/prime",
        ]),

        // Music & audio
        BrandRule("Spotify"),
        BrandRule("Apple", aliases: ["apple.com/bill", "apple music", "itunes", "apple services"]),
        BrandRule("Audible"),
        BrandRule("Tidal"),
        BrandRule("Pandora"),

        // Creative / productivity / cloud
        BrandRule("Adobe", aliases: ["adobe", "creative cloud"]),
        BrandRule("Microsoft 365", aliases: ["microsoft 365", "office 365"]),
        BrandRule("Google", aliases: ["google one", "google storage", "google workspace"]),
        BrandRule("Dropbox"),
        BrandRule("Notion"),
        BrandRule("Canva"),
        BrandRule("AWS", aliases: ["aws", "amazon web services"]),

        // Creators & memberships
        BrandRule("Patreon"),
        BrandRule("Substack"),
        BrandRule("OnlyFans", aliases: ["onlyfans"]),

        // Fitness & lifestyle
        BrandRule("Gym", aliases: ["gym", "fitness", "planet fit", "equinox", "la fitness", "24 hour"]),
        BrandRule("Peloton"),
        BrandRule("ClassPass"),
        BrandRule("Zwift", aliases: ["zwift"]),

        // News
        BrandRule("New York Times", aliases: ["new york times", "nytimes"]),
        BrandRule("Wall Street Journal", aliases: ["wall street journal", "wsj"]),

        // Streaming & cable
        BrandRule("Sling TV", aliases: ["sling tv"]),
        BrandRule("Cinemark Movie Club", aliases: ["cinemark movie club"]),

        // Vehicle subscriptions
        BrandRule("Rivian Connect+", aliases: ["rivian connect+", "rivian connect"]),
        BrandRule("Tesla Premium Connectivity", aliases: ["tesla premium", "tesla connectivity"]),

        // Insurance & home services
        BrandRule("Tesla Insurance", aliases: ["tesla insurance"]),
        BrandRule("eRenterPlan", aliases: ["erenterplan", "renter plan", "renters plan", "renter's plan"]),
        BrandRule("ADT Security", aliases: ["adt security", "adtsecurity", "myadt"]),
        BrandRule("SafeStreets", aliases: ["safestreets"]),
        BrandRule("Ring Protect", aliases: ["ring protect", "ring.com"]),
        BrandRule("SimpliSafe", aliases: ["simplisafe"]),

        // Telecom & internet (recurring by nature)
        BrandRule("Comcast Xfinity", aliases: ["comcast", "xfinity"]),
        BrandRule("Google Fi", aliases: ["google fi", "googlefi", "google *fi"]),
        BrandRule("Verizon", aliases: ["verizon"]),
        BrandRule("AT&T", aliases: ["at&t", "att payment", "att*"]),
        BrandRule("T-Mobile", aliases: ["t-mobile", "tmobile"]),

        // Home networking
        BrandRule("Eero Plus", aliases: ["eero plus", "eero secure", "eero"]),

        // Hosting & domains
        BrandRule("HostGator", aliases: ["hostgator"]),
        BrandRule("GoDaddy", aliases: ["godaddy"]),
        BrandRule("Namecheap", aliases: ["namecheap"]),
        BrandRule("Cloudflare", aliases: ["cloudflare"]),
        BrandRule("DigitalOcean", aliases: ["digitalocean", "digital ocean"]),
        BrandRule("Linode", aliases: ["linode", "akamai linode"]),
        BrandRule("Heroku", aliases: ["heroku"]),
        BrandRule("Vercel", aliases: ["vercel"]),
        BrandRule("Netlify", aliases: ["netlify"]),

        // AI tools
        BrandRule("Claude", aliases: ["claude.ai", "anthropic"]),
        BrandRule("ChatGPT", aliases: ["chatgpt", "openai"]),
        BrandRule("Cursor", aliases: ["cursor.com", "cursor.sh", "cursor ai"]),
        BrandRule("Perplexity", aliases: ["perplexity"]),
        BrandRule("Midjourney", aliases: ["midjourney"]),

        // Developer tools
        BrandRule("GitHub", aliases: ["github"]),
        BrandRule("GitLab", aliases: ["gitlab"]),
        BrandRule("Figma", aliases: ["figma"]),
        BrandRule("Linear", aliases: ["linear.app"]),
        BrandRule("Sentry", aliases: ["sentry.io"]),

        // Password & security
        BrandRule("1Password", aliases: ["1password", "1pass"]),
        BrandRule("LastPass", aliases: ["lastpass"]),
        BrandRule("Bitwarden", aliases: ["bitwarden"]),
        BrandRule("NordVPN", aliases: ["nordvpn", "nord vpn"]),
        BrandRule("ExpressVPN", aliases: ["expressvpn", "express vpn"]),

        // Healthcare & wellness
        BrandRule("Rula Health", aliases: ["rula health", "rula"]),
        BrandRule("BetterHelp", aliases: ["betterhelp", "better help"]),
        BrandRule("Calm", aliases: ["calm.com", "calm app"]),
        BrandRule("Headspace", aliases: ["headspace"]),

        // Writing & productivity (additions to existing Notion/Microsoft 365/Google)
        BrandRule("Grammarly", aliases: ["grammarly"]),
        BrandRule("Evernote", aliases: ["evernote"]),
        BrandRule("Todoist", aliases: ["todoist"]),
        BrandRule("Bear", aliases: ["bear writer", "bear notes"]),
    ]
}
