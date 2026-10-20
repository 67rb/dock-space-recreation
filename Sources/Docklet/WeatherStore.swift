import Combine
import Foundation

struct GeoLocation: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let country_code: String?
    let admin1: String?
    let timezone: String?

    var displayName: String {
        [name, admin1, country]
            .compactMap { $0 }
            .reduce(into: [String]()) { parts, value in
                if !parts.contains(value) { parts.append(value) }
            }
            .joined(separator: ", ")
    }
}

struct WeatherDay: Identifiable, Codable {
    let id: String
    let label: String
    let conditionCode: Int
    let high: Double
    let low: Double
}

@MainActor
final class WeatherStore: ObservableObject {
    @Published var cityQuery = ""
    @Published private(set) var location: GeoLocation?
    @Published private(set) var searchResults: [GeoLocation] = []
    @Published private(set) var currentTemperature: Double?
    @Published private(set) var apparentTemperature: Double?
    @Published private(set) var humidity: Int?
    @Published private(set) var conditionCode: Int?
    @Published private(set) var forecast: [WeatherDay] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isSearching = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?

    @Published var fahrenheit = false { didSet { preferences.set(fahrenheit, forKey: "docklet.weather.fahrenheit") } }
    private let preferences: UserDefaults
    private let networking: Bool
    private var requestID = UUID()
    private let cacheKey = "docklet.weather.cache.v1"
    private struct Cache: Codable {
        var location: GeoLocation
        var temperature: Double
        var apparent: Double?
        var humidity: Int?
        var code: Int?
        var forecast: [WeatherDay]
        var updated: Date
    }
    private let locationKey = "docklet.weather.location.v1"

    init(preferences: UserDefaults = DockletPreferences.shared, networking: Bool = true) {
        self.preferences = preferences; self.networking = networking
        fahrenheit = preferences.bool(forKey: "docklet.weather.fahrenheit")
        if let data = preferences.data(forKey: locationKey),
           let saved = try? JSONDecoder().decode(GeoLocation.self, from: data) {
            location = saved
            cityQuery = saved.displayName
            restoreCache()
            if networking { Task { await refresh() } }
        }
    }
    func temperatureString(_ celsius: Double) -> String {
        let value = fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }
    private func restoreCache() {
        guard let data = preferences.data(forKey: cacheKey), let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.location.latitude == location?.latitude, cache.location.longitude == location?.longitude else { return }
        currentTemperature = cache.temperature; apparentTemperature = cache.apparent; humidity = cache.humidity
        conditionCode = cache.code; forecast = cache.forecast; lastUpdated = cache.updated
    }
    private func clearForecast() {
        currentTemperature = nil; apparentTemperature = nil; humidity = nil
        conditionCode = nil; forecast = []; lastUpdated = nil
    }

    func searchCity() async {
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            errorMessage = "Enter at least two letters to search."
            searchResults = []
            return
        }

        isSearching = true
        errorMessage = nil
        searchResults = []
        defer { isSearching = false }

        do {
            var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            components.queryItems = [
                URLQueryItem(name: "name", value: query),
                URLQueryItem(name: "count", value: "6"),
                URLQueryItem(name: "language", value: "en"),
                URLQueryItem(name: "format", value: "json")
            ]
            let data = try await getData(from: components.url!)
            let response = try JSONDecoder().decode(GeocodingResponse.self, from: data)
            searchResults = response.results ?? []
            if searchResults.isEmpty { errorMessage = "No matching cities found." }
        } catch {
            errorMessage = "City search failed. Check your connection and try again."
        }
    }

    func select(_ result: GeoLocation) {
        requestID = UUID(); clearForecast()
        location = result
        restoreCache()
        cityQuery = result.displayName
        searchResults = []
        errorMessage = nil
        if let data = try? JSONEncoder().encode(result) {
            preferences.set(data, forKey: locationKey)
        }
        Task { await refresh() }
    }

    func clearLocation() {
        requestID = UUID(); isRefreshing = false
        preferences.removeObject(forKey: locationKey)
        location = nil
        currentTemperature = nil
        apparentTemperature = nil
        humidity = nil
        conditionCode = nil
        forecast = []
        lastUpdated = nil
        searchResults = []
        errorMessage = nil
        cityQuery = ""
    }

    func setCurrentLocation(latitude: Double, longitude: Double) {
        let current = GeoLocation(
            id: -1,
            name: "Current Location",
            latitude: latitude,
            longitude: longitude,
            country: nil,
            country_code: nil,
            admin1: nil,
            timezone: TimeZone.current.identifier
        )
        location = current
        cityQuery = current.displayName
        if let data = try? JSONEncoder().encode(current) {
            preferences.set(data, forKey: locationKey)
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard networking else { return }
        // A native widget and the optional strip use the same selected city.
        if let data = preferences.data(forKey: locationKey),
           let saved = try? JSONDecoder().decode(GeoLocation.self, from: data) {
            if saved.latitude != location?.latitude || saved.longitude != location?.longitude {
                location = saved
                cityQuery = saved.displayName
                currentTemperature = nil
                apparentTemperature = nil
                humidity = nil
                conditionCode = nil
                forecast = []
                lastUpdated = nil
            }
        } else if location != nil {
            clearLocation()
        }
        guard let location else { return }
        let currentRequest = UUID(); requestID = currentRequest
        isRefreshing = true
        errorMessage = nil
        defer { if requestID == currentRequest { isRefreshing = false } }

        do {
            var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: String(location.latitude)),
                URLQueryItem(name: "longitude", value: String(location.longitude)),
                URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code"),
                URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
                URLQueryItem(name: "forecast_days", value: "4"),
                URLQueryItem(name: "timezone", value: "auto")
            ]
            let data = try await getData(from: components.url!)
            let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
            guard requestID == currentRequest, self.location?.latitude == location.latitude, self.location?.longitude == location.longitude else { return }
            currentTemperature = response.current.temperature
            apparentTemperature = response.current.apparent
            humidity = response.current.humidity
            conditionCode = response.current.weatherCode

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let timezone = location.timezone, let zone = TimeZone(identifier: timezone) {
                formatter.timeZone = zone
            }
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "EEE"
            dayFormatter.timeZone = formatter.timeZone
            let dayCount = min(response.daily.times.count, response.daily.weatherCodes.count, response.daily.highs.count, response.daily.lows.count)
            forecast = (0..<dayCount).map { index in
                let dateString = response.daily.times[index]
                let label: String
                if index == 0 {
                    label = "Today"
                } else if let date = formatter.date(from: dateString) {
                    label = dayFormatter.string(from: date)
                } else {
                    label = "Day \(index + 1)"
                }
                return WeatherDay(
                    id: dateString,
                    label: label,
                    conditionCode: response.daily.weatherCodes[index],
                    high: response.daily.highs[index],
                    low: response.daily.lows[index]
                )
            }
            lastUpdated = Date()
            let cache = Cache(location: location, temperature: response.current.temperature, apparent: apparentTemperature,
                              humidity: humidity, code: conditionCode, forecast: forecast, updated: lastUpdated!)
            if let data = try? JSONEncoder().encode(cache) { preferences.set(data, forKey: cacheKey) }
        } catch {
            guard requestID == currentRequest else { return }
            errorMessage = "Weather could not be refreshed. Showing the last result, if available."
        }
    }

    var displayTemperature: String {
        currentTemperature.map(temperatureString) ?? "—"
    }

    var condition: String {
        guard let conditionCode else { return "Set a city" }
        return Self.description(for: conditionCode)
    }

    var symbol: String {
        guard let conditionCode else { return "cloud.sun.fill" }
        return Self.symbol(for: conditionCode)
    }

    var updatedDescription: String? {
        guard let lastUpdated else { return nil }
        return "Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))"
    }

    private func getData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    static func description(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67: return "Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Conditions"
        }
    }

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

private struct GeocodingResponse: Decodable {
    let results: [GeoLocation]?
}

private struct ForecastResponse: Decodable {
    let current: CurrentConditions
    let daily: DailyForecast
}

private struct CurrentConditions: Decodable {
    let temperature: Double
    let apparent: Double
    let humidity: Int
    let weatherCode: Int

    enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case apparent = "apparent_temperature"
        case humidity = "relative_humidity_2m"
        case weatherCode = "weather_code"
    }
}

private struct DailyForecast: Decodable {
    let times: [String]
    let weatherCodes: [Int]
    let highs: [Double]
    let lows: [Double]

    enum CodingKeys: String, CodingKey {
        case times = "time"
        case weatherCodes = "weather_code"
        case highs = "temperature_2m_max"
        case lows = "temperature_2m_min"
    }
}
