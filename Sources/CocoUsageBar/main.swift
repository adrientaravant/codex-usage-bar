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

    mutating func add(_ sample: UsageSample, at date: Date) {
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
}

struct ProviderUsage: Codable {
    var today = TokenWindow()
    var sevenDays = TokenWindow()
    var thirtyDays = TokenWindow()

    mutating func add(_ sample: UsageSample, at date: Date, todayStart: Date, sevenDayCutoff: Date, thirtyDayCutoff: Date) {
        guard date >= thirtyDayCutoff else { return }
        thirtyDays.add(sample, at: date)
        if date >= sevenDayCutoff {
            sevenDays.add(sample, at: date)
        }
        if date >= todayStart {
            today.add(sample, at: date)
        }
    }
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

enum CostEstimator {
    // Default Codex estimate: GPT-5.4 short-context API pricing.
    static let codex = TokenPrices(
        inputPerMTok: 1.25,
        cachedInputPerMTok: 0.13,
        cacheWritePerMTok: 1.25,
        cacheReadPerMTok: 0.13,
        outputPerMTok: 7.50
    )

    static func claudePrices(model: String?) -> TokenPrices {
        let normalized = (model ?? "").lowercased()
        if normalized.contains("fable") || normalized.contains("mythos") {
            return TokenPrices(inputPerMTok: 10, cachedInputPerMTok: 1, cacheWritePerMTok: 12.50, cacheReadPerMTok: 1, outputPerMTok: 50)
        }
        if normalized.contains("opus") {
            return TokenPrices(inputPerMTok: 5, cachedInputPerMTok: 0.50, cacheWritePerMTok: 6.25, cacheReadPerMTok: 0.50, outputPerMTok: 25)
        }
        if normalized.contains("haiku") {
            return TokenPrices(inputPerMTok: 1, cachedInputPerMTok: 0.10, cacheWritePerMTok: 1.25, cacheReadPerMTok: 0.10, outputPerMTok: 5)
        }
        return TokenPrices(inputPerMTok: 3, cachedInputPerMTok: 0.30, cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30, outputPerMTok: 15)
    }

    static func cost(
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
    }

    func load() -> UsageSnapshot {
        let now = Date()
        let thirtyDayCutoff = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let sevenDayCutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let todayStart = calendar.startOfDay(for: now)
        let home = fileManager.homeDirectoryForCurrentUser

        debugLog("read codex start")
        let codex = readCodex(
            root: home.appendingPathComponent(".codex/sessions", isDirectory: true),
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
        root: URL,
        sevenDayCutoff: Date,
        thirtyDayCutoff: Date,
        todayStart: Date
    ) -> (limits: CodexRateLimits?, usage: ProviderUsage) {
        var latestLimits: CodexRateLimits?
        var usage = ProviderUsage()
        let roots = codexDateRoots(root: root, from: thirtyDayCutoff, through: Date())
        debugLog("codex roots \(roots.filter { fileManager.fileExists(atPath: $0.path) }.count)")

        let usedRipgrep = forEachRipgrepLine(
            pattern: #""type"\s*:\s*"event_msg".*"rate_limits""#,
            roots: roots.isEmpty ? [root] : roots
        ) { line in
            parseCodexLine(
                line,
                sevenDayCutoff: sevenDayCutoff,
                thirtyDayCutoff: thirtyDayCutoff,
                todayStart: todayStart,
                latestLimits: &latestLimits,
                usage: &usage
            )
        }

        if !usedRipgrep {
            for file in jsonlFiles(under: root, modifiedSince: thirtyDayCutoff.addingTimeInterval(-24 * 60 * 60)) {
                forEachLine(in: file) { line in
                    guard line.contains(#""type":"event_msg""#),
                          line.contains(#""rate_limits""#) || line.contains(#""token_count""#)
                    else { return }
                    parseCodexLine(
                        line,
                        sevenDayCutoff: sevenDayCutoff,
                        thirtyDayCutoff: thirtyDayCutoff,
                        todayStart: todayStart,
                        latestLimits: &latestLimits,
                        usage: &usage
                    )
                }
            }
        }

        return (latestLimits, usage)
    }

    private func parseCodexLine(
        _ line: String,
        sevenDayCutoff: Date,
        thirtyDayCutoff: Date,
        todayStart: Date,
        latestLimits: inout CodexRateLimits?,
        usage: inout ProviderUsage
    ) {
        guard let object = jsonObject(from: line),
              let timestamp = parseTimestamp(object["timestamp"]),
              let payload = object["payload"] as? [String: Any]
        else { return }

        if let rateLimits = payload["rate_limits"] as? [String: Any],
           let parsed = parseCodexRateLimits(rateLimits, updatedAt: timestamp),
           latestLimits == nil || parsed.updatedAt > latestLimits!.updatedAt {
            latestLimits = parsed
        }

        guard (payload["type"] as? String) == "token_count",
              let info = payload["info"] as? [String: Any],
              let lastTokenUsage = info["last_token_usage"] as? [String: Any],
              let sample = codexSample(from: lastTokenUsage)
        else { return }

        usage.add(sample, at: timestamp, todayStart: todayStart, sevenDayCutoff: sevenDayCutoff, thirtyDayCutoff: thirtyDayCutoff)
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
        let usedRipgrep = forEachRipgrepLine(
            pattern: #""usage""#,
            roots: [root]
        ) { line in
            parseClaudeLine(
                line,
                sevenDayCutoff: sevenDayCutoff,
                thirtyDayCutoff: thirtyDayCutoff,
                todayStart: todayStart,
                keyedSamples: &keyedSamples,
                unkeyedSamples: &unkeyedSamples
            )
        }

        if !usedRipgrep {
            for file in jsonlFiles(under: root, modifiedSince: thirtyDayCutoff.addingTimeInterval(-24 * 60 * 60)) {
                forEachLine(in: file) { line in
                    guard line.contains(#""usage""#) else { return }
                    parseClaudeLine(
                        line,
                        sevenDayCutoff: sevenDayCutoff,
                        thirtyDayCutoff: thirtyDayCutoff,
                        todayStart: todayStart,
                        keyedSamples: &keyedSamples,
                        unkeyedSamples: &unkeyedSamples
                    )
                }
            }
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
        sevenDayCutoff: Date,
        thirtyDayCutoff: Date,
        todayStart: Date,
        keyedSamples: inout [String: (date: Date, sample: UsageSample)],
        unkeyedSamples: inout [(date: Date, sample: UsageSample)]
    ) {
        guard let object = jsonObject(from: line),
              (object["type"] as? String) == "assistant",
              let timestamp = parseTimestamp(object["timestamp"]),
              let message = object["message"] as? [String: Any],
              let messageUsage = message["usage"] as? [String: Any],
              let sample = claudeSample(from: messageUsage, model: message["model"] as? String)
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

    private func codexSample(from usage: [String: Any]) -> UsageSample? {
        let rawInput = intValue(usage["input_tokens"]) ?? 0
        let cachedInput = intValue(usage["cached_input_tokens"]) ?? 0
        let input = max(rawInput - cachedInput, 0)
        let output = intValue(usage["output_tokens"]) ?? 0
        let reasoning = intValue(usage["reasoning_output_tokens"]) ?? 0
        let total = rawInput + output + reasoning
        guard total > 0 else { return nil }

        return UsageSample(
            inputTokens: input,
            cachedInputTokens: cachedInput,
            cacheWriteTokens: 0,
            cacheReadTokens: 0,
            outputTokens: output,
            reasoningTokens: reasoning,
            totalTokens: total,
            estimatedCostUSD: CostEstimator.cost(
                inputTokens: input,
                cachedInputTokens: cachedInput,
                outputTokens: output,
                reasoningTokens: reasoning,
                prices: CostEstimator.codex
            )
        )
    }

    private func claudeSample(from usage: [String: Any], model: String?) -> UsageSample? {
        let input = intValue(usage["input_tokens"]) ?? 0
        let cacheWrite = intValue(usage["cache_creation_input_tokens"]) ?? 0
        let cacheRead = intValue(usage["cache_read_input_tokens"]) ?? 0
        let output = intValue(usage["output_tokens"]) ?? 0
        let total = input + cacheWrite + cacheRead + output
        guard total > 0 else { return nil }

        return UsageSample(
            inputTokens: input,
            cachedInputTokens: 0,
            cacheWriteTokens: cacheWrite,
            cacheReadTokens: cacheRead,
            outputTokens: output,
            reasoningTokens: 0,
            totalTokens: total,
            estimatedCostUSD: CostEstimator.cost(
                inputTokens: input,
                cacheWriteTokens: cacheWrite,
                cacheReadTokens: cacheRead,
                outputTokens: output,
                prices: CostEstimator.claudePrices(model: model)
            )
        )
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
    static let width: CGFloat = 380
    static let horizontalPadding: CGFloat = 18
}

private final class MenuHeaderView: NSView {
    init(iconName: String, title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: 42))

        let icon = NSImageView()
        icon.image = providerImage(named: iconName)
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let used = NSTextField(labelWithString: "Used")
        used.font = .systemFont(ofSize: 12, weight: .semibold)
        used.textColor = .secondaryLabelColor
        used.alignment = .right
        used.translatesAutoresizingMaskIntoConstraints = false

        let reset = NSTextField(labelWithString: "Reset")
        reset.font = .systemFont(ofSize: 12, weight: .semibold)
        reset.textColor = .secondaryLabelColor
        reset.alignment = .right
        reset.translatesAutoresizingMaskIntoConstraints = false

        addSubview(icon)
        addSubview(titleLabel)
        addSubview(used)
        addSubview(reset)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.horizontalPadding),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: used.leadingAnchor, constant: -12),

            reset.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuLayout.horizontalPadding),
            reset.centerYAnchor.constraint(equalTo: centerYAnchor),
            reset.widthAnchor.constraint(greaterThanOrEqualToConstant: 78),

            used.trailingAnchor.constraint(equalTo: reset.leadingAnchor, constant: -14),
            used.centerYAnchor.constraint(equalTo: centerYAnchor),
            used.widthAnchor.constraint(greaterThanOrEqualToConstant: 46)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class MenuMetricRowView: NSView {
    init(label: String, value: String, detail: String? = nil, emphasized: Bool = false) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: 32))

        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 13, weight: emphasized ? .semibold : .medium)
        labelView.textColor = .labelColor
        labelView.translatesAutoresizingMaskIntoConstraints = false

        let valueView = NSTextField(labelWithString: value)
        valueView.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueView.textColor = .labelColor
        valueView.alignment = .right
        valueView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(labelView)
        addSubview(valueView)

        var trailingAnchorForValue = trailingAnchor
        var trailingConstant: CGFloat = -MenuLayout.horizontalPadding

        if let detail, !detail.isEmpty {
            let detailView = NSTextField(labelWithString: detail)
            detailView.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
            detailView.textColor = .secondaryLabelColor
            detailView.alignment = .right
            detailView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(detailView)
            trailingAnchorForValue = detailView.leadingAnchor
            trailingConstant = -14

            NSLayoutConstraint.activate([
                detailView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuLayout.horizontalPadding),
                detailView.centerYAnchor.constraint(equalTo: centerYAnchor),
                detailView.widthAnchor.constraint(greaterThanOrEqualToConstant: 78)
            ])
        }

        NSLayoutConstraint.activate([
            labelView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.horizontalPadding),
            labelView.centerYAnchor.constraint(equalTo: centerYAnchor),

            valueView.leadingAnchor.constraint(greaterThanOrEqualTo: labelView.trailingAnchor, constant: 12),
            valueView.trailingAnchor.constraint(equalTo: trailingAnchorForValue, constant: trailingConstant),
            valueView.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueView.widthAnchor.constraint(greaterThanOrEqualToConstant: 46)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }
}

private final class MenuCostRowView: NSView {
    init(label: String, value: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: 36))

        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 13, weight: .semibold)
        labelView.textColor = .labelColor
        labelView.translatesAutoresizingMaskIntoConstraints = false

        let valueView = NSTextField(labelWithString: value)
        valueView.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
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

    required init?(coder: NSCoder) {
        nil
    }
}

private final class MenuFooterView: NSView {
    init(updatedText: String, target: AnyObject, refreshAction: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuLayout.width, height: 36))

        let label = NSTextField(labelWithString: updatedText)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "Refresh", target: target, action: refreshAction)
        refreshButton.font = .systemFont(ofSize: 13, weight: .semibold)
        refreshButton.isBordered = false
        refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshButton.imagePosition = .imageLeading
        refreshButton.contentTintColor = .labelColor
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(label)
        addSubview(refreshButton)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuLayout.horizontalPadding),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            refreshButton.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 18),
            refreshButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuLayout.horizontalPadding),
            refreshButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
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

@MainActor
final class UsageBarController: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var latestSnapshot: UsageSnapshot?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UpdaterController.shared.start()
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

    private func feedbackEmailBody() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return """


---
Coco Usage Bar \(version) (\(build))
"""
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
                title: "Codex",
                iconName: "codex-mark",
                limits: snapshot.codexLimits,
                usage: snapshot.codexUsage,
                missingLimitDetail: "n/a",
                to: menu
            )
        }

        if codexVisible && claudeVisible {
            menu.addItem(.separator())
        }

        if claudeVisible {
            addProviderSection(
                title: "Claude Code",
                iconName: "claude-mark",
                limits: snapshot.claudeLimits,
                usage: snapshot.claudeUsage,
                missingLimitDetail: "needs account",
                to: menu
            )
        }

        if !codexVisible && !claudeVisible {
            addView(MenuCostRowView(label: "No local usage yet", value: "Refresh after a session"), to: menu)
        }

        menu.addItem(.separator())
        addView(
            MenuFooterView(
                updatedText: "Updated \(timeOnly(snapshot.generatedAt))",
                target: self,
                refreshAction: #selector(refreshFromMenu)
            ),
            to: menu
        )

        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(UpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = UpdaterController.shared
        updateItem.isEnabled = true
        menu.addItem(updateItem)

        let feedbackItem = NSMenuItem(
            title: "Send Feedback...",
            action: #selector(sendFeedbackFromMenu),
            keyEquivalent: ""
        )
        feedbackItem.target = self
        feedbackItem.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: "Send Feedback")
        feedbackItem.isEnabled = true
        menu.addItem(feedbackItem)

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        return menu
    }

    private func addProviderSection(
        title: String,
        iconName: String,
        limits: CodexRateLimits?,
        usage: ProviderUsage,
        missingLimitDetail: String,
        to menu: NSMenu
    ) {
        addView(MenuHeaderView(iconName: iconName, title: title), to: menu)
        addView(rateView(label: "5h", window: limits?.primary, missingDetail: missingLimitDetail), to: menu)
        addView(rateView(label: "Weekly", window: limits?.secondary, missingDetail: missingLimitDetail), to: menu)

        let thirtyDays = usage.thirtyDays
        if thirtyDays.totalTokens > 0 {
            let value = "\(compactTokens(thirtyDays.totalTokens)) tokens"
            addView(MenuCostRowView(label: "Last 30 days", value: value), to: menu)
        } else {
            addView(MenuCostRowView(label: "Last 30 days", value: "No local tokens"), to: menu)
        }
    }

    private func rateView(label: String, window: RateWindow?, missingDetail: String) -> NSView {
        guard let window, let percent = window.usedPercent else {
            return MenuMetricRowView(label: label, value: "n/a", detail: missingDetail)
        }

        let detail = window.resetsAt.map(resetLabel)
        return MenuMetricRowView(label: label, value: formatPercent(percent), detail: detail, emphasized: true)
    }

    private func addView(_ view: NSView, to menu: NSMenu) {
        let item = NSMenuItem()
        item.view = view
        menu.addItem(item)
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
