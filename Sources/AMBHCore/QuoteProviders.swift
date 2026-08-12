import CoreFoundation
import Foundation

public enum QuoteProviderError: LocalizedError, Equatable, Sendable {
    case invalidResponse(String)
    case noQuotes

    public var errorDescription: String? {
        switch self {
        case .invalidResponse(let detail): return "行情响应无效：\(detail)"
        case .noQuotes: return "行情源未返回有效数据"
        }
    }
}

public protocol QuoteProvider: Sendable {
    var source: QuoteSource { get }
    func fetch(symbols: [SecuritySymbol], proxy: ProxyConfiguration) async throws -> [SecuritySymbol: Quote]
}

public struct TencentQuoteProvider: QuoteProvider {
    public let source = QuoteSource.tencent
    private let transport: NetworkTransport

    public init(transport: NetworkTransport = CurlTransport()) {
        self.transport = transport
    }

    public func fetch(symbols: [SecuritySymbol], proxy: ProxyConfiguration) async throws -> [SecuritySymbol: Quote] {
        guard !symbols.isEmpty else { return [:] }
        let codes = symbols.map(\.providerCode).joined(separator: ",")
        guard let url = URL(string: "https://qt.gtimg.cn/q=\(codes)") else {
            throw QuoteProviderError.invalidResponse("无法构造腾讯行情地址")
        }
        let response = try await transport.get(url: url, referer: "https://gu.qq.com/", proxy: proxy)
        return try Self.parse(data: response.data, expected: symbols)
    }

    public static func parse(data: Data, expected: [SecuritySymbol]) throws -> [SecuritySymbol: Quote] {
        let text = try decodeGB18030(data)
        var quotes: [SecuritySymbol: Quote] = [:]
        let expectedByID = Dictionary(uniqueKeysWithValues: expected.map { ($0.id, $0) })
        for statement in text.split(separator: ";") {
            guard let equals = statement.firstIndex(of: "=") else { continue }
            let variable = statement[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            guard variable.hasPrefix("v_") else { continue }
            let id = String(variable.dropFirst(2))
            guard let symbol = expectedByID[id] else { continue }
            let payload = statement[statement.index(after: equals)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"\r\n "))
            let fields = payload.split(separator: "~", omittingEmptySubsequences: false).map(String.init)
            guard fields.count > 32,
                  !fields[1].isEmpty,
                  let price = finiteDouble(fields[3]),
                  let previousClose = finiteDouble(fields[4]),
                  let change = finiteDouble(fields[31]),
                  let percent = finiteDouble(fields[32]) else { continue }
            let timestamp = parseTencentDate(fields.count > 30 ? fields[30] : "") ?? Date()
            quotes[symbol] = Quote(symbol: symbol, name: fields[1], price: price, previousClose: previousClose, change: change, changePercent: percent, timestamp: timestamp, source: .tencent)
        }
        guard !quotes.isEmpty else { throw QuoteProviderError.noQuotes }
        return quotes
    }
}

public struct SinaQuoteProvider: QuoteProvider {
    public let source = QuoteSource.sina
    private let transport: NetworkTransport

    public init(transport: NetworkTransport = CurlTransport()) {
        self.transport = transport
    }

    public func fetch(symbols: [SecuritySymbol], proxy: ProxyConfiguration) async throws -> [SecuritySymbol: Quote] {
        guard !symbols.isEmpty else { return [:] }
        let codes = symbols.map(\.providerCode).joined(separator: ",")
        guard let url = URL(string: "https://hq.sinajs.cn/list=\(codes)") else {
            throw QuoteProviderError.invalidResponse("无法构造新浪行情地址")
        }
        let response = try await transport.get(url: url, referer: "https://finance.sina.com.cn/", proxy: proxy)
        return try Self.parse(data: response.data, expected: symbols)
    }

    public static func parse(data: Data, expected: [SecuritySymbol]) throws -> [SecuritySymbol: Quote] {
        let text = try decodeGB18030(data)
        var quotes: [SecuritySymbol: Quote] = [:]
        let expectedByID = Dictionary(uniqueKeysWithValues: expected.map { ($0.id, $0) })
        for statement in text.split(separator: ";") {
            guard let marker = statement.range(of: "hq_str_")?.upperBound,
                  let equals = statement[marker...].firstIndex(of: "=") else { continue }
            let id = String(statement[marker..<equals])
            guard let symbol = expectedByID[id] else { continue }
            let payload = statement[statement.index(after: equals)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"\r\n "))
            let fields = payload.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count > 31,
                  !fields[0].isEmpty,
                  let previousClose = finiteDouble(fields[2]),
                  let price = finiteDouble(fields[3]),
                  previousClose != 0 else { continue }
            let change = price - previousClose
            let percent = change / previousClose * 100
            let timestamp = parseSinaDate(date: fields[30], time: fields[31]) ?? Date()
            quotes[symbol] = Quote(symbol: symbol, name: fields[0], price: price, previousClose: previousClose, change: change, changePercent: percent, timestamp: timestamp, source: .sina)
        }
        guard !quotes.isEmpty else { throw QuoteProviderError.noQuotes }
        return quotes
    }
}

private func decodeGB18030(_ data: Data) throws -> String {
    let encoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
    let raw = CFStringConvertEncodingToNSStringEncoding(encoding)
    guard let text = String(data: data, encoding: String.Encoding(rawValue: raw)) else {
        throw QuoteProviderError.invalidResponse("无法解码 GB18030 数据")
    }
    return text
}

private func finiteDouble(_ value: String) -> Double? {
    guard let result = Double(value), result.isFinite else { return nil }
    return result
}

private let chinaTimeZone = TimeZone(identifier: "Asia/Shanghai")!

private func parseTencentDate(_ value: String) -> Date? {
    guard value.count >= 14 else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = chinaTimeZone
    formatter.dateFormat = "yyyyMMddHHmmss"
    return formatter.date(from: String(value.prefix(14)))
}

private func parseSinaDate(date: String, time: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = chinaTimeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: "\(date) \(time)")
}
