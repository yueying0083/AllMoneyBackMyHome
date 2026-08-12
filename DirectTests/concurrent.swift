import AMBHCore
import Foundation

@main
struct ConcurrentSmokeTest {
    static func main() async throws {
        let symbol = try SecuritySymbol.parse("sz300475")
        let proxy = ProxyConfiguration()
        async let quote = TencentQuoteProvider().fetch(symbols: [symbol], proxy: proxy)
        async let chart = TencentIntradayProvider().fetch(symbol: symbol, proxy: proxy)
        let (quotes, points) = try await (quote, chart)
        print("Concurrent transport: \(quotes.count) quote, \(points.count) chart points")
    }
}
