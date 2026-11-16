import Foundation
import PMKFoundation
import PromiseKit

// Weather from Open-Meteo (free, no API key): current temperature, WMO weather
// code, and precipitation probability for the next 3 hours, in one request.
// Location is fixed (no Location Services): Maracaibo, Zulia, Venezuela.

let weatherLatitude = 10.64
let weatherLongitude = -71.61

public struct WeatherInfo: Equatable {
  let temperature: Measurement<UnitTemperature>
  let condition: String  // short English word, max 5 chars
  let rainChance: Int?   // max precipitation probability over the next 3 h
}

func shortCondition(wmoCode code: Int) -> String {
  switch code {
  case 0, 1: return "Clear"
  case 2, 3: return "Cloud"
  case 45, 48: return "Fog"
  case 51...67, 80...82: return "Rain"
  case 71...77, 85, 86: return "Snow"
  case 95...99: return "Storm"
  default: return "?"
  }
}

func OpenMeteoURL() -> URL {
  let lat = String(format: "%.2f", weatherLatitude)
  let lon = String(format: "%.2f", weatherLongitude)
  return URL(
    string: "https://api.open-meteo.com/v1/forecast?"
      + "latitude=\(lat)&longitude=\(lon)"
      + "&current=temperature_2m,weather_code"
      + "&hourly=precipitation_probability&forecast_hours=3&timezone=auto"
  )!
}

let disabledCachingConfig: (URLSessionConfiguration) -> Void = {
  $0.requestCachePolicy = .reloadIgnoringLocalCacheData
  $0.urlCache = nil
}

struct OpenMeteoResponse: Codable {
  struct Current: Codable {
    let temperature_2m: Double
    let weather_code: Int
  }
  struct Hourly: Codable {
    let precipitation_probability: [Int?]
  }
  let current: Current
  let hourly: Hourly?
}

func fetchWeather() -> Promise<WeatherInfo> {
  return Promise { seal in
    let sessionConfig = URLSessionConfiguration.default
    disabledCachingConfig(sessionConfig)

    URLSession(configuration: sessionConfig).dataTask(
      .promise,
      with: OpenMeteoURL()
    ).compactMap {
      try JSONDecoder().decode(OpenMeteoResponse.self, from: $0.data)
    }.done {
      let chances = $0.hourly?.precipitation_probability.compactMap { $0 } ?? []
      seal.fulfill(WeatherInfo(
        temperature: Measurement(value: $0.current.temperature_2m, unit: .celsius),
        condition: shortCondition(wmoCode: $0.current.weather_code),
        rainChance: chances.max()
      ))
    }.catch {
      seal.reject($0)
    }
  }
}

public class TemperatureNotifier {
  public static let TemperatureDidChangeNotification = Notification.Name(
    rawValue: "TemperatureNotifier.TemperatureDidChangeNotification"
  )

  public static let shared = TemperatureNotifier()
  private init() {}

  public private(set) var weather: WeatherInfo?

  private var lastSuccess: Date?
  private var fetching = false

  // No timer: the app calls refreshIfStale() when it opens or becomes active.

  // Called when the app becomes active: only hits the network if the last
  // successful reading is older than maxAge (or there is none yet).
  public func refreshIfStale(maxAge: TimeInterval = 1800) {
    if let last = lastSuccess, Date().timeIntervalSince(last) < maxAge { return }
    fetch()
  }

  private func fetch() {
    guard !fetching else { return }
    fetching = true
    fetchWeather().done { [weak self] current in
      self?.lastSuccess = Date()
      if current == self?.weather {
        return
      }

      self?.weather = current

      NotificationCenter.default.post(
        Notification(
          name: TemperatureNotifier.TemperatureDidChangeNotification,
          object: self?.weather,
          userInfo: nil
        )
      )
    }.ensure { [weak self] in
      self?.fetching = false
    }.catch {
      print("Error:", $0.localizedDescription)
    }
  }
}
