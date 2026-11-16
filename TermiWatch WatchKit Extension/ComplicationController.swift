import ClockKit
import UIKit

// Static launcher complication: shows the TermiWatch icon; tapping it opens the app.
class ComplicationController: NSObject, CLKComplicationDataSource {
  private static let families: [CLKComplicationFamily] = [
    .graphicCircular, .graphicCorner, .modularSmall, .circularSmall,
    .utilitarianSmall, .extraLarge,
  ]

  func getComplicationDescriptors(handler: @escaping ([CLKComplicationDescriptor]) -> Void) {
    handler([
      CLKComplicationDescriptor(
        identifier: "launcher",
        displayName: "TermiWatch",
        supportedFamilies: Self.families
      )
    ])
  }

  func getCurrentTimelineEntry(
    for complication: CLKComplication,
    withHandler handler: @escaping (CLKComplicationTimelineEntry?) -> Void
  ) {
    handler(template(for: complication.family).map {
      CLKComplicationTimelineEntry(date: Date(), complicationTemplate: $0)
    })
  }

  func getLocalizableSampleTemplate(
    for complication: CLKComplication,
    withHandler handler: @escaping (CLKComplicationTemplate?) -> Void
  ) {
    handler(template(for: complication.family))
  }

  func getPrivacyBehavior(
    for complication: CLKComplication,
    withHandler handler: @escaping (CLKComplicationPrivacyBehavior) -> Void
  ) {
    handler(.showOnLockScreen)
  }

  func getTimelineEndDate(
    for complication: CLKComplication,
    withHandler handler: @escaping (Date?) -> Void
  ) {
    handler(.distantFuture)
  }

  private func template(for family: CLKComplicationFamily) -> CLKComplicationTemplate? {
    let icon = UIImage(named: "ComplicationIcon") ?? UIImage()
    let prompt = CLKSimpleTextProvider(text: "$_")
    prompt.tintColor = UIColor(red: 0.2, green: 1.0, blue: 0.25, alpha: 1.0)

    switch family {
    case .graphicCircular:
      return CLKComplicationTemplateGraphicCircularImage(
        imageProvider: CLKFullColorImageProvider(fullColorImage: icon))
    case .graphicCorner:
      return CLKComplicationTemplateGraphicCornerCircularImage(
        imageProvider: CLKFullColorImageProvider(fullColorImage: icon))
    case .modularSmall:
      return CLKComplicationTemplateModularSmallSimpleText(textProvider: prompt)
    case .circularSmall:
      return CLKComplicationTemplateCircularSmallSimpleText(textProvider: prompt)
    case .utilitarianSmall:
      return CLKComplicationTemplateUtilitarianSmallFlat(textProvider: prompt)
    case .extraLarge:
      return CLKComplicationTemplateExtraLargeSimpleText(textProvider: prompt)
    default:
      return nil
    }
  }
}
