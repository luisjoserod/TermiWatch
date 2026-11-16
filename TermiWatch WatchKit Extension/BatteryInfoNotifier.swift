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
