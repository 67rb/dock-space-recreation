import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
    print("PASS: " + message)
}
@MainActor func runChecks() {
    let suite = "app.personal.docklet.checks." + UUID().uuidString
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    var now = Date(timeIntervalSince1970: 1_700_000_000)
    let timer = TimerStore(preferences: preferences, now: { now }, automaticTicker: false)
    timer.choosePreset(minutes: 1, name: "Focus"); timer.startOrResume()
    now += 20; timer.refreshFromClock()
    check(timer.remaining == 40, "Countdown uses a deadline rather than tick counts")
    timer.addMinute(); now += 30; timer.refreshFromClock()
    check(timer.remaining == 70, "Adding a minute moves the running deadline")
    timer.pause(); now += 100
    let resumed = TimerStore(preferences: preferences, now: { now }, automaticTicker: false)
    check(resumed.remaining == 70 && !resumed.isRunning, "Paused countdown persists without consuming time")
    resumed.startOrResume(); now += 80
    let completed = TimerStore(preferences: preferences, now: { now }, automaticTicker: false)
    check(completed.isComplete && completed.completedFocusSessions == 1, "An expired focus session is counted once after restart")
    let again = TimerStore(preferences: preferences, now: { now }, automaticTicker: false)
    check(again.completedFocusSessions == 1, "Reloading a completed timer does not count it twice")
    again.selectMode(.stopwatch); again.startOrResume(); now += 12; again.recordLap(); again.pause(); now += 40
    again.startOrResume(); now += 8; again.recordLap(); again.pause()
    check(again.laps.count == 2 && again.laps[1].split == 8 && again.elapsed == 20, "Stopwatch lap splits exclude paused time")
    let restored = TimerStore(preferences: preferences, now: { now }, automaticTicker: false)
    check(restored.laps.count == 2 && restored.elapsed == 20, "Laps and elapsed time survive a restart")
    restored.reset(); check(restored.laps.isEmpty && restored.elapsed == 0, "Stopwatch reset clears lap history")
    let stocks = StockStore(preferences: preferences, networking: false)
    let searchData = Data("\u{5B}{\"symbol\":\"BTC-USD\",\"shortname\":\"Bitcoin USD\",\"exchDisp\":\"CCC\",\"quoteType\":\"CRYPTOCURRENCY\"}\u{5D}".utf8)
    let result = try! JSONDecoder().decode([StockSearchResult].self, from: searchData)[0]
    check(result.name == "Bitcoin USD" && result.isMarketAsset && StockStore.validSymbol(result.symbol) == result.symbol, "Company search resolves Bitcoin to its USD market symbol")
    check(StockRange.allCases.map(\.rawValue) == ["1D", "1W", "1M", "1Y"], "Stocks offers daily, weekly, monthly and yearly charts")
    stocks.symbolDraft = " msft "; stocks.applySymbol()
    check(stocks.symbol == "MSFT" && stocks.watchlist == ["AAPL", "MSFT"], "Adding a ticker normalizes it and preserves the watchlist")
    stocks.symbolDraft = "bad/ticker"; stocks.applySymbol()
    check(stocks.symbol == "MSFT" && stocks.watchlist.count == 2, "Invalid ticker input leaves the current selection intact")
    stocks.remove("MSFT")
    check(stocks.symbol == "AAPL", "Removing the selected ticker selects a remaining entry")
    stocks.remove("AAPL"); check(stocks.watchlist == ["AAPL"], "The last watchlist entry cannot be removed")
    stocks.symbolDraft = "NVDA"; stocks.applySymbol()
    stocks.selectRange(.year)
    let savedStocks = StockStore(preferences: preferences, networking: false)
    check(savedStocks.watchlist == ["AAPL", "NVDA"] && savedStocks.symbol == "NVDA", "Watchlist and selected symbol survive a restart")
    check(savedStocks.range == .year, "Selected stock chart range survives a restart")
    let profiles = LayoutProfiles(preferences: preferences)
    let items: [WidgetPlacement] = [.init(kind: .stocks, slots: 3), .init(kind: .notes, slots: 2)]
    profiles.save(name: " Work ", widgets: items)
    profiles.save(name: "work", widgets: [.init(kind: .weather, slots: 2)])
    check(profiles.profiles.count == 1 && profiles.profiles[0].widgets[0].kind == .weather, "Saving the same layout name updates it instead of duplicating it")
    let profile = profiles.profiles[0]; profiles.remove(profile); profiles.undoRemove()
    let loaded = LayoutProfiles(preferences: preferences)
    check(loaded.profiles == profiles.profiles && loaded.profiles.count == 1, "Deleted layouts can be restored and persist")
    check(LayoutProfiles.normalized([.init(kind: .notes, slots: 2), .init(kind: .notes, slots: 3), .init(kind: .timer, slots: 9)]).count == 1, "Invalid and duplicate widget placements are rejected")
    let weather = WeatherStore(preferences: preferences, networking: false)
    check(weather.temperatureString(-5) == "-5°", "Celsius retains negative temperatures")
    weather.fahrenheit = true
    check(weather.temperatureString(0) == "32°" && weather.temperatureString(100) == "212°", "Temperature conversion is correct")
    check(WeatherStore(preferences: preferences, networking: false).fahrenheit, "Temperature units persist")
    for pitch in [16.0, 24, 32, 64, 128] {
        let raw = CGRect(x: 100, y: 10, width: pitch * 3, height: pitch + 12)
        let fitted = DockGeometry.iconRowRect(raw, slotLength: pitch, orientation: "bottom")
        check(raw.contains(fitted) && fitted.height < pitch, "Compact tile stays inside its reserved area at pitch \(pitch)")
    }
}
MainActor.assumeIsolated { runChecks() }
print("Feature checks finished. Only an isolated temporary preference suite was used.")
