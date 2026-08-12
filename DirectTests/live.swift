import AMBHCore
import Foundation

@main
struct LiveSmokeTest {
    static func main() async throws {
        let symbols = [
            try SecuritySymbol(exchange: .shanghai, code: "000001"),
            try SecuritySymbol(exchange: .shenzhen, code: "399001")
        ]
        let proxy = ProxyConfiguration()
        let providers: [any QuoteProvider] = [TencentQuoteProvider(), SinaQuoteProvider()]
        for provider in providers {
            let quotes = try await provider.fetch(symbols: symbols, proxy: proxy)
            guard quotes.count == symbols.count else {
                throw QuoteProviderError.invalidResponse("\(provider.source.displayName) 返回数量不完整")
            }
            let summary = symbols.compactMap { quotes[$0] }.map {
                "\($0.name) \(String(format: "%.2f", $0.price))"
            }.joined(separator: ", ")
            print("\(provider.source.displayName): \(summary)")
        }
        let points = try await TencentIntradayProvider().fetch(symbol: symbols[0], proxy: proxy)
        guard let first = points.first, let last = points.last else {
            throw QuoteProviderError.noQuotes
        }
        print("腾讯分时: \(points.count) 点，\(first.minute) - \(last.minute)")
    }
}
