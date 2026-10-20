import SwiftUI

struct DockIntegratedTile: View {
    let kind: DockWidget
    @ObservedObject var timer: TimerStore
    @ObservedObject var stocks: StockStore
    @ObservedObject var weather: WeatherStore
    @ObservedObject var music: MusicStore
    @ObservedObject var agenda: CalendarAccessStore
    let onOpen: () -> Void
    var onResize: ((Int) -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    @AppStorage("docklet.notes.text.v1") private var noteText = ""
    @AppStorage("docklet.native.largeText") private var largeText = false
    @AppStorage("docklet.widget.cornerRadius") private var cornerRadius = 18.0
    private var textScale: CGFloat { largeText ? 1.2 : 1 }

    var body: some View {
        GeometryReader { geometry in
            let dense = geometry.size.height < 60
            let densityScale = min(1.6, max(0.55, geometry.size.height / 28))
            let wide = geometry.size.width > (dense ? 66 * densityScale : 135)
            let radius = dense ? min(cornerRadius, geometry.size.height * 0.22) : cornerRadius
            Group {
                if dense { denseDockCard(wide: wide, scale: densityScale, availableWidth: geometry.size.width) }
                else { switch kind {
                case .music: musicCard(wide: wide)
                case .timer: timerCard(wide: wide)
                case .stocks: stocksCard(wide: wide)
                case .weather: weatherCard(wide: wide)
                case .calendar: calendarCard
                case .reminders: reminderCard
                case .clock: clockCard
                case .notes: notesCard(wide: wide, scale: 1.5)
                } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(kind == .music && (!dense || music.hasTrack) ? Color(red: 0.76, green: 0.025, blue: 0.065) : Color(red: 0.055, green: 0.065, blue: 0.075), in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(dense ? 0.055 : 0.12), lineWidth: dense ? 0.4 : 0.8))
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .foregroundStyle(.white)
            .contextMenu {
                Button("Open \(kind.title)", action: onOpen)
                if kind == .timer {
                    Button(timer.isRunning ? "Pause" : "Start / Resume") { timer.isRunning ? timer.pause() : timer.startOrResume() }
                    if timer.mode == .timer { Button("Add 1 minute", action: timer.addMinute) }
                    else { Button("Record lap", action: timer.recordLap).disabled(!timer.isRunning) }
                    Button("Reset", action: timer.reset)
                }
                if kind == .stocks {
                    Menu("Show ticker") { ForEach(stocks.watchlist, id: \.self) { symbol in Button(symbol) { stocks.select(symbol) } } }
                    Button("Refresh quote") { Task { await stocks.refresh() } }
                }
                if let onResize {
                    Divider()
                    Menu("Width") {
                        Button("Compact") { onResize(1) }; Button("Medium") { onResize(2) }
                        Button("Wide") { onResize(3) }; Button("Extra wide") { onResize(5) }
                    }
                }
                if let onRemove { Button("Remove from Dock", action: onRemove) }
            }
        }
    }
    @ViewBuilder private func denseDockCard(wide: Bool, scale: CGFloat, availableWidth: CGFloat) -> some View {
        switch kind {
        case .stocks:
            openLabel {
                HStack(spacing: 5 * scale) {
                    VStack(alignment: wide ? .leading : .center, spacing: 1 * scale) {
                        HStack(spacing: 3 * scale) {
                            Text(stocks.quote?.symbol ?? stocks.symbol).font(.system(size: 7.3 * scale, weight: .semibold)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: true, vertical: false)
                            if wide, let quote = stocks.quote {
                                Text(String(format: "%+.1f%%", quote.changePercent)).font(.system(size: 6.5 * scale)).fixedSize(horizontal: true, vertical: false)
                                    .foregroundStyle(quote.isPositive ? .green : .red)
                            }
                            Spacer(minLength: 0)
                        }
                        Text(stocks.quote.map { wide ? $0.formattedTilePrice : $0.price.formatted(.number.precision(.fractionLength(2))) } ?? "—")
                            .font(.system(size: 11.5 * scale * textScale, weight: .semibold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.65)
                    }
                    if wide {
                        StockSparkline(points: stocks.quote?.points ?? [], tint: stocks.quote?.isPositive == false ? .red : .green)
                            .frame(width: max(16, (availableWidth - 20) * 0.28), height: 16 * scale)
                    }
                }.padding(.horizontal, 5 * scale).padding(.vertical, 2 * scale)
            }
        case .timer:
            HStack(spacing: 5 * scale) {
                openLabel {
                    VStack(spacing: 0) {
                        Text(timer.mode == .timer ? timer.sessionName : timer.mode.rawValue).font(.system(size: 7 * scale)).foregroundStyle(.white.opacity(0.55))
                        Text(timer.displayValue).font(.system(size: 13.5 * scale * textScale, weight: .semibold, design: .rounded).monospacedDigit())
                            .lineLimit(1).minimumScaleFactor(0.65)
                    }
                }
                if wide {
                    Button { timer.isRunning ? timer.pause() : timer.startOrResume() } label: {
                        Image(systemName: timer.isRunning ? "pause.fill" : "play.fill").font(.system(size: 9 * scale)).foregroundStyle(.orange)
                    }.buttonStyle(.plain).help("Start, pause or resume")
                }
            }.padding(.horizontal, 5 * scale).padding(.vertical, 2 * scale)
        case .weather:
            openLabel {
                ViewThatFits(in: .horizontal) {
                    compactWeatherRow(iconSize: 13 * scale, fontSize: 13 * scale, spacing: 4 * scale)
                        .fixedSize(horizontal: true, vertical: false)
                    compactWeatherRow(iconSize: 10 * scale, fontSize: 11 * scale, spacing: 2 * scale)
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(spacing: 0) {
                        Image(systemName: weather.location == nil ? "cloud.sun.fill" : weather.symbol)
                            .symbolRenderingMode(.multicolor).font(.system(size: 8 * scale))
                        compactWeatherValue(fontSize: 10 * scale)
                    }
                }.padding(.horizontal, 3 * scale)
            }
        case .music:
            HStack(spacing: 5 * scale) {
                openLabel {
                    HStack(spacing: 5 * scale) {
                        Image(systemName: "music.note").font(.system(size: 12 * scale))
                        if wide { Text(music.hasTrack ? music.title : "Music").font(.system(size: 8.5 * scale, weight: .medium)).lineLimit(1) }
                    }
                }
                if wide && music.isConnected {
                    Button(action: music.togglePlayback) { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 9 * scale)) }
                        .buttonStyle(.plain).disabled(music.isWorking).help("Play or pause")
                }
            }.padding(.horizontal, 6 * scale)
        case .calendar:
            openLabel {
                VStack(spacing: 0) {
                    Text(Date().formatted(.dateTime.month(.abbreviated)).uppercased()).font(.system(size: 7 * scale, weight: .semibold)).foregroundStyle(.red)
                    Text(Date().formatted(.dateTime.day())).font(.system(size: 15 * scale, weight: .medium, design: .rounded))
                }
            }
        case .reminders:
            openLabel {
                HStack(spacing: 4 * scale) {
                    Image(systemName: "checklist").font(.system(size: 12 * scale))
                    Text(agenda.remindersAllowed ? "\(agenda.reminders.count)" : "Tasks").font(.system(size: 9 * scale, weight: .medium))
                }.padding(.horizontal, 4 * scale)
            }
        case .notes:
            notesCard(wide: wide, scale: scale)
        case .clock:
            openLabel {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(clock(context.date)).font(.system(size: 12 * scale * textScale, weight: .medium, design: .rounded).monospacedDigit())
                        .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 4 * scale)
                }
            }
        }
    }
    private func notesCard(wide: Bool, scale: CGFloat) -> some View {
        openLabel {
            HStack(spacing: 5 * scale) {
                Image(systemName: noteText.isEmpty ? "square.and.pencil" : "note.text").font(.system(size: 13 * scale)).foregroundStyle(.yellow)
                if wide {
                    Text(noteText.split(separator: "\n").first.map(String.init) ?? "Quick note")
                        .font(.system(size: 9 * scale, weight: .medium)).lineLimit(1)
                }
            }.padding(.horizontal, 5 * scale)
        }
    }
    private func compactWeatherRow(iconSize: CGFloat, fontSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            Image(systemName: weather.location == nil ? "cloud.sun.fill" : weather.symbol)
                .symbolRenderingMode(.multicolor).font(.system(size: iconSize))
            compactWeatherValue(fontSize: fontSize)
        }
    }
    private func compactWeatherValue(fontSize: CGFloat) -> some View {
        Text(weather.location == nil ? "Set city" : weather.displayTemperature)
            .font(.system(size: weather.location == nil ? min(fontSize, 8) : fontSize * textScale,
                          weight: .semibold, design: .rounded))
            .lineLimit(1).minimumScaleFactor(0.5)
    }
    private func openLabel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Button(action: onOpen) { content().frame(maxWidth: .infinity, maxHeight: .infinity) }
            .buttonStyle(.plain).help("Open \(kind.title)")
    }
    private func musicCard(wide: Bool) -> some View {
        HStack(spacing: 9) {
            openLabel {
                HStack(spacing: 9) {
                    Image(systemName: "music.note").font(.system(size: wide ? 28 : 24)).frame(width: wide ? 48 : 32, height: 54)
                        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 11))
                    if wide {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(music.hasTrack ? music.title : "Music").font(.system(size: 14 * textScale, weight: .bold)).lineLimit(1)
                            Text(music.isConnected ? music.artist : "Connect Music or Spotify").font(.system(size: 10 * textScale)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                        }
                    }
                }
            }
            if wide && music.isConnected {
                HStack(spacing: 9) {
                    Button(action: music.previousTrack) { Image(systemName: "backward.end.fill") }.help("Previous track")
                    Button(action: music.togglePlayback) { Image(systemName: music.isPlaying ? "pause.fill" : "play.fill") }.help("Play or pause")
                    Button(action: music.nextTrack) { Image(systemName: "forward.end.fill") }.help("Next track")
                }.buttonStyle(.plain).font(.system(size: 13)).disabled(music.isWorking)
            }
        }.padding(9)
    }
    private func timerCard(wide: Bool) -> some View {
        HStack(spacing: 8) {
            openLabel {
                VStack(spacing: 3) {
                    Text(timer.mode.rawValue).font(.system(size: 10 * textScale)).foregroundStyle(.gray)
                    Text(timer.displayValue).font(.system(size: 27 * textScale, weight: .bold, design: .rounded).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.5)
                    if wide { Text(timer.statusText).font(.system(size: 9)).foregroundStyle(.orange) }
                }
            }
            if wide {
                VStack(spacing: 8) {
                    Button { timer.isRunning ? timer.pause() : timer.startOrResume() } label: { Image(systemName: timer.isRunning ? "pause.fill" : "play.fill") }.help("Start, pause or resume")
                    Button(action: timer.reset) { Image(systemName: "arrow.counterclockwise") }.help("Reset")
                }.buttonStyle(.plain).foregroundStyle(.orange).font(.system(size: 13))
            }
        }.padding(8)
    }
    private func stocksCard(wide: Bool) -> some View {
        openLabel {
            HStack(spacing: 9) {
                VStack(alignment: wide ? .leading : .center, spacing: 3) {
                    Text(stocks.quote?.symbol ?? stocks.symbol).font(.system(size: 10 * textScale, weight: .bold)).foregroundStyle(.gray)
                    Text(stocks.quote.map { wide ? $0.formattedPrice : $0.price.formatted(.number.precision(.fractionLength(2))) } ?? "—")
                        .font(.system(size: 21 * textScale, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.3)
                    Text(stocks.quote.map { String(format: "%+.2f%%", $0.changePercent) } ?? (stocks.isRefreshing ? "Loading" : "Open stocks"))
                        .font(.system(size: 9 * textScale, weight: .semibold)).foregroundStyle(stocks.quote?.isPositive == false ? .red : .green)
                }
                if wide { StockSparkline(points: stocks.quote?.points ?? [], tint: stocks.quote?.isPositive == false ? .red : .green).frame(maxWidth: .infinity).frame(height: 43) }
            }.padding(10)
        }
    }
    private func weatherCard(wide: Bool) -> some View {
        openLabel {
            HStack(spacing: 8) {
                Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 27))
                VStack(alignment: wide ? .leading : .center, spacing: 2) {
                    if wide { Text(weather.location?.name ?? "Choose city").font(.system(size: 10 * textScale, weight: .medium)).foregroundStyle(.gray).lineLimit(1) }
                    Text(weather.displayTemperature).font(.system(size: 28 * textScale, weight: .bold, design: .rounded))
                    if wide { Text(weather.condition).font(.system(size: 9 * textScale)).foregroundStyle(.gray).lineLimit(1) }
                }
            }.padding(9)
        }
    }
    private var calendarCard: some View {
        openLabel {
            VStack(spacing: 0) {
                Text(Date().formatted(.dateTime.month(.abbreviated)).uppercased()).font(.system(size: 12, weight: .bold)).foregroundStyle(.red)
                Text(Date().formatted(.dateTime.day())).font(.system(size: 37 * textScale, weight: .light, design: .rounded))
            }.padding(5)
        }
    }
    private var reminderCard: some View {
        openLabel {
            VStack(spacing: 2) {
                Text("Reminders").font(.system(size: 10 * textScale)).foregroundStyle(.gray)
                Text(agenda.remindersAllowed ? "\(agenda.reminders.count)" : "—").font(.system(size: 29 * textScale, weight: .bold, design: .rounded))
            }
        }
    }
    private var clockCard: some View {
        openLabel {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(spacing: 2) {
                    Text(context.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.system(size: 10)).foregroundStyle(.gray)
                    Text(clock(context.date)).font(.system(size: 26 * textScale, weight: .medium, design: .rounded).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.4)
                }
            }
        }
    }
    private func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = (DockletPreferences.shared.object(forKey: "docklet.clock.24hour") as? Bool ?? true) ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }
}
