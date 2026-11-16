import HealthKit
import PMKHealthKit
import PromiseKit
import SwiftUI
import WatchKit

// SwiftUI version of the terminal screen. Unlike the storyboard screen, a
// SwiftUI hosting controller honours `.statusBarHidden()`, which removes the
// system clock in the top-right corner.

private enum TermColors {
  static let label = Color.white
  static let time = Color(red: 0.2, green: 1.0, blue: 0.25)
  static let date = Color(red: 0.325, green: 0.647, blue: 0.984)
  static let temperature = Color(red: 0.992, green: 0.561, blue: 0.247)
  static let batteryNormal = Color(red: 0.2, green: 1.0, blue: 0.25)
  static let batteryLow = Color.red
  static let exercise = Color(red: 1.0, green: 0.231, blue: 0.188)
  static let move = Color(red: 0.2, green: 1.0, blue: 0.25)
  static let stand = Color(red: 0.325, green: 0.647, blue: 0.984)
  static let steps = Color(red: 0.588, green: 0.525, blue: 0.961)
  static let sleep = Color(red: 1.0, green: 0.1, blue: 0.1)
  static let uptime = Color(red: 1.0, green: 0.85, blue: 0.2)
}

final class TerminalModel: ObservableObject {
  @Published var weather = "--"
  @Published var battery = "--"
  @Published var batteryLow = false
  @Published var rings: (Int, Int, Int)? = nil
  @Published var steps = "--"
  @Published var sleep = "-"
  @Published var lastCharge: Date? = ChargeTracker.lastCharge
  @Published var charging = ChargeTracker.isCharging

  private let healthStore = HKHealthStore()
  private var started = false
  private var lastSleepRefresh: Date?
  // Day (start of day) whose sleep is already final; no more queries until tomorrow.
  private var sleepDoneForDay: Date?

  func start() {
    guard !started else { return }
    started = true

    // Weather (fixed location, no Location Services)
    let formatter = MeasurementFormatter()
    localizedTemperatureStyle(formatter)
    NotificationCenter.default.addObserver(
      forName: TemperatureNotifier.TemperatureDidChangeNotification,
      object: nil, queue: .main
    ) { [weak self] notification in
      guard let w = notification.object as? WeatherInfo else { return }
      var text = "\(formatter.string(from: w.temperature)), \(w.condition)"
      if let rain = w.rainChance { text += " \(rain)%" }
      self?.weather = text
    }
    TemperatureNotifier.shared.refreshIfStale()

    // Last charge ([UPTM]): cache values instead of reading storage every second
    NotificationCenter.default.addObserver(
      forName: ChargeTracker.didChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.lastCharge = ChargeTracker.lastCharge
      self?.charging = ChargeTracker.isCharging
    }

    // Health
    let types = Set([
      HKObjectType.activitySummaryType(),
      HKCategoryType.categoryType(forIdentifier: .appleStandHour)!,
      HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
      HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
      HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
      HKObjectType.quantityType(forIdentifier: .stepCount)!,
    ])
    firstly {
      healthStore.requestAuthorization(toShare: nil, read: types)
    }.done { [weak self] _ in
      guard let self = self else { return }
      let ringUpdate: (HKActivitySummary) -> Void = { [weak self] s in
        let e = Int(s.activeEnergyBurned.doubleValue(for: .kilocalorie()))
        let m = Int(s.appleExerciseTime.doubleValue(for: .minute()))
        let st = Int(s.appleStandHours.doubleValue(for: .count()))
        DispatchQueue.main.async { self?.rings = (e, m, st) }
      }
      // One observer: active energy is written every few minutes, so the whole
      // summary (energy, exercise, stand) is refreshed with it.
      subscribeToActivitySummary(
        forSampleType: HKSampleType.quantityType(forIdentifier: .activeEnergyBurned)!,
        healthStore: self.healthStore, completion: ringUpdate)
      subscribeToStatisticsForToday(
        forQuantityType: HKQuantityType.quantityType(forIdentifier: .stepCount)!,
        unit: .count(), options: .cumulativeSum, healthStore: self.healthStore
      ) { [weak self] v in DispatchQueue.main.async { self?.steps = "\(Int(v)) steps" } }
      self.refreshSleep(force: true)
    }.catch { print("Error:", $0) }

    // Battery
    NotificationCenter.default.addObserver(
      forName: BatteryInfoNotifier.BatteryDidChangeNotification,
      object: nil, queue: .main
    ) { [weak self] notification in
      let info = notification.object as! BatteryInfo
      guard info.state != .unknown else { return }
      self?.battery = batteryIndicatorString(percent: UInt(info.level))
      self?.batteryLow = info.level <= 20
      ChargeTracker.sample()
    }
    BatteryInfoNotifier.shared.start()
  }

  // Called whenever the app becomes active again (wrist raise). Everything here
  // is a cheap check; network/Health queries only run when data is stale.
  func refresh() {
    guard started else { return }
    BatteryInfoNotifier.shared.poll()
    TemperatureNotifier.shared.refreshIfStale()
    refreshSleep()
  }

  // Total time asleep in the most recent sleep session (last 36 h). Samples
  // from several sources (Watch, iPhone, apps) are merged so overlaps are not
  // double-counted; a gap of more than 3 h starts a new session.
  // Sleep changes once a day. Query at most every 30 min, and only until this
  // morning's sleep is found and settled (ended 2+ h ago); then stop until the
  // next day.
  func refreshSleep(force: Bool = false) {
    let today = Calendar.current.startOfDay(for: Date())
    if !force, sleepDoneForDay == today { return }
    if !force, let last = lastSleepRefresh, Date().timeIntervalSince(last) < 1800 { return }
    lastSleepRefresh = Date()
    guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
    let now = Date()
    let predicate = HKQuery.predicateForSamples(
      withStart: now.addingTimeInterval(-36 * 3600), end: now, options: [])
    let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
    let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map { $0.rawValue }

    let query = HKSampleQuery(
      sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
      sortDescriptors: [sort]
    ) { [weak self] _, samples, _ in
      let intervals = (samples as? [HKCategorySample] ?? [])
        .filter { asleep.contains($0.value) }
        .map { ($0.startDate, $0.endDate) }

      // Merge overlapping intervals.
      var merged: [(Date, Date)] = []
      for (start, end) in intervals {
        if let last = merged.last, start <= last.1 {
          merged[merged.count - 1].1 = max(last.1, end)
        } else {
          merged.append((start, end))
        }
      }

      // Group into sessions and keep the latest one.
      var sessionTotal: TimeInterval = 0
      var previousEnd: Date?
      for (start, end) in merged {
        if let prev = previousEnd, start.timeIntervalSince(prev) > 3 * 3600 {
          sessionTotal = 0
        }
        sessionTotal += end.timeIntervalSince(start)
        previousEnd = end
      }

      let text: String
      if sessionTotal < 60 {
        text = "-"
      } else {
        let minutes = Int(sessionTotal / 60)
        text = "\(minutes / 60)h\(String(format: "%02d", minutes % 60))m"
      }
      // Settled = the latest session ended today and at least 2 h ago (so a
      // short wake-up followed by more sleep is still picked up).
      let settled = sessionTotal >= 60 && previousEnd.map {
        $0 >= Calendar.current.startOfDay(for: now) && now.timeIntervalSince($0) >= 2 * 3600
      } ?? false

      DispatchQueue.main.async {
        self?.sleep = text
        if settled { self?.sleepDoneForDay = Calendar.current.startOfDay(for: now) }
      }
    }
    healthStore.execute(query)
  }
}

struct TerminalView: View {
  @ObservedObject var model: TerminalModel
  // True when the wrist is down (Always-On): redraw once a minute, no seconds.
  @Environment(\.isLuminanceReduced) private var dimmed

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .medium
    f.dateStyle = .none
    return f
  }()

  private static let shortTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    f.dateStyle = .none
    return f
  }()

  private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, E"
    return f
  }()

  private var fontSize: CGFloat {
    // 16pt on a 45 mm screen (198 pt wide), scaled for other sizes.
    (WKInterfaceDevice.current().screenBounds.width / 12.4).rounded(.down)
  }

  // One Text per line so an over-long line shrinks as a whole instead of overflowing.
  private func row(_ tag: String, _ value: Text) -> Text {
    Text(tag).foregroundColor(TermColors.label) + value
  }

  private func colored(_ string: String, _ color: Color) -> Text {
    Text(string).foregroundColor(color)
  }

  private var ringText: Text {
    guard let r = model.rings else { return colored("--", TermColors.label) }
    let sep = colored(" • ", TermColors.label)
    return colored("\(r.0)", TermColors.exercise) + sep
      + colored("\(r.1)", TermColors.move) + sep
      + colored("\(r.2)", TermColors.stand)
  }

  var body: some View {
    TimelineView(.periodic(
      from: Calendar.current.dateInterval(of: .minute, for: Date())!.start,
      by: dimmed ? 60 : 1
    )) { context in
      VStack(alignment: .leading, spacing: 2) {
        colored("user@watch:~ $ now", TermColors.label)
        row("[TIME]", colored(
          (dimmed ? Self.shortTimeFormatter : Self.timeFormatter).string(from: context.date),
          TermColors.time))
        row("[DATE]", colored(Self.dateFormatter.string(from: context.date), TermColors.date))
        row("[WTHR]", colored(model.weather, TermColors.temperature))
        row("[BATT]", colored(model.battery,
                              model.batteryLow ? TermColors.batteryLow : TermColors.batteryNormal))
        row("[RING]", ringText)
        row("[STEP]", colored(model.steps, TermColors.steps))
        row("[SLEP]", colored(model.sleep, TermColors.sleep))
        row("[UPTM]", colored(
          ChargeTracker.uptimeString(now: context.date, lastCharge: model.lastCharge,
                                     charging: model.charging),
          TermColors.uptime))
        colored("user@watch:~ $ ", TermColors.label)
      }
      .font(.system(size: fontSize, design: .monospaced))
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      // Block is as wide as its longest line (capped to the screen), then centred
      // so the margins are equal on all four sides.
      .frame(maxWidth: WKInterfaceDevice.current().screenBounds.width - 10)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .background(Color.black)
    .ignoresSafeArea()
    ._statusBarHidden(true)
    .onAppear { model.start() }
  }
}

final class TerminalHostingController: WKHostingController<TerminalView> {
  private let model = TerminalModel()

  override var body: TerminalView {
    TerminalView(model: model)
  }

  override func willActivate() {
    super.willActivate()
    model.refresh()
  }
}
