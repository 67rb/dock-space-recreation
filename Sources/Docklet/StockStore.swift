import Combine
import Foundation

struct StockChartPoint: Codable, Identifiable {
    let timestamp: Int
    let price: Double

    var id: Int { timestamp }
}

struct StockQuote: Codable {
    let symbol: String
    let currency: String
    let price: Double
    let previousClose: Double
    let points: [StockChartPoint]
    let fetchedAt: Date

    var change: Double { price - previousClose }
    var changePercent: Double {
        guard previousClose != 0 else { return 0 }
        return change / previousClose * 100
    }

    var isPositive: Bool { change >= 0 }

    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)
    }

    var formattedTilePrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = price >= 1_000 ? 0 : 2
        formatter.maximumFractionDigits = price >= 1_000 ? 0 : 2
        return formatter.string(from: NSNumber(value: price)) ?? String(format: "%.2f", price)
    }

    var formattedChange: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: NSNumber(value: abs(change))) ?? String(format: "%.2f", abs(change))
        let percent = String(format: "%.2f", abs(changePercent))
        return "\(isPositive ? "+" : "−")\(value) (\(isPositive ? "+" : "−")\(percent)%)"
    }

    var updateDescription: String {
        "Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))"
    }
}

struct StockSearchResult: Decodable, Identifiable, Hashable {
    let symbol: String
    let shortname: String?
    let longname: String?
    let exchDisp: String?
    let quoteType: String?
    var id: String { symbol }
    var name: String { shortname ?? longname ?? symbol }
    private enum CodingKeys: String, CodingKey { case symbol, shortname, longname, exchDisp, quoteType }
    var isMarketAsset: Bool { ["EQUITY", "ETF", "MUTUALFUND", "CRYPTOCURRENCY", "INDEX", "FUTURE"].contains(quoteType ?? "") }
}

enum StockRange: String, CaseIterable, Codable, Identifiable {
    case day = "1D", week = "1W", month = "1M", year = "1Y"
    var id: String { rawValue }
    var query: String {
        switch self { case .day: return "range=1d&interval=5m"; case .week: return "range=5d&interval=30m"; case .month: return "range=1mo&interval=1d"; case .year: return "range=1y&interval=1wk" }
    }
}

@MainActor
final class StockStore: ObservableObject {
    @Published private(set) var symbol: String
    @Published var symbolDraft: String
    @Published private(set) var quote: StockQuote?
    @Published private(set) var watchlist: [String]
    @Published private(set) var quotes: [String: StockQuote]
    @Published private(set) var range: StockRange = .day
    @Published private(set) var chartPoints: [StockChartPoint] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isChartRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var chartError: String?
    @Published private(set) var searchResults: [StockSearchResult] = []
    @Published private(set) var isSearching = false
    private let preferences: UserDefaults
    private let networking: Bool
    private var refreshTask: Task<Void, Never>?
    private var chartTask: Task<Void, Never>?
    private var chartCache: [String: [StockChartPoint]] = [:]
    private let symbolKey = "docklet.stocks.symbol.v1"
    private let quoteKey = "docklet.stocks.quote.v1"
    private let watchlistKey = "docklet.stocks.watchlist.v1"
    private let quotesKey = "docklet.stocks.quotes.v2"
    private let rangeKey = "docklet.stocks.range.v1"

    init(preferences: UserDefaults = DockletPreferences.shared, networking: Bool = true) {
        self.preferences = preferences; self.networking = networking
        let saved = preferences.string(forKey: symbolKey) ?? "AAPL"
        symbol = saved; symbolDraft = saved
        var symbols = preferences.stringArray(forKey: watchlistKey) ?? [saved]
        if !symbols.contains(saved) { symbols.insert(saved, at: 0) }
        watchlist = Array(NSOrderedSet(array: symbols).array as? [String] ?? [saved])
        quotes = preferences.data(forKey: quotesKey).flatMap { try? JSONDecoder().decode([String: StockQuote].self, from: $0) } ?? [:]
        if let data = preferences.data(forKey: quoteKey), let legacy = try? JSONDecoder().decode(StockQuote.self, from: data) { quotes[saved] = legacy }
        quote = quotes[saved]; chartPoints = quote?.points ?? []
        range = StockRange(rawValue: preferences.string(forKey: rangeKey) ?? "1D") ?? .day
        if range != .day && networking { Task { self.loadChart() } }
        if networking {
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }
    deinit { refreshTask?.cancel(); chartTask?.cancel() }
    static func validSymbol(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-^=")
        return !value.isEmpty && value.count <= 15 && value.unicodeScalars.allSatisfy { allowed.contains($0) } ? value : nil
    }
    func applySymbol() {
        guard let candidate = Self.validSymbol(symbolDraft) else { errorMessage = "Enter a ticker such as AAPL, MSFT or BRK-B."; return }
        guard watchlist.contains(candidate) || watchlist.count < 12 else { errorMessage = "Your watchlist holds 12 symbols. Remove one to add another."; return }
        if !watchlist.contains(candidate) { watchlist.append(candidate); saveWatchlist() }
        select(candidate)
    }
    func select(_ value: String) {
        guard watchlist.contains(value) else { return }
        symbol = value; symbolDraft = value; quote = quotes[value]; errorMessage = nil
        preferences.set(value, forKey: symbolKey)
        if let quote, let data = try? JSONEncoder().encode(quote) { preferences.set(data, forKey: quoteKey) }
        else { preferences.removeObject(forKey: quoteKey) }
        loadChart()
        if networking { Task { await refresh() } }
    }
    func remove(_ value: String) {
        guard watchlist.count > 1 else { return }
        watchlist.removeAll { $0 == value }; saveWatchlist()
        if symbol == value { select(watchlist[0]) }
    }
    func nextSymbol() {
        guard let index = watchlist.firstIndex(of: symbol), !watchlist.isEmpty else { return }
        select(watchlist[(index + 1) % watchlist.count])
    }
    func selectRange(_ value: StockRange) {
        range = value; preferences.set(value.rawValue, forKey: rangeKey); loadChart()
    }
    func searchCompanies() async {
        let query = symbolDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard networking, query.count >= 2 else { errorMessage = "Type at least two letters to search."; return }
        isSearching = true; searchResults = []; errorMessage = nil
        defer { isSearching = false }
        var lastError: Error = StockDataError.unavailable
        for host in ["query1.finance.yahoo.com", "query2.finance.yahoo.com"] {
            var components = URLComponents(); components.scheme = "https"; components.host = host
            components.path = "/v1/finance/search"
            components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "quotesCount", value: "12"), URLQueryItem(name: "newsCount", value: "0")]
            guard let url = components.url else { continue }
            do {
                var request = URLRequest(url: url); request.timeoutInterval = 15
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw StockDataError.unavailable }
                let payload = try JSONDecoder().decode(YahooSearchResponse.self, from: data)
                guard symbolDraft.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
                searchResults = Array(payload.quotes.filter { $0.isMarketAsset && Self.validSymbol($0.symbol) != nil }.prefix(8))
                if searchResults.isEmpty { errorMessage = "No matching stocks or market symbols found." }
                return
            } catch { lastError = error }
        }
        errorMessage = lastError is StockDataError ? "Company search is unavailable. You can still add a ticker directly." : "Company search failed. Check your connection and try again."
    }
    func selectSearchResult(_ result: StockSearchResult) {
        symbolDraft = result.symbol; searchResults = []; applySymbol()
    }
    private func saveWatchlist() { preferences.set(watchlist, forKey: watchlistKey) }
    private func saveQuotes() {
        if let data = try? JSONEncoder().encode(quotes) { preferences.set(data, forKey: quotesKey) }
        if let quote, let data = try? JSONEncoder().encode(quote) { preferences.set(data, forKey: quoteKey) }
    }
    func refresh() async {
        guard networking, !isRefreshing else { return }
        let requested = symbol
        isRefreshing = true
        defer {
            isRefreshing = false
            if requested != symbol { Task { await refresh() } }
        }
        do {
            let result = try await fetchQuote(for: requested)
            quotes[requested] = result
            if symbol == requested {
                quote = result; errorMessage = nil
                if range == .day { chartPoints = result.points } else { loadChart() }
            }
            saveQuotes()
        } catch {
            if symbol == requested { errorMessage = "Could not refresh \(requested). Any saved quote is shown below." }
        }
    }
    func refreshWatchlist() async {
        guard networking else { return }
        for value in watchlist where value != symbol {
            guard !Task.isCancelled else { return }
            if let saved = quotes[value], Date().timeIntervalSince(saved.fetchedAt) < 60 { continue }
            if let result = try? await fetchQuote(for: value), watchlist.contains(value) { quotes[value] = result }
        }
        saveQuotes()
    }
    private func loadChart() {
        chartTask?.cancel(); chartError = nil; isChartRefreshing = false
        if range == .day { chartPoints = quote?.points ?? []; return }
        let requestedSymbol = symbol, requestedRange = range
        let key = requestedSymbol + requestedRange.rawValue
        chartPoints = chartCache[key] ?? []
        guard networking else { return }
        isChartRefreshing = true
        chartTask = Task { [weak self] in
            guard let self else { return }
            do {
                let series = try await fetchChart(for: requestedSymbol, range: requestedRange)
                guard !Task.isCancelled, symbol == requestedSymbol, range == requestedRange else { return }
                chartPoints = Self.points(series); chartCache[key] = chartPoints
            } catch {
                guard !Task.isCancelled, symbol == requestedSymbol, range == requestedRange else { return }
                chartError = "This chart could not be loaded. Try another range."
            }
            isChartRefreshing = false
        }
    }
    private static func points(_ series: YahooChartSeries) -> [StockChartPoint] {
        zip(series.timestamps ?? [], series.closePrices).compactMap { timestamp, value in
            guard let value, value.isFinite, value > 0 else { return nil }
            return StockChartPoint(timestamp: timestamp, price: value)
        }
    }
    private func fetchQuote(for symbol: String) async throws -> StockQuote {
        let series = try await fetchChart(for: symbol, range: .day)
        let price = series.meta.regularMarketPrice ?? series.closePrices.compactMap { $0 }.last ?? 0
        let previous = series.meta.chartPreviousClose ?? series.meta.previousClose ?? price
        guard price.isFinite, price > 0, previous.isFinite, previous > 0 else { throw StockDataError.invalidQuote }
        return StockQuote(symbol: symbol, currency: series.meta.currency ?? "USD", price: price, previousClose: previous, points: Self.points(series), fetchedAt: Date())
    }
    private func fetchChart(for symbol: String, range: StockRange) async throws -> YahooChartSeries {
        var lastError: Error = StockDataError.unavailable
        for host in ["query1.finance.yahoo.com", "query2.finance.yahoo.com"] {
            guard let escaped = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let url = URL(string: "https://\(host)/v8/finance/chart/\(escaped)?\(range.query)&includePrePost=false") else { throw StockDataError.invalidQuote }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw StockDataError.unavailable }
                let body = try JSONDecoder().decode(YahooChartResponse.self, from: data)
                guard let series = body.chart.result?.first else { throw StockDataError.unavailable }
                return series
            } catch { lastError = error }
        }
        throw lastError
    }
}

private struct YahooSearchResponse: Decodable { let quotes: [StockSearchResult] }

private enum StockDataError: Error {
    case unavailable
    case invalidQuote
}

private struct YahooChartResponse: Decodable {
    let chart: YahooChartContainer
}

private struct YahooChartContainer: Decodable {
    let result: [YahooChartSeries]?
}

private struct YahooChartSeries: Decodable {
    let meta: YahooChartMeta
    let timestamps: [Int]?
    let indicators: YahooIndicators

    var closePrices: [Double?] {
        indicators.quote?.first?.close ?? []
    }

    enum CodingKeys: String, CodingKey {
        case meta
        case timestamps = "timestamp"
        case indicators
    }
}

private struct YahooChartMeta: Decodable {
    let symbol: String?
    let currency: String?
    let regularMarketPrice: Double?
    let chartPreviousClose: Double?
    let previousClose: Double?
}

private struct YahooIndicators: Decodable {
    let quote: [YahooQuoteData]?
}

private struct YahooQuoteData: Decodable {
    let close: [Double?]?
}
