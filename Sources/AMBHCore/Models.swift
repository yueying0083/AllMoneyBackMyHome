import Foundation

public enum Exchange: String, Codable, Sendable {
    case shanghai = "sh"
    case shenzhen = "sz"
}

public struct SecuritySymbol: Codable, Hashable, Identifiable, Sendable {
    public let exchange: Exchange
    public let code: String

    public var id: String { exchange.rawValue + code }
    public var providerCode: String { id }

    public init(exchange: Exchange, code: String) throws {
        guard code.count == 6, code.allSatisfy(\.isNumber) else {
            throw SymbolError.invalidFormat
        }
        self.exchange = exchange
        self.code = code
    }

    public static func parse(_ input: String) throws -> SecuritySymbol {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("sh") || normalized.hasPrefix("sz") {
            let prefix = String(normalized.prefix(2))
            return try SecuritySymbol(
                exchange: prefix == "sh" ? .shanghai : .shenzhen,
                code: String(normalized.dropFirst(2))
            )
        }
        guard normalized.count == 6, normalized.allSatisfy(\.isNumber) else {
            throw SymbolError.invalidFormat
        }
        let exchange: Exchange
        switch normalized.first {
        case "5", "6", "9": exchange = .shanghai
        case "0", "1", "2", "3": exchange = .shenzhen
        default: throw SymbolError.ambiguousExchange
        }
        return try SecuritySymbol(exchange: exchange, code: normalized)
    }
}

public enum SymbolError: LocalizedError, Equatable {
    case invalidFormat
    case ambiguousExchange

    public var errorDescription: String? {
        switch self {
        case .invalidFormat: return "请输入六位证券代码，或使用 sh/sz 前缀"
        case .ambiguousExchange: return "无法判断交易所，请添加 sh 或 sz 前缀"
        }
    }
}

public enum QuoteSource: String, Codable, CaseIterable, Sendable {
    case tencent
    case sina

    public var displayName: String { self == .tencent ? "腾讯" : "新浪" }
    public var alternate: QuoteSource { self == .tencent ? .sina : .tencent }
}

public struct Quote: Codable, Equatable, Sendable {
    public let symbol: SecuritySymbol
    public let name: String
    public let price: Double
    public let previousClose: Double
    public let change: Double
    public let changePercent: Double
    public let timestamp: Date
    public let source: QuoteSource

    public init(symbol: SecuritySymbol, name: String, price: Double, previousClose: Double, change: Double, changePercent: Double, timestamp: Date, source: QuoteSource) {
        self.symbol = symbol
        self.name = name
        self.price = price
        self.previousClose = previousClose
        self.change = change
        self.changePercent = changePercent
        self.timestamp = timestamp
        self.source = source
    }
}

public struct WatchlistItem: Codable, Identifiable, Equatable, Sendable {
    public let symbol: SecuritySymbol
    public var displayName: String?
    public var alias: String?
    public var id: String { symbol.id }

    public init(symbol: SecuritySymbol, displayName: String? = nil, alias: String? = nil) {
        self.symbol = symbol
        self.displayName = displayName
        self.alias = alias
    }

    public func preferredName(quoteName: String? = nil) -> String {
        if let alias, !alias.isEmpty { return alias }
        return quoteName ?? displayName ?? symbol.code
    }
}

public struct IntradayPoint: Codable, Equatable, Sendable, Identifiable {
    public let minute: String
    public let price: Double
    public let sequence: Int
    public var id: Int { sequence }

    public init(minute: String, price: Double, sequence: Int) {
        self.minute = minute
        self.price = price
        self.sequence = sequence
    }
}

public struct CachedIntradaySeries: Codable, Equatable, Sendable {
    public let symbol: SecuritySymbol
    public let points: [IntradayPoint]
    public let fetchedAt: Date

    public init(symbol: SecuritySymbol, points: [IntradayPoint], fetchedAt: Date = Date()) {
        self.symbol = symbol
        self.points = points
        self.fetchedAt = fetchedAt
    }
}

public enum PriceRefreshInterval: Int, Codable, CaseIterable, Sendable {
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case sixtySeconds = 60

    public var seconds: Int { rawValue }
    public var displayName: String { "\(rawValue) 秒" }
}

public enum ChartRefreshInterval: Int, Codable, CaseIterable, Sendable {
    case fiveMinutes = 300
    case tenMinutes = 600

    public var seconds: Int { rawValue }
    public var displayName: String { "\(rawValue / 60) 分钟" }
}

public enum ChinaTradingSession {
    public static let startMinute = 9 * 60 + 30
    public static let morningEndMinute = 11 * 60 + 30
    public static let afternoonStartMinute = 13 * 60
    public static let endMinute = 15 * 60

    public static func minuteOffset(for value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else { return nil }
        let absolute = hour * 60 + minute
        guard (startMinute...endMinute).contains(absolute) else { return nil }
        return absolute - startMinute
    }
}

public enum ProxyScheme: String, Codable, CaseIterable, Sendable {
    case http, https, socks5, socks5h

    public var curlValue: Int32 {
        switch self {
        case .http: return 1
        case .https: return 2
        case .socks5: return 3
        case .socks5h: return 4
        }
    }
}

public struct ProxyConfiguration: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var scheme: ProxyScheme
    public var host: String
    public var port: Int

    public init(isEnabled: Bool = false, scheme: ProxyScheme = .http, host: String = "", port: Int = 7890) {
        self.isEnabled = isEnabled
        self.scheme = scheme
        self.host = host
        self.port = port
    }

    public func validated() throws -> ProxyConfiguration {
        guard !isEnabled || !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProxyValidationError.emptyHost
        }
        guard !isEnabled || (1...65_535).contains(port) else {
            throw ProxyValidationError.invalidPort
        }
        var copy = self
        copy.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        return copy
    }

    public func applyingHostSemantics() throws -> ProxyConfiguration {
        var copy = self
        copy.isEnabled = !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return try copy.validated()
    }
}

public enum ProxyValidationError: LocalizedError, Equatable {
    case emptyHost
    case invalidPort

    public var errorDescription: String? {
        switch self {
        case .emptyHost: return "代理主机不能为空"
        case .invalidPort: return "代理端口必须在 1 到 65535 之间"
        }
    }
}
