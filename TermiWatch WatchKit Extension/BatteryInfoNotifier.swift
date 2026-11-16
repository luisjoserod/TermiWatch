import Foundation
import WatchKit

public struct BatteryInfo {
  var state: WKInterfaceDeviceBatteryState
  var level: Float
}

func batteryInfo(forDevice device: WKInterfaceDevice = .current())
  -> BatteryInfo {
  let originalMonitoringValue = device.isBatteryMonitoringEnabled

  defer {
    device.isBatteryMonitoringEnabled = originalMonitoringValue
  }

  device.isBatteryMonitoringEnabled = true

  return BatteryInfo(
    state: device.batteryState,
    level: device.batteryLevel * 100.0
  )
}

public class BatteryInfoNotifier {
  public static let BatteryDidChangeNotification = Notification.Name(
    rawValue: "BatteryInfoNotifier.BatteryInfoDidChangeNotification"
  )

  public static let shared = BatteryInfoNotifier()
  private init() {}

  public private(set) var info = BatteryInfo(state: .unknown, level: -1)
  private var timer: Timer?

  public static let device = WKInterfaceDevice.current()

  public var isStarted: Bool {
    return timer != nil && timer!.isValid
  }

  public func start(withTimeInterval interval: TimeInterval = 300) {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
      [weak self] _ in self?.poll()
    }
    timer!.fire()
  }

  // Read the battery now and notify only if something changed.
  public func poll() {
    let currentInfo = batteryInfo(forDevice: BatteryInfoNotifier.device)
    guard currentInfo.state != info.state || currentInfo.level != info.level else { return }
    info = currentInfo
    NotificationCenter.default.post(Notification(
      name: BatteryInfoNotifier.BatteryDidChangeNotification,
      object: info,
      userInfo: nil
    ))
  }

  public func stop() {
    timer?.invalidate()
    timer = nil
  }
}

// MARK: - Last charge tracking (for [UPTM])
//
// watchOS gives apps no battery history, so we infer the last charge:
// whenever we observe the watch charging (or at 100% and plugged in), or the
// level is higher than the previous observation, we record "now" as the last
// charge time. Observations happen while the app is open and from an hourly
// background refresh, so the estimate is accurate to roughly an hour.
public enum ChargeTracker {
  public static let didChangeNotification = Notification.Name("ChargeTracker.didChange")

  private static let defaults = UserDefaults.standard
  private static let lastChargeKey = "tw.lastCharge"
  private static let lastLevelKey = "tw.lastLevel"
  private static let chargingKey = "tw.isCharging"

  public static var lastCharge: Date? { defaults.object(forKey: lastChargeKey) as? Date }
  public static var isCharging: Bool { defaults.bool(forKey: chargingKey) }

  public static func sample() {
    let info = batteryInfo()
    guard info.state != .unknown, info.level >= 0 else { return }

    let charging = info.state == .charging || info.state == .full
    let previousLevel = defaults.object(forKey: lastLevelKey) as? Float
    let rose = previousLevel.map { info.level > $0 + 1 } ?? false

    if charging || rose {
      defaults.set(Date(), forKey: lastChargeKey)
    }
    defaults.set(info.level, forKey: lastLevelKey)
    defaults.set(charging, forKey: chargingKey)
    NotificationCenter.default.post(name: didChangeNotification, object: nil)
  }

  // "up 1d 07h", "up 5h 12m", "charging", or "-" before the first charge is seen.
  public static func uptimeString(now: Date = Date()) -> String {
    uptimeString(now: now, lastCharge: lastCharge, charging: isCharging)
  }

  public static func uptimeString(now: Date, lastCharge: Date?, charging: Bool) -> String {
    if charging { return "charging" }
    guard let last = lastCharge else { return "-" }
    let minutes = max(0, Int(now.timeIntervalSince(last) / 60))
    let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
    if days > 0 { return "up \(days)d \(String(format: "%02d", hours))h" }
    return "up \(hours)h \(String(format: "%02d", mins))m"
  }

  // Ask watchOS to wake the extension in about an hour to sample again.
  public static func scheduleBackgroundSample() {
    WKExtension.shared().scheduleBackgroundRefresh(
      withPreferredDate: Date().addingTimeInterval(3600), userInfo: nil
    ) { _ in }
  }
}
