import Foundation

public struct TencentIntradayProvider: Sendable {
    private let transport: NetworkTransport

    public init(transport: NetworkTransport = CurlTransport()) {
        self.transport = transport
    }

    public func fetch(symbol: SecuritySymbol, proxy: ProxyConfiguration) async throws -> [IntradayPoint] {
        guard let url = URL(string: "https://web.ifzq.gtimg.cn/appstock/app/minute/query?code=\(symbol.providerCode)") else {
            throw QuoteProviderError.invalidResponse("无法构造分时行情地址")
        }
        let response = try await transport.get(url: url, referer: "https://gu.qq.com/", proxy: proxy)
        return try Self.parse(data: response.data, symbol: symbol)
    }

    public static func parse(data: Data, symbol: SecuritySymbol) throws -> [IntradayPoint] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataNode = root["data"] as? [String: Any],
              let symbolNode = dataNode[symbol.providerCode] as? [String: Any],
              let nestedData = symbolNode["data"] as? [String: Any],
              let rows = nestedData["data"] as? [String] else {
            throw QuoteProviderError.invalidResponse("分时数据结构不完整")
        }

        let points = rows.enumerated().compactMap { index, row -> IntradayPoint? in
            let fields = row.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 2,
                  fields[0].count == 4,
                  let price = Double(fields[1]),
                  price.isFinite else { return nil }
            let rawMinute = String(fields[0])
            let minute = "\(rawMinute.prefix(2)):\(rawMinute.suffix(2))"
            return IntradayPoint(minute: minute, price: price, sequence: index)
        }
        guard !points.isEmpty else { throw QuoteProviderError.noQuotes }
        return points
    }
}
