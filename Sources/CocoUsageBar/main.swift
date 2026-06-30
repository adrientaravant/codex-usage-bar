import AppKit
import Foundation

private let claudeOAuthCredentialsFile = ".claude/.credentials.json"
private let claudeOAuthKeychainService = "Claude Code-credentials"
private let feedbackEmail = "adrien.taravant@gmail.com"

struct TokenWindow: Codable {
    var inputTokens: Int64 = 0
    var cachedInputTokens: Int64 = 0
    var cacheWriteTokens: Int64 = 0
    var cacheReadTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var reasoningTokens: Int64 = 0
    var totalTokens: Int64 = 0
    var estimatedCostUSD: Double = 0
    var eventCount: Int = 0
    var latestEventAt: Date?
    var sessionCount: Int = 0
    var sourceTokens: [String: Int64] = [:]
    var modelTokens: [String: Int64] = [:]
    var dayTokens: [String: Int64] = [:]
    var pricingBasisTokens: [String: Int64] = [:]
    var fallbackPricedTokens: Int64 = 0
    var unpricedTokens: Int64 = 0

    private var sessionIDs: Set<String> = []

    init() {}

    enum CodingKeys: String, CodingKey {
        case inputTokens
        case cachedInputTokens
        case cacheWriteTokens
        case cacheReadTokens
        case outputTokens
        case reasoningTokens
        case totalTokens
        case estimatedCostUSD
        case eventCount
        case latestEventAt
        case sessionCount
        case sourceTokens
        case modelTokens
        case dayTokens
        case pricingBasisTokens
        case fallbackPricedTokens
        case unpricedTokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decodeIfPresent(Int64.self, forKey: .inputTokens) ?? 0
        cachedInputTokens = try container.decodeIfPresent(Int64.self, forKey: .cachedInputTokens) ?? 0
        cacheWriteTokens = try container.decodeIfPresent(Int64.self, forKey: .cacheWriteTokens) ?? 0
        cacheReadTokens = try container.decodeIfPresent(Int64.self, forKey: .cacheReadTokens) ?? 0
        outputTokens = try container.decodeIfPresent(Int64.self, forKey: .outputTokens) ?? 0
        reasoningTokens = try container.decodeIfPresent(Int64.self, forKey: .reasoningTokens) ?? 0
        totalTokens = try container.decodeIfPresent(Int64.self, forKey: .totalTokens) ?? 0
        estimatedCostUSD = try container.decodeIfPresent(Double.self, forKey: .estimatedCostUSD) ?? 0
        eventCount = try container.decodeIfPresent(Int.self, forKey: .eventCount) ?? 0
        latestEventAt = try container.decodeIfPresent(Date.self, forKey: .latestEventAt)
        sessionCount = try container.decodeIfPresent(Int.self, forKey: .sessionCount) ?? 0
        sourceTokens = try container.decodeIfPresent([String: Int64].self, forKey: .sourceTokens) ?? [:]
        modelTokens = try container.decodeIfPresent([String: Int64].self, forKey: .modelTokens) ?? [:]
        dayTokens = try container.decodeIfPresent([String: Int64].self, forKey: .dayTokens) ?? [:]
        pricingBasisTokens = try container.decodeIfPresent([String: Int64].self, forKey: .pricingBasisTokens) ?? [:]
        fallbackPricedTokens = try container.decodeIfPresent(Int64.self, forKey: .fallbackPricedTokens) ?? 0
        unpricedTokens = try container.decodeIfPresent(Int64.self, forKey: .unpricedTokens) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(inputTokens, forKey: .inputTokens)
        try container.encode(cachedInputTokens, forKey: .cachedInputTokens)
        try container.encode(cacheWriteTokens, forKey: .cacheWriteTokens)
        try container.encode(cacheReadTokens, forKey: .cacheReadTokens)
        try container.encode(outputTokens, forKey: .outputTokens)
        try container.encode(reasoningTokens, forKey: .reasoningTokens)
        try container.encode(totalTokens, forKey: .totalTokens)
        try container.encode(estimatedCostUSD, forKey: .estimatedCostUSD)
        try container.encode(eventCount, forKey: .eventCount)
        try container.encodeIfPresent(latestEventAt, forKey: .latestEventAt)
        try container.encode(sessionCount, forKey: .sessionCount)
        try container.encode(sourceTokens, forKey: .sourceTokens)
        try container.encode(modelTokens, forKey: .modelTokens)
        try container.encode(dayTokens, forKey: .dayTokens)
        try container.encode(pricingBasisTokens, forKey: .pricingBasisTokens)
        try container.encode(fallbackPricedTokens, forKey: .fallbackPricedTokens)
        try container.encode(unpricedTokens, forKey: .unpricedTokens)
    }

    mutating func add(_ sample: UsageSample, at date: Date, dayKey: String) {
        inputTokens += sample.inputTokens
        cachedInputTokens += sample.cachedInputTokens
        cacheWriteTokens += sample.cacheWriteTokens
        cacheReadTokens += sample.cacheReadTokens
        outputTokens += sample.outputTokens
        reasoningTokens += sample.reasoningTokens
        totalTokens += sample.totalTokens
        estimatedCostUSD += sample.estimatedCostUSD
        eventCount += 1
        if latestEventAt == nil || date > latestEventAt! {
            latestEventAt = date
        }
        if let sessionID = sample.sessionID, !sessionID.isEmpty {
            sessionIDs.insert(sessionID)
            sessionCount = sessionIDs.count
        }
        if let source = sample.source, !source.isEmpty {
            sourceTokens[source, default: 0] += sample.totalTokens
        }
        if let model = sample.model, !model.isEmpty {
            modelTokens[model, default: 0] += sample.totalTokens
        }
        if !sample.pricingBasis.isEmpty {
            pricingBasisTokens[sample.pricingBasis, default: 0] += sample.totalTokens
        }
        if sample.isFallbackPriced {
            fallbackPricedTokens += sample.totalTokens
        }
        if sample.isUnpriced {
            unpricedTokens += sample.totalTokens
        }
        dayTokens[dayKey, default: 0] += sample.totalTokens
    }
}

struct UsageSample {
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let cacheWriteTokens: Int64
    let cacheReadTokens: Int64
    let outputTokens: Int64
    let reasoningTokens: Int64
    let totalTokens: Int64
    let estimatedCostUSD: Double
    let sessionID: String?
    let source: String?
    let model: String?
    let pricingBasis: String
    let isFallbackPriced: Bool
    let isUnpriced: Bool
}

struct ProviderUsage: Codable {
    var today = TokenWindow()
    var sevenDays = TokenWindow()
    var thirtyDays = TokenWindow()

    mutating func add(_ sample: UsageSample, at date: Date, todayStart: Date, sevenDayCutoff: Date, thirtyDayCutoff: Date) {
        guard date >= thirtyDayCutoff else { return }
        let dayKey = ProviderUsage.dayFormatter.string(from: date)
        thirtyDays.add(sample, at: date, dayKey: dayKey)
        if date >= sevenDayCutoff {
            sevenDays.add(sample, at: date, dayKey: dayKey)
        }
        if date >= todayStart {
            today.add(sample, at: date, dayKey: dayKey)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct RateWindow: Codable {
    let usedPercent: Double?
    let windowMinutes: Int?
    let resetsAt: Date?
}

struct CodexRateLimits: Codable {
    let updatedAt: Date
    let planType: String?
    let primary: RateWindow?
    let secondary: RateWindow?
}

struct UsageSnapshot: Codable {
    let generatedAt: Date
    let codexLimits: CodexRateLimits?
    let claudeLimits: CodexRateLimits?
    let codexUsage: ProviderUsage
    let claudeUsage: ProviderUsage
}

struct ClaudeOAuthCredentialsPayload: Decodable {
    let claudeAiOauth: ClaudeOAuthCredentials?
}

struct ClaudeOAuthCredentials: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Int64?
    let scopes: [String]?
    let subscriptionType: String?
    let rateLimitTier: String?

    var hasProfileScope: Bool {
        scopes?.contains("user:profile") == true
    }

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Int64(Date().timeIntervalSince1970 * 1000)
    }
}

struct ClaudeOAuthUsageResponse: Decodable {
    let fiveHour: ClaudeOAuthUsageWindow?
    let sevenDay: ClaudeOAuthUsageWindow?
    let sevenDayOAuthApps: ClaudeOAuthUsageWindow?
    let sevenDaySonnet: ClaudeOAuthUsageWindow?
    let sevenDayOpus: ClaudeOAuthUsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOAuthApps = "seven_day_oauth_apps"
        case sevenDaySonnet = "seven_day_sonnet"
        case sevenDayOpus = "seven_day_opus"
    }
}

struct ClaudeOAuthUsageWindow: Decodable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

private final class ClaudeOAuthUsageResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ClaudeOAuthUsageResponse?

    func set(_ value: ClaudeOAuthUsageResponse?) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func get() -> ClaudeOAuthUsageResponse? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

struct TokenPrices {
    let inputPerMTok: Double
    let cachedInputPerMTok: Double
    let cacheWritePerMTok: Double
    let cacheReadPerMTok: Double
    let outputPerMTok: Double
}

struct CostEstimate {
    let amountUSD: Double
    let basis: String
    let isFallback: Bool
    let isPriced: Bool
}

enum CostEstimator {
    static func codexPrices(model: String?) -> (prices: TokenPrices, basis: String, isFallback: Bool) {
        let normalized = normalizedModel(model)
        switch normalized {
        case let value where value.contains("gpt-5.5"):
            return (
                TokenPrices(inputPerMTok: 5, cachedInputPerMTok: 0.50, cacheWritePerMTok: 5, cacheReadPerMTok: 0.50, outputPerMTok: 30),
                "OpenAI GPT-5.5 public API pricing",
                false
            )
        case let value where value.contains("gpt-5.4") || value.contains("codex-auto-review"):
            return (
                TokenPrices(inputPerMTok: 2.50, cachedInputPerMTok: 0.25, cacheWritePerMTok: 2.50, cacheReadPerMTok: 0.25, outputPerMTok: 15),
                "OpenAI GPT-5.4 public API pricing",
                normalized.isEmpty
            )
        case let value where value.contains("gpt-5.3"):
            return (
                TokenPrices(inputPerMTok: 1.25, cachedInputPerMTok: 0.13, cacheWritePerMTok: 1.25, cacheReadPerMTok: 0.13, outputPerMTok: 7.50),
                "OpenAI GPT-5.3 fallback pricing",
                false
            )
        default:
            return (
                TokenPrices(inputPerMTok: 5, cachedInputPerMTok: 0.50, cacheWritePerMTok: 5, cacheReadPerMTok: 0.50, outputPerMTok: 30),
                "OpenAI GPT-5.5 public API pricing (fallback)",
                true
            )
        }
    }

    static func claudePrices(model: String?) -> (prices: TokenPrices, basis: String, isFallback: Bool, isPriced: Bool) {
        let normalized = (model ?? "").lowercased()
        if normalized == "<synthetic>" {
            return (
                TokenPrices(inputPerMTok: 0, cachedInputPerMTok: 0, cacheWritePerMTok: 0, cacheReadPerMTok: 0, outputPerMTok: 0),
                "Unpriced synthetic Claude rows",
                false,
                false
            )
        }
        if normalized.contains("fable") || normalized.contains("mythos") {
            return (
                TokenPrices(inputPerMTok: 10, cachedInputPerMTok: 1, cacheWritePerMTok: 12.50, cacheReadPerMTok: 1, outputPerMTok: 50),
                "Anthropic Claude Fable/Mythos public API pricing",
                false,
                true
            )
        }
        if normalized.contains("opus") {
            return (
                TokenPrices(inputPerMTok: 5, cachedInputPerMTok: 0.50, cacheWritePerMTok: 6.25, cacheReadPerMTok: 0.50, outputPerMTok: 25),
                "Anthropic Claude Opus public API pricing",
                false,
                true
            )
        }
        if normalized.contains("haiku") {
            return (
                TokenPrices(inputPerMTok: 1, cachedInputPerMTok: 0.10, cacheWritePerMTok: 1.25, cacheReadPerMTok: 0.10, outputPerMTok: 5),
                "Anthropic Claude Haiku public API pricing",
                false,
                true
            )
        }
        if normalized.contains("sonnet") {
            return (
                TokenPrices(inputPerMTok: 3, cachedInputPerMTok: 0.30, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30, outputPerMTok: 15),
                "Anthropic Claude Sonnet public API pricing",
                false,
                true
            )
        }
        return (
            TokenPrices(inputPerMTok: 3, cachedInputPerMTok: 0.30, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30, outputPerMTok: 15),
            "Anthropic Claude Sonnet public API pricing (fallback)",
            true,
            true
        )
    }

    static func codexCost(
        model: String?,
        inputTokens: Int64,
        cachedInputTokens: Int64,
        outputTokens: Int64,
        reasoningTokens: Int64
    ) -> CostEstimate {
        let resolved = codexPrices(model: model)
        return CostEstimate(
            amountUSD: cost(
                inputTokens: inputTokens,
                cachedInputTokens: cachedInputTokens,
                outputTokens: outputTokens,
                reasoningTokens: reasoningTokens,
                prices: resolved.prices
            ),
            basis: resolved.basis,
            isFallback: resolved.isFallback,
            isPriced: true
        )
    }

    static func claudeCost(
        model: String?,
        inputTokens: Int64,
        cacheWriteTokens: Int64,
        cacheReadTokens: Int64,
        outputTokens: Int64
    ) -> CostEstimate {
        let resolved = claudePrices(model: model)
        return CostEstimate(
            amountUSD: cost(
                inputTokens: inputTokens,
                cacheWriteTokens: cacheWriteTokens,
                cacheReadTokens: cacheReadTokens,
                outputTokens: outputTokens,
                prices: resolved.prices
            ),
            basis: resolved.basis,
            isFallback: resolved.isFallback,
            isPriced: resolved.isPriced
        )
    }

    private static func normalizedModel(_ model: String?) -> String {
        (model ?? "").lowercased()
    }

    private static func cost(
        inputTokens: Int64,
        cachedInputTokens: Int64 = 0,
        cacheWriteTokens: Int64 = 0,
        cacheReadTokens: Int64 = 0,
        outputTokens: Int64,
        reasoningTokens: Int64 = 0,
        prices: TokenPrices
    ) -> Double {
        let outputAndReasoning = outputTokens + reasoningTokens
        return dollars(inputTokens, prices.inputPerMTok)
            + dollars(cachedInputTokens, prices.cachedInputPerMTok)
            + dollars(cacheWriteTokens, prices.cacheWritePerMTok)
            + dollars(cacheReadTokens, prices.cacheReadPerMTok)
            + dollars(outputAndReasoning, prices.outputPerMTok)
    }

    private static func dollars(_ tokens: Int64, _ perMillion: Double) -> Double {
        Double(tokens) / 1_000_000 * perMillion
    }
}

final class UsageReader {
    private let fileManager = FileManager.default
    private let calendar = Calendar.current
    private let isoWithFractional: ISO8601DateFormatter
    private let isoWithoutFractional: ISO8601DateFormatter
    private let newline = Data([0x0A])
    private let ripgrepURL: URL?
    private let modelRegex: NSRegularExpression?
    private let debugTiming: Bool

    init(debugTiming: Bool = false) {
        self.debugTiming = debugTiming
        isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoWithoutFractional = ISO8601DateFormatter()
        isoWithoutFractional.formatOptions = [.withInternetDateTime]
        ripgrepURL = [
            "/Applications/Codex.app/Contents/Resources/rg",
            "/opt/homebrew/bin/rg",
            "/usr/local/bin/rg",
            "/usr/bin/rg"
        ]
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
        modelRegex = try? NSRegularExpression(pattern: #""(?:model|model_name|model_slug|model_id)"\s*:\s*"([^"]+)""#)
    }

    func load() -> UsageSnapshot {
        let now = Date()
        let thirtyDayCutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let sevenDayCutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let todayStart = calendar.startOfDay(for: now)
        let home = fileManager.homeDirectoryForCurrentUser

        debugLog("read codex start")
        let codex = readCodex(
            roots: [
                home.appendingPathComponent(".codex/sessions", isDirectory: true),
                home.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
            ],
            sevenDayCutoff: sevenDayCutoff,
            thirtyDayCutoff: thirtyDayCutoff,
            todayStart: todayStart
        )
        debugLog("read codex done")
        debugLog("read claude start")
        let claudeUsage = readClaude(
            root: home.appendingPathComponent(".claude/projects", isDirectory: true),
            sevenDayCutoff: sevenDayCutoff,
            thirtyDayCutoff: thirtyDayCutoff,
            todayStart: todayStart
        )
        debugLog("read claude done")
        debugLog("read claude oauth start")
        let claudeLimits = readClaudeOAuthLimits()
        debugLog("read claude oauth done")

        return UsageSnapshot(
            generatedAt: now,
            codexLimits: codex.limits,
            claudeLimits: claudeLimits,
            codexUsage: codex.usage,
            claudeUsage: claudeUsage
        )
    }

    private func debugLog(_ message: String) {
        guard debugTiming else { return }
        let line = "[\(Date())] \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    private func readCodex(
        roots: [URL],
        sevenDayCutoff: Date,
        thirtyDayCutoff: Date,
        todayStart: Date
    ) -> (limits: CodexRateLimits?, usage: ProviderUsage) {
        var latestLimits: CodexRateLimits?
        var usage = ProviderUsage()
        var seenLines = Set<String>()
        let searchRoots = roots.flatMap { codexSearchRoots(root: $0, from: thirtyDayCutoff, through: Date()) }
        debugLog("codex roots \(searchRoots.filter { fileManager.fileExists(atPath: $0.path) }.count)")

        let states = CodexFileStates()
        let usedRipgrep = forEachRipgrepPathLine(
            pattern: #""token_count"|"rate_limits"|"session_meta"|"(?:model|model_name|model_slug|model_id)"\s*:\s*"(?:gpt-|codex|claude)"#,
            roots: searchRoots
        ) { file, line in
            parseCodexMatchedLine(
                line,
                file: file,
                state: states.state(for: file),
                thirtyDayCutoff: thirtyDayCutoff,
                latestLimits: &latestLimits,
                seenLines: &seenLines
            )
        }

        if usedRipgrep {
            applyCodexStates(states.all, sevenDayCutoff: sevenDayCutoff, thirtyDayCutoff: thirtyDayCutoff, todayStart: todayStart, usage: &usage)
        } else {
            for root in searchRoots {
                for file in jsonlFiles(under: root, modifiedSince: Date.distantPast) {
                    parseCodexFile(
                        file,
                        sevenDayCutoff: sevenDayCutoff,
                        thirtyDayCutoff: thirtyDayCutoff,
                        todayStart: todayStart,
                        latestLimits: &latestLimits,
                        usage: &usage,
                        seenLines: &seenLines
                    )
                }
            }
        }

        return (latestLimits, usage)
    }

    private struct PendingCodexEvent {
        let line: String
        let timestamp: Date
        let usage: [String: Any]
    }

    private final class CodexFileState {
        let file: URL
        var sessionID: String
        var originator = ""
        var source = ""
        var threadSource = ""
        var modelCounts: [String: Int] = [:]
        var pendingEvents: [PendingCodexEvent] = []

        init(file: URL) {
            self.file = file
            sessionID = file.deletingPathExtension().lastPathComponent
        }
    }

    private final class CodexFileStates {
        private var values: [String: CodexFileState] = [:]

        var all: [CodexFileState] {
            Array(values.values)
        }

        func state(for file: URL) -> CodexFileState {
            let key = file.path
            if let existing = values[key] { return existing }
            let state = CodexFileState(file: file)
            values[key] = state
            return state
        }
    }

    private func parseCodexMatchedLine(
        _ line: String,
        file: URL,
        state: CodexFileState,
        thirtyDayCutoff: Date,
        latestLimits: inout CodexRateLimits?,
        seenLines: inout Set<String>
    ) {
        if line.contains(#""model"#) {
            for model in modelHints(inLine: line) {
                state.modelCounts[model, default: 0] += 1
            }
        }

        guard line.contains(#""token_count""#)
                || line.contains(#""rate_limits""#)
                || line.contains(#""session_meta""#)
        else { return }
        guard let object = jsonObject(from: line) else { return }

        if (object["type"] as? String) == "session_meta",
           let payload = object["payload"] as? [String: Any] {
            if let id = payload["id"] as? String, !id.isEmpty {
                state.sessionID = id
            }
            state.originator = payload["originator"] as? String ?? state.originator
            state.source = scalarDescription(payload["source"]) ?? state.source
            state.threadSource = payload["thread_source"] as? String ?? state.threadSource
            return
        }

        guard let timestamp = parseTimestamp(object["timestamp"]),
              let payload = object["payload"] as? [String: Any]
        else { return }

        if let rateLimits = payload["rate_limits"] as? [String: Any],
           let parsed = parseCodexRateLimits(rateLimits, updatedAt: timestamp),
           latestLimits == nil || parsed.updatedAt > latestLimits!.updatedAt {
            latestLimits = parsed
        }

        guard timestamp >= thirtyDayCutoff,
              (payload["type"] as? String) == "token_count",
              let info = payload["info"] as? [String: Any],
              let lastTokenUsage = info["last_token_usage"] as? [String: Any],
              seenLines.insert(line).inserted
        else { return }

        state.pendingEvents.append(PendingCodexEvent(line: line, timestamp: timestamp, usage: lastTokenUsage))
    }

    private func applyCodexStates(
        _ states: [CodexFileState],
        sevenDayCutoff: Date,
        thirtyDayCutoff: Date,
        todayStart: Date,
        usage: inout ProviderUsage
    ) {
        for state in states {
            let model = preferredModel(from: state.modelCounts)
            let sourceLabel = codexSourceLabel(originator: state.originator, source: state.source, threadSource: state.threadSource)
            for event in state.pendingEvents {
                guard let sample = codexSample(
                    from: event.usage,
                    model: model,
                    source: sourceLabel,
                    sessionID: state.sessionID
                ) else { continue }
                usage.add(sample, at: event.timestamp, todayStart: todayStart, sevenDayCutoff: sevenDayCutoff, thirtyDayCutoff: thirtyDayCutoff)
            }
        }
    }

    private func parseCodexFile(
        _ file: URL,
        sevenDayCutoff: Date,
        thirtyDayCutoff: Date,
        todayStart: Date,
        latestLimits: inout CodexRateLimits?,
        usage: inout ProviderUsage,
        seenLines: inout Set<String>
    ) {
        var sessionID = file.deletingPathExtension().lastPathComponent
        var originator = ""
        var source = ""
        var threadSource = ""
        var modelCounts: [String: Int] = [:]
        var pendingEvents: [PendingCodexEvent] = []

        forEachLine(in: file) { line in
            if line.contains(#""model"#) {
                for model in modelHints(inLine: line) {
                    modelCounts[model, default: 0] += 1
                }
            }

            guard line.contains(#""token_count""#)
                    || line.contains(#""rate_limits""#)
                    || line.contains(#""session_meta""#)
            else { return }
            guard let object = jsonObject(from: line) else { return }

            for model in modelHints(inLine: line) {
                modelCounts[model, default: 0] += 1
            }

            if (object["type"] as? String) == "session_meta",
               let payload = object["payload"] as? [String: Any] {
                if let id = payload["id"] as? String, !id.isEmpty {
                    sessionID = id
                }
                originator = payload["originator"] as? String ?? originator
                source = scalarDescription(payload["source"]) ?? source
                threadSource = payload["thread_source"] as? String ?? threadSource
                return
            }

            guard let timestamp = parseTimestamp(object["timestamp"]),
                  let payload = object["payload"] as? [String: Any]
            else { return }

            if let rateLimits = payload["rate_limits"] as? [String: Any],
               let parsed = parseCodexRateLimits(rateLimits, updatedAt: timestamp),
               latestLimits == nil || parsed.updatedAt > latestLimits!.updatedAt {
                latestLimits = parsed
            }

            guard timestamp >= thirtyDayCutoff,
                  (payload["type"] as? String) == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let lastTokenUsage = info["last_token_usage"] as? [String: Any],
                  seenLines.insert(line).inserted
            else { return }

            pendingEvents.append(PendingCodexEvent(line: line, timestamp: timestamp, usage: lastTokenUsage))
        }

        let model = preferredModel(from: modelCounts)
        let sourceLabel = codexSourceLabel(originator: originator, source: source, threadSource: threadSource)
        for event in pendingEvents {
            guard let sample = codexSample(
                from: event.usage,
                model: model,
                source: sourceLabel,
                sessionID: sessionID
            ) else { continue }
            usage.add(sample, at: event.timestamp, todayStart: todayStart, sevenDayCutoff: sevenDayCutoff, thirtyDayCutoff: thirtyDayCutoff)
        }
    }

    private func readClaude(
        root: URL,
        sevenDayCutoff: Date,
        thirtyDayCutoff: Date,
        todayStart: Date
    ) -> ProviderUsage {
        var usage = ProviderUsage()
        var keyedSamples: [String: (date: Date, sample: UsageSample)] = [:]
        var unkeyedSamples: [(date: Date, sample: UsageSample)] = []

        let usedRipgrep = forEachRipgrepPathLine(pattern: #""usage""#, roots: [root]) { file, line in
            parseClaudeLine(
                line,
                sessionID: file.deletingPathExtension().lastPathComponent,
                keyedSamples: &keyedSamples,
                unkeyedSamples: &unkeyedSamples
            )
        }

        if !usedRipgrep {
            for file in jsonlFiles(under: root, modifiedSince: thirtyDayCutoff.addingTimeInterval(-24 * 60 * 60)) {
                let sessionID = file.deletingPathExtension().lastPathComponent
                forEachLine(in: file) { line in
                    guard line.contains(#""usage""#) else { return }
                    parseClaudeLine(
                        line,
                        sessionID: sessionID,
                        keyedSamples: &keyedSamples,
                        unkeyedSamples: &unkeyedSamples
                    )
                }
            }
        } else {
            keyedSamples = keyedSamples.filter { $0.value.date >= thirtyDayCutoff }
            unkeyedSamples = unkeyedSamples.filter { $0.date >= thirtyDayCutoff }
        }

        for entry in keyedSamples.values {
            usage.add(entry.sample, at: entry.date, todayStart: todayStart, sevenDayCutoff: sevenDayCutoff, thirtyDayCutoff: thirtyDayCutoff)
        }
        for entry in unkeyedSamples {
            usage.add(entry.sample, at: entry.date, todayStart: todayStart, sevenDayCutoff: sevenDayCutoff, thirtyDayCutoff: thirtyDayCutoff)
        }

        return usage
    }

    private func readClaudeOAuthLimits() -> CodexRateLimits? {
        guard let credentials = loadClaudeOAuthCredentials(),
              credentials.hasProfileScope,
              !credentials.accessToken.isEmpty,
              !credentials.isExpired,
              let response = fetchClaudeOAuthUsage(accessToken: credentials.accessToken)
        else { return nil }

        func makeWindow(_ window: ClaudeOAuthUsageWindow?, minutes: Int) -> RateWindow? {
            guard let window, let utilization = window.utilization else { return nil }
            return RateWindow(
                usedPercent: utilization,
                windowMinutes: minutes,
                resetsAt: parseISO8601(window.resetsAt)
            )
        }

        let fiveHour = makeWindow(response.fiveHour, minutes: 5 * 60)
        let weekly = makeWindow(response.sevenDay, minutes: 7 * 24 * 60)
        let primary = fiveHour
            ?? weekly
            ?? makeWindow(response.sevenDayOAuthApps, minutes: 7 * 24 * 60)
            ?? makeWindow(response.sevenDaySonnet, minutes: 7 * 24 * 60)
            ?? makeWindow(response.sevenDayOpus, minutes: 7 * 24 * 60)

        guard primary != nil || weekly != nil else { return nil }
        return CodexRateLimits(
            updatedAt: Date(),
            planType: claudePlanName(subscriptionType: credentials.subscriptionType, rateLimitTier: credentials.rateLimitTier),
            primary: primary,
            secondary: weekly
        )
    }

    private func loadClaudeOAuthCredentials() -> ClaudeOAuthCredentials? {
        if let credentials = loadClaudeOAuthCredentialsFromKeychain(),
           credentials.hasProfileScope,
           !credentials.accessToken.isEmpty,
           !credentials.isExpired {
            return credentials
        }
        if let credentials = loadClaudeOAuthCredentialsFromFile(),
           credentials.hasProfileScope,
           !credentials.accessToken.isEmpty,
           !credentials.isExpired {
            return credentials
        }
        return nil
    }

    private func loadClaudeOAuthCredentialsFromFile() -> ClaudeOAuthCredentials? {
        let url = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(claudeOAuthCredentialsFile)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ClaudeOAuthCredentialsPayload.self, from: data).claudeAiOauth
    }

    private func loadClaudeOAuthCredentialsFromKeychain() -> ClaudeOAuthCredentials? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", claudeOAuthKeychainService, "-w"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let raw = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let jsonData = raw.data(using: .utf8)
        else { return nil }

        return try? JSONDecoder().decode(ClaudeOAuthCredentialsPayload.self, from: jsonData).claudeAiOauth
    }

    private func fetchClaudeOAuthUsage(accessToken: String) -> ClaudeOAuthUsageResponse? {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")

        let result = ClaudeOAuthUsageResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let data
            else { return }
            result.set(try? JSONDecoder().decode(ClaudeOAuthUsageResponse.self, from: data))
        }.resume()
        _ = semaphore.wait(timeout: .now() + 12)
        return result.get()
    }

    private func parseISO8601(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return isoWithFractional.date(from: string) ?? isoWithoutFractional.date(from: string)
    }

    private func claudePlanName(subscriptionType: String?, rateLimitTier: String?) -> String? {
        let source = (subscriptionType?.isEmpty == false ? subscriptionType : rateLimitTier)?.lowercased() ?? ""
        if source.contains("max") { return "Claude Max" }
        if source.contains("pro") { return "Claude Pro" }
        if source.contains("team") { return "Claude Team" }
        if source.contains("enterprise") { return "Claude Enterprise" }
        return nil
    }

    private func parseClaudeLine(
        _ line: String,
        sessionID: String,
        keyedSamples: inout [String: (date: Date, sample: UsageSample)],
        unkeyedSamples: inout [(date: Date, sample: UsageSample)]
    ) {
        guard let object = jsonObject(from: line),
              (object["type"] as? String) == "assistant",
              let timestamp = parseTimestamp(object["timestamp"]),
              let message = object["message"] as? [String: Any],
              let messageUsage = message["usage"] as? [String: Any],
              let sample = claudeSample(
                from: messageUsage,
                model: message["model"] as? String,
                sessionID: sessionID
              )
        else { return }

        if let messageID = message["id"] as? String,
           let requestID = object["requestId"] as? String {
            keyedSamples["\(messageID):\(requestID)"] = (timestamp, sample)
        } else {
            unkeyedSamples.append((timestamp, sample))
        }
    }

    @discardableResult
    private func forEachRipgrepLine(pattern: String, roots: [URL], _ body: (String) -> Void) -> Bool {
        guard let ripgrepURL else { return false }

        let existingRoots = roots.filter { fileManager.fileExists(atPath: $0.path) }
        guard !existingRoots.isEmpty else { return true }
        debugLog("rg start \(pattern) roots \(existingRoots.count)")

        let process = Process()
        process.executableURL = ripgrepURL
        process.arguments = ["--no-filename", "-g", "*.jsonl", pattern] + existingRoots.map(\.path)

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return false
        }

        var buffer = Data()
        while true {
            let chunk = (try? output.fileHandleForReading.read(upToCount: 64 * 1024)) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let range = buffer.firstRange(of: newline) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    body(line)
                }
            }
        }

        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            body(line)
        }

        process.waitUntilExit()
        debugLog("rg done status \(process.terminationStatus)")

        return process.terminationStatus == 0 || process.terminationStatus == 1
    }

    @discardableResult
    private func forEachRipgrepPathLine(pattern: String, roots: [URL], _ body: (URL, String) -> Void) -> Bool {
        guard let ripgrepURL else { return false }

        let existingRoots = roots.filter { fileManager.fileExists(atPath: $0.path) }
        guard !existingRoots.isEmpty else { return true }
        debugLog("rg path start \(pattern) roots \(existingRoots.count)")

        let process = Process()
        process.executableURL = ripgrepURL
        process.arguments = ["--with-filename", "-g", "*.jsonl", pattern] + existingRoots.map(\.path)

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return false
        }

        func emit(_ rawLine: String) {
            guard let separator = rawLine.firstIndex(of: ":") else { return }
            let path = String(rawLine[..<separator])
            let line = String(rawLine[rawLine.index(after: separator)...])
            guard !path.isEmpty, !line.isEmpty else { return }
            body(URL(fileURLWithPath: path), line)
        }

        var buffer = Data()
        while true {
            let chunk = (try? output.fileHandleForReading.read(upToCount: 64 * 1024)) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let range = buffer.firstRange(of: newline) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    emit(line)
                }
            }
        }

        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            emit(line)
        }

        process.waitUntilExit()
        debugLog("rg path done status \(process.terminationStatus)")

        return process.terminationStatus == 0 || process.terminationStatus == 1
    }

    private func codexDateRoots(root: URL, from cutoff: Date, through end: Date) -> [URL] {
        var roots: [URL] = []
        var cursor = calendar.startOfDay(for: cutoff)
        let lastDay = calendar.startOfDay(for: end)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"

        while cursor <= lastDay {
            let relativePath = formatter.string(from: cursor)
            roots.append(root.appendingPathComponent(relativePath, isDirectory: true))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return roots
    }

    private func codexSearchRoots(root: URL, from cutoff: Date, through end: Date) -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }

        let datedRoots = codexDateRoots(root: root, from: cutoff, through: end)
            .filter { fileManager.fileExists(atPath: $0.path) }

        return datedRoots.isEmpty ? [root] : datedRoots
    }

    private func jsonlFiles(under root: URL, modifiedSince cutoff: Date) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let file as URL in enumerator {
            guard file.pathExtension == "jsonl" else { continue }
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true
            else { continue }
            if let modifiedAt = values.contentModificationDate, modifiedAt < cutoff {
                continue
            }
            files.append(file)
        }
        return files
    }

    private func forEachLine(in file: URL, _ body: (String) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }

        var buffer = Data()
        while true {
            let chunk = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let range = buffer.firstRange(of: newline) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    body(line)
                }
            }
        }

        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            body(line)
        }
    }

    private func jsonObject(from line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func parseTimestamp(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return isoWithFractional.date(from: string) ?? isoWithoutFractional.date(from: string)
    }

    private func parseCodexRateLimits(_ value: [String: Any], updatedAt: Date) -> CodexRateLimits? {
        CodexRateLimits(
            updatedAt: updatedAt,
            planType: value["plan_type"] as? String,
            primary: parseRateWindow(value["primary"] as? [String: Any]),
            secondary: parseRateWindow(value["secondary"] as? [String: Any])
        )
    }

    private func parseRateWindow(_ value: [String: Any]?) -> RateWindow? {
        guard let value else { return nil }
        return RateWindow(
            usedPercent: doubleValue(value["used_percent"]),
            windowMinutes: intValue(value["window_minutes"]).map(Int.init),
            resetsAt: intValue(value["resets_at"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private func codexSample(from usage: [String: Any], model: String?, source: String, sessionID: String) -> UsageSample? {
        let rawInput = intValue(usage["input_tokens"]) ?? 0
        let cachedInput = intValue(usage["cached_input_tokens"]) ?? 0
        let input = max(rawInput - cachedInput, 0)
        let output = intValue(usage["output_tokens"]) ?? 0
        let reasoning = intValue(usage["reasoning_output_tokens"]) ?? 0
        let visibleOutput = max(output - reasoning, 0)
        let total = intValue(usage["total_tokens"]) ?? rawInput + output
        guard total > 0 else { return nil }
        let estimate = CostEstimator.codexCost(
            model: model,
            inputTokens: input,
            cachedInputTokens: cachedInput,
            outputTokens: visibleOutput,
            reasoningTokens: reasoning
        )

        return UsageSample(
            inputTokens: input,
            cachedInputTokens: cachedInput,
            cacheWriteTokens: 0,
            cacheReadTokens: 0,
            outputTokens: visibleOutput,
            reasoningTokens: reasoning,
            totalTokens: total,
            estimatedCostUSD: estimate.amountUSD,
            sessionID: sessionID,
            source: source,
            model: model ?? "OpenAI GPT-5.5 fallback",
            pricingBasis: estimate.basis,
            isFallbackPriced: estimate.isFallback,
            isUnpriced: !estimate.isPriced
        )
    }

    private func claudeSample(from usage: [String: Any], model: String?, sessionID: String) -> UsageSample? {
        let input = intValue(usage["input_tokens"]) ?? 0
        let cacheWrite = intValue(usage["cache_creation_input_tokens"]) ?? 0
        let cacheRead = intValue(usage["cache_read_input_tokens"]) ?? 0
        let output = intValue(usage["output_tokens"]) ?? 0
        let total = input + cacheWrite + cacheRead + output
        guard total > 0 else { return nil }
        let estimate = CostEstimator.claudeCost(
            model: model,
            inputTokens: input,
            cacheWriteTokens: cacheWrite,
            cacheReadTokens: cacheRead,
            outputTokens: output
        )

        return UsageSample(
            inputTokens: input,
            cachedInputTokens: 0,
            cacheWriteTokens: cacheWrite,
            cacheReadTokens: cacheRead,
            outputTokens: output,
            reasoningTokens: 0,
            totalTokens: total,
            estimatedCostUSD: estimate.amountUSD,
            sessionID: sessionID,
            source: "Claude Code",
            model: model ?? "Claude Sonnet fallback",
            pricingBasis: estimate.basis,
            isFallbackPriced: estimate.isFallback,
            isUnpriced: !estimate.isPriced
        )
    }

    private func preferredModel(from counts: [String: Int]) -> String? {
        counts
            .filter { !$0.key.isEmpty }
            .max { lhs, rhs in lhs.value < rhs.value }?
            .key
    }

    private func modelHints(inLine line: String) -> [String] {
        guard let modelRegex else { return [] }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        return modelRegex.matches(in: line, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: line)
            else { return nil }
            let model = String(line[range])
            return isLikelyModelName(model) ? model : nil
        }
    }

    private func modelHints(in value: Any) -> [String] {
        var results: [String] = []
        func visit(_ node: Any) {
            if let dict = node as? [String: Any] {
                for (key, value) in dict {
                    if ["model", "model_name", "model_slug", "model_id"].contains(key),
                       let model = value as? String,
                       isLikelyModelName(model) {
                        results.append(model)
                    } else if let nested = value as? [String: Any] {
                        visit(nested)
                    } else if let nested = value as? [Any] {
                        nested.prefix(30).forEach(visit)
                    }
                }
            } else if let array = node as? [Any] {
                array.prefix(30).forEach(visit)
            }
        }
        visit(value)
        return results
    }

    private func isLikelyModelName(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("gpt-")
            || normalized.contains("codex")
            || normalized.contains("claude")
    }

    private func codexSourceLabel(originator: String, source: String, threadSource: String) -> String {
        let joined = "\(originator) \(source) \(threadSource)".lowercased()
        if joined.contains("subagent") { return "Subagent" }
        if joined.contains("codex-tui") || joined.contains("cli") { return "CLI / TUI" }
        if joined.contains("codex_exec") || joined.contains("exec") { return "Exec" }
        if joined.contains("desktop") || joined.contains("vscode") { return "Desktop app" }
        return "Codex"
    }

    private func scalarDescription(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let dict as [String: Any]:
            if dict["subagent"] != nil { return "subagent" }
            return nil
        default:
            return nil
        }
    }

    private func intValue(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber:
            return number.int64Value
        case let string as String:
            return Int64(string)
        default:
            return nil
        }
    }

    private func doubleValue(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }
}

enum SnapshotCache {
    private static var cacheURL: URL {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CocoUsageBar", isDirectory: true)
        return support.appendingPathComponent("snapshot.json")
    }

    static func load() -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    static func save(_ snapshot: UsageSnapshot) {
        let fileManager = FileManager.default
        let url = cacheURL
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Cache is an optimization. A failed write should not affect the menu bar app.
        }
    }
}

private enum MenuLayout {
    static let width: CGFloat = 360
    static let horizontalPadding: CGFloat = 12
    static let valueLeading: CGFloat = 82
    static let railLeading: CGFloat = horizontalPadding
}

private final class MenuHeaderView: NSView {
    init(iconName: String, title: String, detail: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: 28))

        let icon = NSImageView()
        icon.image = providerImage(named: iconName)
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.alignment = .right
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(titleLabel)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.horizontalPadding),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 13),
            icon.heightAnchor.constraint(equalToConstant: 13),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailLabel.leadingAnchor, constant: -12),

            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuLayout.horizontalPadding),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class MenuLimitRowView: NSView {
    private let usedPercent: Double?
    private let pacePercent: Double?
    private let providerColor: NSColor

    init(
        label: String,
        value: NSAttributedString,
        detail: NSAttributedString,
        usedPercent: Double?,
        pacePercent: Double?,
        providerColor: NSColor
    ) {
        self.usedPercent = usedPercent
        self.pacePercent = pacePercent
        self.providerColor = providerColor
        super.init(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: usedPercent == nil ? 28 : 38))
        wantsLayer = true

        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 12.5, weight: .semibold)
        labelView.textColor = .labelColor
        labelView.translatesAutoresizingMaskIntoConstraints = false

        let valueView = NSTextField(labelWithAttributedString: value)
        valueView.alignment = .right
        valueView.translatesAutoresizingMaskIntoConstraints = false

        let detailView = NSTextField(labelWithAttributedString: detail)
        detailView.alignment = .right
        detailView.lineBreakMode = .byTruncatingTail
        detailView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(labelView)
        addSubview(valueView)
        addSubview(detailView)

        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.horizontalPadding),
            labelView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            labelView.widthAnchor.constraint(equalToConstant: 60),

            valueView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.valueLeading),
            valueView.topAnchor.constraint(equalTo: labelView.topAnchor),
            valueView.widthAnchor.constraint(equalToConstant: 72),

            detailView.leadingAnchor.constraint(greaterThanOrEqualTo: valueView.trailingAnchor, constant: 8),
            detailView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuLayout.horizontalPadding),
            detailView.topAnchor.constraint(equalTo: labelView.topAnchor)
        ])
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let usedPercent else { return }

        let railX = MenuLayout.railLeading
        let railY: CGFloat = 28
        let railHeight: CGFloat = 3
        let railWidth = bounds.width - (MenuLayout.horizontalPadding * 2)
        let railRect = NSRect(x: railX, y: railY, width: railWidth, height: railHeight)
        NSColor.separatorColor.withAlphaComponent(0.38).setFill()
        NSBezierPath(roundedRect: railRect, xRadius: railHeight / 2, yRadius: railHeight / 2).fill()

        let usedRatio = max(0, min(usedPercent / 100, 1))
        let fillWidth = usedRatio == 0 ? 3 : max(3, railWidth * usedRatio)
        let fillRect = NSRect(x: railX, y: railY, width: fillWidth, height: railHeight)
        providerColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: railHeight / 2, yRadius: railHeight / 2).fill()

        guard let pacePercent else { return }
        let paceRatio = max(0, min(pacePercent / 100, 1))
        let tickX = railX + railWidth * paceRatio
        let tickRect = NSRect(x: tickX - 1, y: railY - 4, width: 2, height: 11)
        NSColor.labelColor.withAlphaComponent(0.62).setFill()
        NSBezierPath(roundedRect: tickRect, xRadius: 1, yRadius: 1).fill()
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class MenuCostRowView: NSView {
    init(label: String, value: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: 34))
        wantsLayer = true

        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 13, weight: .semibold)
        labelView.textColor = .labelColor
        labelView.translatesAutoresizingMaskIntoConstraints = false

        let valueView = NSTextField(labelWithString: value)
        valueView.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
        valueView.textColor = .secondaryLabelColor
        valueView.alignment = .right
        valueView.lineBreakMode = .byTruncatingHead
        valueView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(labelView)
        addSubview(valueView)

        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.horizontalPadding),
            labelView.centerYAnchor.constraint(equalTo: centerYAnchor),

            valueView.leadingAnchor.constraint(greaterThanOrEqualTo: labelView.trailingAnchor, constant: 12),
            valueView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuLayout.horizontalPadding),
            valueView.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueView.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        ])
    }

    override var isFlipped: Bool { true }

    required init?(coder: NSCoder) {
        nil
    }
}

private enum DetailMenuLayout {
    static let width: CGFloat = 460
    static let horizontalPadding: CGFloat = 16
    static let labelWidth: CGFloat = 128
    static let rowHeight: CGFloat = 28
}

private final class DetailTitleRowView: NSView {
    init(title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: DetailMenuLayout.width, height: 34))

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13.5, weight: .semibold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DetailMenuLayout.horizontalPadding),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -DetailMenuLayout.horizontalPadding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class DetailRowView: NSView {
    init(label: String, value: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: DetailMenuLayout.width, height: DetailMenuLayout.rowHeight))

        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 12.5, weight: .medium)
        labelView.textColor = .secondaryLabelColor
        labelView.translatesAutoresizingMaskIntoConstraints = false

        let valueView = NSTextField(labelWithString: value)
        valueView.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .regular)
        valueView.textColor = .labelColor
        valueView.alignment = .right
        valueView.lineBreakMode = .byTruncatingMiddle
        valueView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(labelView)
        addSubview(valueView)

        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DetailMenuLayout.horizontalPadding),
            labelView.centerYAnchor.constraint(equalTo: centerYAnchor),
            labelView.widthAnchor.constraint(equalToConstant: DetailMenuLayout.labelWidth),

            valueView.leadingAnchor.constraint(equalTo: labelView.trailingAnchor, constant: 14),
            valueView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DetailMenuLayout.horizontalPadding),
            valueView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class DetailFootnoteRowView: NSView {
    init(text: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: DetailMenuLayout.width, height: 32))

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DetailMenuLayout.horizontalPadding),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -DetailMenuLayout.horizontalPadding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

/// An empty view used to add breathing room between sections without a divider line.
private final class MenuSpacerView: NSView {
    init(height: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: height))
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private enum FooterLayout {
    static let captionHeight: CGFloat = 30
    static let rowHeight: CGFloat = 34
}

private final class MenuFooterView: NSView {
    init(updatedText: String, target: AnyObject, refreshAction: Selector, feedbackAction: Selector) {
        let rows: [MenuActionRow] = [
            MenuActionRow(title: "Refresh", symbolName: "arrow.clockwise", target: target, action: refreshAction),
            MenuActionRow(
                title: "Check for Updates",
                symbolName: "arrow.down.circle",
                target: UpdaterController.shared,
                action: #selector(UpdaterController.checkForUpdates(_:))
            ),
            MenuActionRow(title: "Send Feedback", symbolName: "bubble.left", target: target, action: feedbackAction),
            MenuActionRow(
                title: "Quit",
                symbolName: "power",
                shortcut: "⌘Q",
                target: NSApp,
                action: #selector(NSApplication.terminate(_:))
            )
        ]
        let totalHeight = FooterLayout.captionHeight + CGFloat(rows.count) * FooterLayout.rowHeight
        super.init(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: totalHeight))
        wantsLayer = true

        let caption = NSTextField(labelWithString: updatedText)
        caption.font = .systemFont(ofSize: 12, weight: .regular)
        caption.textColor = .tertiaryLabelColor
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(caption)

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.horizontalPadding),
            caption.topAnchor.constraint(equalTo: topAnchor, constant: 7),

            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: FooterLayout.captionHeight),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    override var isFlipped: Bool { true }

    required init?(coder: NSCoder) {
        nil
    }
}

/// A full-width menu row: leading icon, label, optional trailing shortcut.
/// No persistent background; the whole row softly highlights on hover.
private final class MenuActionRow: NSButton {
    init(title: String, symbolName: String, shortcut: String? = nil, target: AnyObject?, action: Selector?) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: FooterLayout.rowHeight))
        self.target = target
        self.action = action
        self.title = ""
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        let icon = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(config)
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13.5, weight: .regular)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: MenuLayout.width),
            heightAnchor.constraint(equalToConstant: FooterLayout.rowHeight),

            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.horizontalPadding),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),

            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        if let shortcut {
            let keys = NSTextField(labelWithString: shortcut)
            keys.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            keys.textColor = .tertiaryLabelColor
            keys.translatesAutoresizingMaskIntoConstraints = false
            addSubview(keys)
            NSLayoutConstraint.activate([
                keys.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuLayout.horizontalPadding),
                keys.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }

    override var isFlipped: Bool { true }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = isHighlighted
            ? NSColor.labelColor.withAlphaComponent(0.07).cgColor
            : NSColor.clear.cgColor
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        enclosingMenuItem?.menu?.cancelTracking()
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private func providerImage(named name: String) -> NSImage? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
          let image = NSImage(contentsOf: url)?.copy() as? NSImage
    else { return nil }
    image.isTemplate = true
    return image
}

private func mascotImage() -> NSImage? {
    guard let url = Bundle.main.url(forResource: "logo", withExtension: "png") else { return nil }
    return NSImage(contentsOf: url)
}

private final class UsageMenuContext: NSObject {
    let providerKey: String
    let providerName: String
    let planName: String
    let snapshot: UsageSnapshot

    init(providerKey: String, providerName: String, planName: String, snapshot: UsageSnapshot) {
        self.providerKey = providerKey
        self.providerName = providerName
        self.planName = planName
        self.snapshot = snapshot
    }

    var usage: ProviderUsage {
        providerKey == "codex" ? snapshot.codexUsage : snapshot.claudeUsage
    }
}

@MainActor
final class UsageBarController: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var latestSnapshot: UsageSnapshot?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UpdaterController.shared.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updaterStateDidChange),
            name: UpdaterController.stateDidChangeNotification,
            object: UpdaterController.shared
        )
        configureButton()
        if let cached = SnapshotCache.load() {
            render(cached)
        }
        refreshInBackground()
        timer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshInBackground() }
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.attributedTitle = statusTitle(providers: [])
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        button.toolTip = "Coco Usage Bar: Codex and Claude Code usage"
    }

    @objc private func refreshFromMenu() {
        refreshInBackground(force: true)
    }

    @objc private func updaterStateDidChange() {
        guard let latestSnapshot else { return }
        statusItem.menu = menu(for: latestSnapshot)
    }

    @objc private func sendFeedbackFromMenu() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Coco Usage Bar feedback"),
            URLQueryItem(name: "body", value: feedbackEmailBody())
        ]

        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func copyUsageSummaryFromMenu(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? UsageMenuContext else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(usageSummaryText(snapshot: context.snapshot), forType: .string)
    }

    @objc private func createImageSnapshotFromMenu(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? UsageMenuContext,
              let url = createSnapshotPNG(snapshot: context.snapshot)
        else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func feedbackEmailBody() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return """


---
Coco Usage Bar \(version) (\(build))
"""
    }

    private func usageSummaryText(snapshot: UsageSnapshot) -> String {
        var lines = [
            "Coco Usage Bar — last 30 days",
            "Generated \(dateTime(snapshot.generatedAt))",
            ""
        ]

        if snapshot.codexUsage.thirtyDays.totalTokens > 0 {
            lines.append(providerSummaryLine(name: "Codex", usage: snapshot.codexUsage))
        }
        if snapshot.claudeUsage.thirtyDays.totalTokens > 0 {
            lines.append(providerSummaryLine(name: "Claude Code", usage: snapshot.claudeUsage))
        }

        lines.append("")
        lines.append("Estimated from local token logs using public API pricing. Not an invoice.")
        return lines.joined(separator: "\n")
    }

    private func providerSummaryLine(name: String, usage: ProviderUsage) -> String {
        let window = usage.thirtyDays
        var parts = [
            "\(name): \(exactTokens(window.totalTokens)) raw tokens",
            "\(cacheShare(window)) cached",
            "estimated cost \(exactDollars(window.estimatedCostUSD))"
        ]
        if window.sessionCount > 0 {
            parts.append("\(exactCount(window.sessionCount)) sessions")
        }
        if let source = compactBreakdown(window.sourceTokens, total: window.totalTokens) {
            parts.append(source)
        }
        return "- " + parts.joined(separator: " · ")
    }

    private func createSnapshotPNG(snapshot: UsageSnapshot) -> URL? {
        let image = snapshotImage(snapshot: snapshot)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CocoUsageBar", isDirectory: true)
            .appendingPathComponent("Snapshots", isDirectory: true)
        do {
            try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let url = support.appendingPathComponent("CocoUsageSnapshot-\(formatter.string(from: Date())).png")
            try png.write(to: url, options: [.atomic])

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
            pasteboard.setString(url.absoluteString, forType: .fileURL)
            return url
        } catch {
            return nil
        }
    }

    private func snapshotImage(snapshot: UsageSnapshot) -> NSImage {
        let size = NSSize(width: 900, height: 520)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor(calibratedWhite: 0.055, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        drawRoundedRect(NSRect(x: 28, y: 28, width: size.width - 56, height: size.height - 56), radius: 28, color: NSColor(calibratedWhite: 0.09, alpha: 1))
        if let mascot = mascotImage() {
            mascot.draw(in: topRect(x: 58, y: 58, width: 72, height: 72, canvasHeight: size.height), from: .zero, operation: .sourceOver, fraction: 1)
        }

        drawText("Coco Usage Snapshot", x: 148, top: 62, width: 500, height: 30, canvasHeight: size.height, font: .systemFont(ofSize: 27, weight: .bold), color: .white)
        drawText("Last 30 days · \(dateOnly(snapshot.generatedAt))", x: 150, top: 97, width: 420, height: 20, canvasHeight: size.height, font: .systemFont(ofSize: 15, weight: .regular), color: NSColor.secondaryLabelColor)
        drawText("local only", x: 720, top: 72, width: 120, height: 22, canvasHeight: size.height, font: .systemFont(ofSize: 14, weight: .semibold), color: providerAccentColor(iconName: "codex-mark"), alignment: .right)

        let codexRect = NSRect(x: 58, y: 245, width: 378, height: 150)
        let claudeRect = NSRect(x: 464, y: 245, width: 378, height: 150)
        if snapshot.codexUsage.thirtyDays.totalTokens > 0 {
            drawProviderCard(name: "Codex", plan: snapshot.codexLimits?.planType ?? "local logs", usage: snapshot.codexUsage, accent: providerAccentColor(iconName: "codex-mark"), rect: codexRect, canvasHeight: size.height)
        }
        if snapshot.claudeUsage.thirtyDays.totalTokens > 0 {
            drawProviderCard(name: "Claude Code", plan: snapshot.claudeLimits?.planType ?? "local logs", usage: snapshot.claudeUsage, accent: providerAccentColor(iconName: "claude-mark"), rect: claudeRect, canvasHeight: size.height)
        }

        let statsY: CGFloat = 338
        drawStatPill(title: "Codex sessions", value: snapshot.codexUsage.thirtyDays.sessionCount > 0 ? exactCount(snapshot.codexUsage.thirtyDays.sessionCount) : "n/a", x: 58, top: statsY, canvasHeight: size.height)
        drawStatPill(title: "Heaviest day", value: heaviestDay(snapshot.codexUsage.thirtyDays) ?? "n/a", x: 304, top: statsY, canvasHeight: size.height)
        drawStatPill(title: "Source split", value: compactBreakdown(snapshot.codexUsage.thirtyDays.sourceTokens, total: snapshot.codexUsage.thirtyDays.totalTokens) ?? "n/a", x: 550, top: statsY, canvasHeight: size.height)

        drawText("Estimated from local token logs · public API pricing · not an invoice · prompts and local filenames excluded",
                 x: 58,
                 top: 456,
                 width: 784,
                 height: 20,
                 canvasHeight: size.height,
                 font: .systemFont(ofSize: 13, weight: .regular),
                 color: NSColor.tertiaryLabelColor)
        return image
    }

    private func drawProviderCard(name: String, plan: String, usage: ProviderUsage, accent: NSColor, rect: NSRect, canvasHeight: CGFloat) {
        let drawRect = topRect(x: rect.origin.x, y: rect.origin.y, width: rect.width, height: rect.height, canvasHeight: canvasHeight)
        drawRoundedRect(drawRect, radius: 18, color: NSColor(calibratedWhite: 0.12, alpha: 1))
        drawText(name, x: rect.origin.x + 20, top: rect.origin.y + 18, width: 180, height: 22, canvasHeight: canvasHeight, font: .systemFont(ofSize: 18, weight: .bold), color: .white)
        drawText(plan, x: rect.origin.x + rect.width - 160, top: rect.origin.y + 20, width: 138, height: 18, canvasHeight: canvasHeight, font: .systemFont(ofSize: 13, weight: .semibold), color: accent, alignment: .right)
        drawText(compactTokens(usage.thirtyDays.totalTokens), x: rect.origin.x + 20, top: rect.origin.y + 58, width: 160, height: 38, canvasHeight: canvasHeight, font: .systemFont(ofSize: 35, weight: .heavy), color: .white)
        drawText("raw tokens", x: rect.origin.x + 22, top: rect.origin.y + 99, width: 140, height: 18, canvasHeight: canvasHeight, font: .systemFont(ofSize: 13, weight: .regular), color: NSColor.secondaryLabelColor)
        drawText("Estimated cost", x: rect.origin.x + 210, top: rect.origin.y + 60, width: 130, height: 18, canvasHeight: canvasHeight, font: .systemFont(ofSize: 13, weight: .regular), color: NSColor.secondaryLabelColor, alignment: .right)
        drawText(compactDollars(usage.thirtyDays.estimatedCostUSD), x: rect.origin.x + 200, top: rect.origin.y + 82, width: 142, height: 28, canvasHeight: canvasHeight, font: .systemFont(ofSize: 25, weight: .bold), color: .white, alignment: .right)
        drawText("\(cacheShare(usage.thirtyDays)) cached", x: rect.origin.x + 20, top: rect.origin.y + 122, width: 220, height: 18, canvasHeight: canvasHeight, font: .systemFont(ofSize: 13, weight: .medium), color: accent)
    }

    private func drawStatPill(title: String, value: String, x: CGFloat, top: CGFloat, canvasHeight: CGFloat) {
        let rect = topRect(x: x, y: top, width: 210, height: 72, canvasHeight: canvasHeight)
        drawRoundedRect(rect, radius: 14, color: NSColor(calibratedWhite: 0.12, alpha: 1))
        drawText(value, x: x + 16, top: top + 14, width: 178, height: 24, canvasHeight: canvasHeight, font: .systemFont(ofSize: 18, weight: .bold), color: .white)
        drawText(title, x: x + 16, top: top + 42, width: 178, height: 18, canvasHeight: canvasHeight, font: .systemFont(ofSize: 12, weight: .regular), color: NSColor.secondaryLabelColor)
    }

    private func drawRoundedRect(_ rect: NSRect, radius: CGFloat, color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    private func drawText(
        _ text: String,
        x: CGFloat,
        top: CGFloat,
        width: CGFloat,
        height: CGFloat,
        canvasHeight: CGFloat,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .left
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let rect = topRect(x: x, y: top, width: width, height: height, canvasHeight: canvasHeight)
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }

    private func topRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, canvasHeight: CGFloat) -> NSRect {
        NSRect(x: x, y: canvasHeight - y - height, width: width, height: height)
    }

    private func refreshInBackground(force: Bool = false) {
        guard force || !isRefreshing else { return }
        isRefreshing = true
        Task.detached(priority: .utility) {
            let snapshot = UsageReader().load()
            await MainActor.run {
                SnapshotCache.save(snapshot)
                self.render(snapshot)
                self.isRefreshing = false
            }
        }
    }

    private func render(_ snapshot: UsageSnapshot) {
        latestSnapshot = snapshot
        statusItem.button?.attributedTitle = attributedTitle(for: snapshot)
        statusItem.menu = menu(for: snapshot)
    }

    private func attributedTitle(for snapshot: UsageSnapshot) -> NSAttributedString {
        var providers: [(icon: String, fallback: String, metric: String)] = []
        if let metric = statusMetric(limits: snapshot.codexLimits, usage: snapshot.codexUsage, allowTokenFallback: true) {
            providers.append(("codex-mark", "⌘", metric))
        }
        if let metric = statusMetric(limits: snapshot.claudeLimits, usage: snapshot.claudeUsage, allowTokenFallback: false) {
            providers.append(("claude-mark", "✦", metric))
        }
        return statusTitle(providers: providers)
    }

    private func statusTitle(providers: [(icon: String, fallback: String, metric: String)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        guard !providers.isEmpty else {
            appendText("--", to: result)
            return result
        }

        for (index, provider) in providers.enumerated() {
            if index > 0 {
                appendText("  ·  ", to: result)
            }
            appendProviderMark(provider.icon, fallback: provider.fallback, to: result)
            appendText(" \(provider.metric)", to: result)
        }
        return result
    }

    private func appendProviderMark(_ name: String, fallback: String, to result: NSMutableAttributedString) {
        guard let image = providerImage(named: name) else {
            appendText(fallback, to: result)
            return
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = CGRect(x: 0, y: -2, width: 12, height: 12)
        result.append(NSAttributedString(attachment: attachment))
    }

    private func appendText(_ text: String, to result: NSMutableAttributedString) {
        result.append(NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
        ))
    }

    private func menu(for snapshot: UsageSnapshot) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.minimumWidth = MenuLayout.width

        let codexVisible = hasProviderData(limits: snapshot.codexLimits, usage: snapshot.codexUsage)
        let claudeVisible = hasProviderData(limits: snapshot.claudeLimits, usage: snapshot.claudeUsage)

        if codexVisible {
            addProviderSection(
                providerKey: "codex",
                title: "Codex",
                iconName: "codex-mark",
                limits: snapshot.codexLimits,
                usage: snapshot.codexUsage,
                missingLimitDetail: "n/a",
                referenceDate: snapshot.generatedAt,
                snapshot: snapshot,
                to: menu
            )
        }

        if codexVisible && claudeVisible {
            menu.addItem(.separator())
        }

        if claudeVisible {
            addProviderSection(
                providerKey: "claude",
                title: "Claude Code",
                iconName: "claude-mark",
                limits: snapshot.claudeLimits,
                usage: snapshot.claudeUsage,
                missingLimitDetail: "needs account",
                referenceDate: snapshot.generatedAt,
                snapshot: snapshot,
                to: menu
            )
        }

        if !codexVisible && !claudeVisible {
            addView(MenuCostRowView(label: "No local usage yet", value: "Refresh after a session"), to: menu)
        }

        menu.addItem(.separator())
        let updated = NSMenuItem(title: "Updated \(timeOnly(snapshot.generatedAt))", action: nil, keyEquivalent: "")
        updated.isEnabled = false
        menu.addItem(updated)

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let update = NSMenuItem(title: UpdaterController.shared.menuTitle, action: #selector(UpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        update.target = UpdaterController.shared
        update.isEnabled = UpdaterController.shared.canCheckForUpdates
        menu.addItem(update)

        let feedback = NSMenuItem(title: "Send Feedback", action: #selector(sendFeedbackFromMenu), keyEquivalent: "")
        feedback.target = self
        menu.addItem(feedback)

        let quit = NSMenuItem(title: "Quit Coco Usage Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)

        return menu
    }

    private func addProviderSection(
        providerKey: String,
        title: String,
        iconName: String,
        limits: CodexRateLimits?,
        usage: ProviderUsage,
        missingLimitDetail: String,
        referenceDate: Date,
        snapshot: UsageSnapshot,
        to menu: NSMenu
    ) {
        let headerDetail = limits == nil ? "local logs" : (limits?.planType ?? "limits")
        let providerColor = providerAccentColor(iconName: iconName)
        addView(MenuHeaderView(iconName: iconName, title: title, detail: headerDetail), to: menu)
        addView(
            rateView(
                label: "5h",
                window: limits?.primary,
                missingDetail: missingLimitDetail,
                providerColor: providerColor,
                referenceDate: referenceDate
            ),
            to: menu
        )
        addView(
            rateView(
                label: "Weekly",
                window: limits?.secondary,
                missingDetail: missingLimitDetail,
                providerColor: providerColor,
                referenceDate: referenceDate
            ),
            to: menu
        )

        let thirtyDays = usage.thirtyDays
        if thirtyDays.totalTokens > 0 {
            menu.addItem(usageDetailMenuItem(
                providerKey: providerKey,
                providerName: title,
                planName: headerDetail,
                usage: usage,
                snapshot: snapshot
            ))
        } else {
            addView(MenuCostRowView(label: "30d raw tokens", value: "No local tokens"), to: menu)
        }
    }

    private func usageDetailMenuItem(
        providerKey: String,
        providerName: String,
        planName: String,
        usage: ProviderUsage,
        snapshot: UsageSnapshot
    ) -> NSMenuItem {
        let window = usage.thirtyDays
        let item = NSMenuItem(
            title: "30d raw tokens    \(compactTokenSummary(window))",
            action: nil,
            keyEquivalent: ""
        )
        let context = UsageMenuContext(providerKey: providerKey, providerName: providerName, planName: planName, snapshot: snapshot)
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        addDetailTitle("\(providerName) details", to: submenu)
        submenu.addItem(.separator())
        addDetailRow("Raw tokens", exactTokens(window.totalTokens), to: submenu)
        addDetailRow("Estimated cost", exactDollars(window.estimatedCostUSD), to: submenu)
        addDetailRow("Pricing basis", pricingBasisSummary(window), to: submenu)
        submenu.addItem(.separator())
        addDetailRow("Input", exactTokens(window.inputTokens), to: submenu)
        if window.cachedInputTokens > 0 {
            addDetailRow("Cached input", exactTokens(window.cachedInputTokens), to: submenu)
        }
        if window.cacheWriteTokens > 0 {
            addDetailRow("Cache write", exactTokens(window.cacheWriteTokens), to: submenu)
        }
        if window.cacheReadTokens > 0 {
            addDetailRow("Cache read", exactTokens(window.cacheReadTokens), to: submenu)
        }
        addDetailRow("Output", exactTokens(window.outputTokens), to: submenu)
        if window.reasoningTokens > 0 {
            addDetailRow("Reasoning", exactTokens(window.reasoningTokens), to: submenu)
        }
        addDetailRow("Cache share", cacheShare(window), to: submenu)
        submenu.addItem(.separator())
        addDetailRow("Events", exactCount(window.eventCount), to: submenu)
        if window.sessionCount > 0 {
            addDetailRow("Sessions", exactCount(window.sessionCount), to: submenu)
            addDetailRow("Avg / session", compactTokens(window.totalTokens / Int64(max(window.sessionCount, 1))), to: submenu)
        }
        if let heaviest = heaviestDay(window) {
            addDetailRow("Heaviest day", heaviest, to: submenu)
        }
        if let source = compactBreakdown(window.sourceTokens, total: window.totalTokens) {
            addDetailRow("Source split", source, to: submenu)
        }
        if let model = compactBreakdown(window.modelTokens, total: window.totalTokens) {
            addDetailRow("Model split", model, to: submenu)
        }
        submenu.addItem(.separator())

        let copy = NSMenuItem(title: "Copy summary", action: #selector(copyUsageSummaryFromMenu(_:)), keyEquivalent: "c")
        copy.target = self
        copy.representedObject = context
        submenu.addItem(copy)

        let image = NSMenuItem(title: "Create image snapshot", action: #selector(createImageSnapshotFromMenu(_:)), keyEquivalent: "")
        image.target = self
        image.representedObject = context
        submenu.addItem(image)

        addDetailFootnote("Estimated from local token logs · not an invoice", to: submenu)
        item.submenu = submenu
        return item
    }

    private func addDetailTitle(_ title: String, to menu: NSMenu) {
        addView(DetailTitleRowView(title: title), to: menu)
    }

    private func addDetailRow(_ label: String, _ value: String, to menu: NSMenu) {
        addView(DetailRowView(label: label, value: value), to: menu)
    }

    private func addDetailFootnote(_ title: String, to menu: NSMenu) {
        addView(DetailFootnoteRowView(text: title), to: menu)
    }

    private func rateView(
        label: String,
        window: RateWindow?,
        missingDetail: String,
        providerColor: NSColor,
        referenceDate: Date
    ) -> NSView {
        guard let window, let percent = window.usedPercent else {
            return MenuLimitRowView(
                label: label,
                value: attributedValue(primary: "n/a"),
                detail: attributedDetail(missingDetail),
                usedPercent: nil,
                pacePercent: nil,
                providerColor: providerColor
            )
        }

        let detail = window.resetsAt.map { attributedResetDetail($0) } ?? attributedDetail("reset n/a")
        return MenuLimitRowView(
            label: label,
            value: attributedValue(primary: formatPercent(percent), suffix: " used"),
            detail: detail,
            usedPercent: percent,
            pacePercent: pacePercent(for: window, at: referenceDate),
            providerColor: providerColor
        )
    }

    private func addView(_ view: NSView, to menu: NSMenu) {
        let item = NSMenuItem()
        item.view = view
        menu.addItem(item)
    }

    private func providerAccentColor(iconName: String) -> NSColor {
        if iconName == "claude-mark" {
            return NSColor(calibratedRed: 0.9, green: 0.58, blue: 0.34, alpha: 1)
        }
        return NSColor(calibratedRed: 0.42, green: 0.84, blue: 0.78, alpha: 1)
    }

    private func attributedValue(primary: String, suffix: String? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString(string: primary, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ])
        if let suffix {
            result.append(NSAttributedString(string: suffix, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }
        return result
    }

    private func attributedDetail(_ value: String) -> NSAttributedString {
        NSAttributedString(string: value, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
    }

    private func attributedResetDetail(_ date: Date) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "reset ", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ])
        result.append(NSAttributedString(string: resetLabel(date), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
        return result
    }

    private func pacePercent(for window: RateWindow, at date: Date) -> Double? {
        guard let resetsAt = window.resetsAt,
              let windowMinutes = window.windowMinutes,
              windowMinutes > 0
        else { return nil }

        let duration = TimeInterval(windowMinutes * 60)
        let startsAt = resetsAt.addingTimeInterval(-duration)
        let elapsed = date.timeIntervalSince(startsAt)
        return max(0, min(elapsed / duration * 100, 100))
    }

    private func statusMetric(limits: CodexRateLimits?, usage: ProviderUsage, allowTokenFallback: Bool) -> String? {
        if let percent = limits?.primary?.usedPercent {
            return formatPercent(percent)
        }
        if allowTokenFallback, usage.thirtyDays.totalTokens > 0 {
            return compactTokens(usage.thirtyDays.totalTokens)
        }
        return nil
    }

    private func hasProviderData(limits: CodexRateLimits?, usage: ProviderUsage) -> Bool {
        limits != nil || usage.thirtyDays.totalTokens > 0
    }

    private func exactTokens(_ tokens: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: tokens)) ?? "\(tokens)"
    }

    private func exactCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func exactDollars(_ dollars: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = dollars >= 1_000 ? 0 : 2
        return formatter.string(from: NSNumber(value: dollars)) ?? String(format: "$%.2f", dollars)
    }

    private func cacheShare(_ window: TokenWindow) -> String {
        let cached = window.cachedInputTokens + window.cacheReadTokens
        guard window.totalTokens > 0, cached > 0 else { return "0%" }
        return formatPercent(Double(cached) / Double(window.totalTokens) * 100)
    }

    private func pricingBasisSummary(_ window: TokenWindow) -> String {
        guard let top = window.pricingBasisTokens.max(by: { $0.value < $1.value }) else {
            return "Public API pricing"
        }
        if window.pricingBasisTokens.count == 1, window.fallbackPricedTokens == 0, window.unpricedTokens == 0 {
            return top.key
        }
        var parts = ["Mixed public API pricing"]
        if window.fallbackPricedTokens > 0 {
            parts.append("\(compactTokens(window.fallbackPricedTokens)) fallback")
        }
        if window.unpricedTokens > 0 {
            parts.append("\(compactTokens(window.unpricedTokens)) unpriced")
        }
        return parts.joined(separator: " · ")
    }

    private func heaviestDay(_ window: TokenWindow) -> String? {
        guard let entry = window.dayTokens.max(by: { $0.value < $1.value }) else { return nil }
        let input = DateFormatter()
        input.calendar = Calendar(identifier: .gregorian)
        input.locale = Locale(identifier: "en_US_POSIX")
        input.dateFormat = "yyyy-MM-dd"
        let output = DateFormatter()
        output.dateFormat = "d MMM"
        let label = input.date(from: entry.key).map { output.string(from: $0) } ?? entry.key
        return "\(label) · \(compactTokens(entry.value))"
    }

    private func compactBreakdown(_ values: [String: Int64], total: Int64) -> String? {
        guard total > 0, !values.isEmpty else { return nil }
        return values
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map { key, value in
                let percent = Double(value) / Double(total) * 100
                return "\(key) \(formatPercent(percent))"
            }
            .joined(separator: " · ")
    }

    private func compactTokens(_ tokens: Int64) -> String {
        let value = Double(tokens)
        switch tokens {
        case 1_000_000_000...:
            return String(format: "%.1fB", value / 1_000_000_000).replacingOccurrences(of: ".0B", with: "B")
        case 1_000_000...:
            return String(format: "%.1fM", value / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        case 1_000...:
            return String(format: "%.0fk", value / 1_000)
        default:
            return "\(tokens)"
        }
    }

    private func compactTokenSummary(_ window: TokenWindow) -> String {
        let total = window.totalTokens
        let cached = window.cachedInputTokens + window.cacheReadTokens
        guard total > 0, cached > 0 else { return compactTokens(total) }

        let cachedPercent = Double(cached) / Double(total) * 100
        guard cachedPercent >= 1 else { return compactTokens(total) }

        return "\(compactTokens(total)), \(Int(cachedPercent.rounded()))% cached"
    }

    private func compactDollars(_ dollars: Double) -> String {
        switch dollars {
        case 1_000...:
            return String(format: "$%.1fk", dollars / 1_000).replacingOccurrences(of: ".0k", with: "k")
        case 100...:
            return String(format: "$%.0f", dollars)
        case 10...:
            return String(format: "$%.1f", dollars)
        case 0.01...:
            return String(format: "$%.2f", dollars)
        default:
            return "$0"
        }
    }

    private func formatPercent(_ percent: Double) -> String {
        if percent.rounded() == percent {
            return "\(Int(percent))%"
        }
        return String(format: "%.1f%%", percent)
    }

    private func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func dateOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func timeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func resetLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.timeStyle = .short
            formatter.dateStyle = .none
            return formatter.string(from: date)
        }
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    private func relativeReset(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval > 0, interval < 24 * 60 * 60 {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            if hours > 0 {
                return "in \(hours)h \(minutes)m"
            }
            return "in \(max(minutes, 0))m"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

func printSnapshot() {
    let snapshot = UsageReader(debugTiming: CommandLine.arguments.contains("--debug-timing")).load()
    print("title: \(controllerTitle(snapshot))")
    if let limits = snapshot.codexLimits {
        let primary = limits.primary?.usedPercent.map { "\(Int($0.rounded()))%" } ?? "--"
        let secondary = limits.secondary?.usedPercent.map { "\(Int($0.rounded()))%" } ?? "--"
        print("codex: 5h \(primary), 7d \(secondary)")
    } else {
        print("codex: no rate limits")
    }
    if let limits = snapshot.claudeLimits {
        let primary = limits.primary?.usedPercent.map { "\(Int($0.rounded()))%" } ?? "--"
        let secondary = limits.secondary?.usedPercent.map { "\(Int($0.rounded()))%" } ?? "--"
        print("claude: 5h \(primary), 7d \(secondary)")
    } else {
        print("claude: no rate limits")
    }
    print("codex_30d_tokens: \(snapshot.codexUsage.thirtyDays.totalTokens)")
    print("codex_30d_estimated_cost_usd: \(formatCost(snapshot.codexUsage.thirtyDays.estimatedCostUSD))")
    print("claude_30d_tokens: \(snapshot.claudeUsage.thirtyDays.totalTokens)")
    print("claude_30d_estimated_cost_usd: \(formatCost(snapshot.claudeUsage.thirtyDays.estimatedCostUSD))")
}

func controllerTitle(_ snapshot: UsageSnapshot) -> String {
    var parts: [String] = []
    if let metric = commandLineMetric(limits: snapshot.codexLimits, usage: snapshot.codexUsage) {
        parts.append("Codex \(metric)")
    }
    if let metric = commandLineMetric(limits: snapshot.claudeLimits, usage: snapshot.claudeUsage, allowTokenFallback: false) {
        parts.append("Claude \(metric)")
    }
    return parts.isEmpty ? "--" : parts.joined(separator: " · ")
}

func commandLineMetric(limits: CodexRateLimits?, usage: ProviderUsage, allowTokenFallback: Bool = true) -> String? {
    if let percent = limits?.primary?.usedPercent {
        return percent.rounded() == percent ? "\(Int(percent))%" : String(format: "%.1f%%", percent)
    }
    if allowTokenFallback, usage.thirtyDays.totalTokens > 0 {
        return formatTokens(usage.thirtyDays.totalTokens)
    }
    return nil
}

func formatTokens(_ tokens: Int64) -> String {
    let value = Double(tokens)
    switch tokens {
    case 1_000_000_000...:
        return String(format: "%.1fB", value / 1_000_000_000).replacingOccurrences(of: ".0B", with: "B")
    case 1_000_000...:
        return String(format: "%.1fM", value / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
    case 1_000...:
        return String(format: "%.0fk", value / 1_000)
    default:
        return "\(tokens)"
    }
}

func formatCost(_ dollars: Double) -> String {
    String(format: "%.2f", dollars)
}

if CommandLine.arguments.contains("--print-snapshot") {
    printSnapshot()
    exit(0)
}

let app = NSApplication.shared
let delegate = UsageBarController()
app.delegate = delegate
app.run()
