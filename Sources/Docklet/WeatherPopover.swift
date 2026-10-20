import SwiftUI

struct WeatherPopover: View {
    @ObservedObject var store: WeatherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.location?.displayName ?? "Weather")
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                    Text(store.location == nil ? "Choose a city for a live forecast" : "Four-day forecast · " + (store.fahrenheit ? "Fahrenheit" : "Celsius"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                } else if store.currentTemperature != nil {
                    Button { Task { await store.refresh() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh weather")
                }
                if store.location != nil {
                    Button(action: store.clearLocation) {
                        Image(systemName: "location.slash")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear selected city")
                }
            }

            Picker("Temperature units", selection: $store.fahrenheit) {
                Text("Celsius · °C").tag(false)
                Text("Fahrenheit · °F").tag(true)
            }.pickerStyle(.segmented)
            HStack(spacing: 8) {
                TextField("Search city", text: $store.cityQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await store.searchCity() } }
                Button("Search") { Task { await store.searchCity() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isSearching)
            }

            if store.isSearching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching locations…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            if !store.searchResults.isEmpty {
                VStack(spacing: 3) {
                    ForEach(store.searchResults) { result in
                        Button { store.select(result) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name).font(.system(size: 12, weight: .semibold))
                                    Text([result.admin1, result.country].compactMap { $0 }.joined(separator: ", "))
                                        .font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 5)
                    }
                }
                .padding(10)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            }

            if let temperature = store.currentTemperature {
                HStack(alignment: .top, spacing: 13) {
                    Image(systemName: store.symbol)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.cyan, .yellow)
                        .font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.temperatureString(temperature))
                            .font(.system(size: 38, weight: .medium, design: .rounded))
                        Text(store.condition).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        if let feels = store.apparentTemperature {
                            Text("Feels like " + store.temperatureString(feels))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let humidity = store.humidity {
                        VStack(alignment: .trailing, spacing: 5) {
                            Image(systemName: "humidity.fill").foregroundStyle(.cyan)
                            Text("\(humidity)%").font(.system(size: 12, weight: .semibold))
                        }
                    }
                }

                if !store.forecast.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(store.forecast) { day in
                            VStack(spacing: 7) {
                                Text(day.label)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Image(systemName: WeatherStore.symbol(for: day.conditionCode))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.cyan, .yellow)
                                    .font(.system(size: 19))
                                Text(store.temperatureString(day.high))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                Text(store.temperatureString(day.low))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                }
            } else if store.location == nil {
                Text("Search for a city, then choose a result. Docklet sends that city name to Open-Meteo to find its coordinates and forecast.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = store.errorMessage {
                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(store.updatedDescription ?? "No forecast loaded")
                Spacer()
                Link("Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(19)
        .background(.regularMaterial)
    }
}
