import CoreFoundation
import XCTest
@testable import AMBHCore

final class AMBHCoreTests: XCTestCase {
    func testSymbolParsingAndDefaults() throws {
        XCTAssertEqual(try SecuritySymbol.parse("600519").id, "sh600519")
        XCTAssertEqual(try SecuritySymbol.parse("000001").id, "sz000001")
        XCTAssertEqual(try SecuritySymbol.parse("sh000001").id, "sh000001")
        XCTAssertThrowsError(try SecuritySymbol.parse("123"))
        XCTAssertEqual(PersistedState.initial().watchlist.map(\.symbol.id), ["sh000001", "sz399001"])
    }

    func testProxyValidationAndCurlMapping() throws {
        XCTAssertEqual(ProxyScheme.http.curlValue, 1)
        XCTAssertEqual(ProxyScheme.https.curlValue, 2)
        XCTAssertEqual(ProxyScheme.socks5.curlValue, 3)
        XCTAssertEqual(ProxyScheme.socks5h.curlValue, 4)
        XCTAssertThrowsError(try ProxyConfiguration(isEnabled: true, host: "", port: 7890).validated())
        XCTAssertThrowsError(try ProxyConfiguration(isEnabled: true, host: "localhost", port: 0).validated())
        XCTAssertNoThrow(try ProxyConfiguration(isEnabled: false, host: "", port: 0).validated())
        XCTAssertFalse(try ProxyConfiguration(isEnabled: true, host: "  ", port: 7890).applyingHostSemantics().isEnabled)
        XCTAssertTrue(try ProxyConfiguration(isEnabled: false, scheme: .socks5h, host: "127.0.0.1", port: 7890).applyingHostSemantics().isEnabled)
    }

    func testTencentParser() throws {
        let symbol = try SecuritySymbol.parse("600519")
        let payload = "v_sh600519=\"1~贵州茅台~600519~1344.07~1346.50~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~20260812101815~-2.43~-0.18~\";"
        let quote = try TencentQuoteProvider.parse(data: gbData(payload), expected: [symbol])[symbol]
        XCTAssertEqual(quote?.name, "贵州茅台")
        XCTAssertEqual(quote?.price, 1344.07)
        XCTAssertEqual(quote?.changePercent, -0.18)
    }

    func testSinaParser() throws {
        let symbol = try SecuritySymbol.parse("000001")
        let payload = "var hq_str_sz000001=\"平安银行,11.260,11.260,11.220,11.290,11.200,11.220,11.230,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2026-08-12,10:18:15,00\";"
        let quote = try XCTUnwrap(SinaQuoteProvider.parse(data: gbData(payload), expected: [symbol])[symbol])
        XCTAssertEqual(quote.name, "平安银行")
        XCTAssertEqual(quote.price, 11.22)
        XCTAssertEqual(quote.change, -0.04, accuracy: 0.0001)
    }

    func testMalformedResponses() throws {
        let symbol = try SecuritySymbol.parse("600519")
        XCTAssertThrowsError(try TencentQuoteProvider.parse(data: Data("bad".utf8), expected: [symbol]))
        XCTAssertThrowsError(try SinaQuoteProvider.parse(data: Data("bad".utf8), expected: [symbol]))
    }

    func testIntradayParser() throws {
        let symbol = try SecuritySymbol.parse("sh000001")
        let json = #"{"data":{"sh000001":{"data":{"data":["0930 3933.55 1 2.0","0931 3929.55 2 3.0"]}}}}"#
        let points = try TencentIntradayProvider.parse(data: Data(json.utf8), symbol: symbol)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].minute, "09:30")
        XCTAssertEqual(points[1].price, 3929.55)
    }

    func testChinaTradingSessionAxis() {
        XCTAssertEqual(ChinaTradingSession.minuteOffset(for: "09:30"), 0)
        XCTAssertEqual(ChinaTradingSession.minuteOffset(for: "11:30"), 120)
        XCTAssertEqual(ChinaTradingSession.minuteOffset(for: "13:00"), 120)
        XCTAssertEqual(ChinaTradingSession.minuteOffset(for: "15:00"), 240)
        XCTAssertEqual(ChinaTradingSession.tradingDuration, 240)
        XCTAssertNil(ChinaTradingSession.minuteOffset(for: "12:00"))
        XCTAssertNil(ChinaTradingSession.minuteOffset(for: "09:29"))
    }

    func testWatchlistAliasRoundTrip() throws {
        let symbol = try SecuritySymbol.parse("sh000001")
        let item = WatchlistItem(symbol: symbol, displayName: "上证指数", alias: "上证")
        let data = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(WatchlistItem.self, from: data).alias, "上证")
        XCTAssertEqual(item.preferredName(quoteName: "上证指数"), "上证")
    }

    func testRefreshIntervalsAndLegacyDefaults() throws {
        XCTAssertEqual(PriceRefreshInterval.fifteenSeconds.seconds, 15)
        XCTAssertEqual(ChartRefreshInterval.tenMinutes.seconds, 600)
        let initial = PersistedState.initial()
        XCTAssertEqual(initial.priceRefreshInterval, .sixtySeconds)
        XCTAssertEqual(initial.chartRefreshInterval, .fiveMinutes)

        let legacy = #"{"watchlist":[],"preferredSource":"tencent","proxy":{"isEnabled":false,"scheme":"http","host":"","port":7890},"cachedQuotes":[]}"#
        let decoded = try JSONDecoder().decode(PersistedState.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.priceRefreshInterval, .sixtySeconds)
        XCTAssertEqual(decoded.chartRefreshInterval, .fiveMinutes)
        XCTAssertTrue(decoded.cachedIntradaySeries.isEmpty)
    }

    func testIntradayCacheRoundTrip() throws {
        let symbol = try SecuritySymbol.parse("sz300475")
        let cache = CachedIntradaySeries(
            symbol: symbol,
            points: [IntradayPoint(minute: "09:30", price: 160.01, sequence: 0)],
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        let decoded = try JSONDecoder().decode(CachedIntradaySeries.self, from: JSONEncoder().encode(cache))
        XCTAssertEqual(decoded, cache)
    }

    func testMarketSchedule() throws {
        let schedule = MarketSchedule()
        XCTAssertTrue(schedule.isTradingTime(chinaDate("2026-08-12 10:00:00")))
        XCTAssertFalse(schedule.isTradingTime(chinaDate("2026-08-12 12:00:00")))
        XCTAssertTrue(schedule.isTradingTime(chinaDate("2026-08-12 14:00:00")))
        XCTAssertFalse(schedule.isTradingTime(chinaDate("2026-08-15 10:00:00")))
    }

    func testFailoverAfterTwoProviderFailures() async throws {
        let symbol = try SecuritySymbol.parse("600519")
        let primary = MockProvider(source: .tencent, results: [.failure(QuoteProviderError.noQuotes), .failure(QuoteProviderError.noQuotes)])
        let fallbackQuote = Quote(symbol: symbol, name: "贵州茅台", price: 1, previousClose: 1, change: 0, changePercent: 0, timestamp: Date(), source: .sina)
        let fallback = MockProvider(source: .sina, results: [.success([symbol: fallbackQuote])])
        let service = QuoteService(providers: [primary, fallback])
        do {
            _ = try await service.fetch(symbols: [symbol], preferred: .tencent, proxy: ProxyConfiguration())
            XCTFail("First provider failure should be surfaced")
        } catch {}
        let result = try await service.fetch(symbols: [symbol], preferred: .tencent, proxy: ProxyConfiguration())
        XCTAssertEqual(result.actualSource, .sina)
        XCTAssertTrue(result.isUsingFallback)
    }

    func testTransportFailureDoesNotTriggerFallback() async throws {
        let symbol = try SecuritySymbol.parse("600519")
        let primary = MockProvider(source: .tencent, results: [.failure(TransportError.proxy("offline")), .failure(TransportError.proxy("offline"))])
        let fallback = MockProvider(source: .sina, results: [])
        let service = QuoteService(providers: [primary, fallback])
        for _ in 0..<2 {
            do {
                _ = try await service.fetch(
                    symbols: [symbol],
                    preferred: .tencent,
                    proxy: ProxyConfiguration(isEnabled: true, host: "127.0.0.1", port: 7890)
                )
                XCTFail("Transport failure should be surfaced")
            } catch let error as TransportError {
                XCTAssertTrue(error.isProxyFailure)
            }
        }
        let fallbackCalls = await fallback.callCount
        XCTAssertEqual(fallbackCalls, 0)
    }
}

private actor MockProvider: QuoteProvider {
    nonisolated let source: QuoteSource
    private var results: [Result<[SecuritySymbol: Quote], Error>]
    private(set) var callCount = 0

    init(source: QuoteSource, results: [Result<[SecuritySymbol: Quote], Error>]) {
        self.source = source
        self.results = results
    }

    func fetch(symbols: [SecuritySymbol], proxy: ProxyConfiguration) async throws -> [SecuritySymbol: Quote] {
        callCount += 1
        guard !results.isEmpty else { throw QuoteProviderError.noQuotes }
        return try results.removeFirst().get()
    }
}

private func gbData(_ string: String) -> Data {
    let encoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    return string.data(using: String.Encoding(rawValue: encoding))!
}

private func chinaDate(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.date(from: value)!
}
