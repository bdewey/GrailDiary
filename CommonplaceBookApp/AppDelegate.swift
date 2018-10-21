// Copyright © 2018 Brian's Brain. All rights reserved.

import CocoaLumberjack
import CommonplaceBook
import FlashcardKit
import MaterialComponents.MaterialAppBar
import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

  var window: UIWindow?
  let useCloud = true

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    DDLog.add(DDTTYLogger.sharedInstance) // TTY = Xcode console

    let window = UIWindow(frame: UIScreen.main.bounds)
    let navigationController = MDCAppBarNavigationController()
    navigationController.delegate = self
    navigationController.pushViewController(
      DocumentListViewController(
        parsingRules: LanguageDeck.parsingRules,
        stylesheet: commonplaceBookStylesheet
      ),
      animated: false
    )
    window.rootViewController = navigationController
    window.makeKeyAndVisible()
    self.window = window
    return true
  }
}

private let commonplaceBookStylesheet: Stylesheet = {
  var stylesheet = Stylesheet()
  stylesheet.colorScheme.primaryColor = UIColor.white
  stylesheet.colorScheme.onPrimaryColor = UIColor.black
  stylesheet.colorScheme.secondaryColor = UIColor(rgb: 0x661FFF)
  stylesheet.colorScheme.surfaceColor = UIColor.white
  stylesheet.typographyScheme.headline6 = UIFont(name: "LibreFranklin-Medium", size: 20.0)!
  stylesheet.typographyScheme.body2 = UIFont(name: "LibreFranklin-Regular", size: 14.0)!
  stylesheet.typographyScheme.caption = UIFont(name: "Merriweather-Light", size: 11.4)!
  stylesheet.typographyScheme.subtitle1 = UIFont(name: "LibreFranklin-SemiBold", size: 15.95)!
  stylesheet.kern[.headline6] = 0.25
  stylesheet.kern[.body2] = 0.25
  stylesheet.kern[.caption] = 0.4
  stylesheet.kern[.subtitle1] = 0.15
  return stylesheet
}()

extension UIViewController {
  var semanticColorScheme: MDCColorScheming {
    if let container = self as? StylesheetContaining {
      return container.stylesheet.colorScheme
    } else {
      return MDCSemanticColorScheme(defaults: .material201804)
    }
  }

  var typographyScheme: MDCTypographyScheme {
    if let container = self as? StylesheetContaining {
      return container.stylesheet.typographyScheme
    } else {
      return MDCTypographyScheme(defaults: .material201804)
    }
  }
}

extension AppDelegate: MDCAppBarNavigationControllerDelegate {
  func appBarNavigationController(
    _ navigationController: MDCAppBarNavigationController,
    willAdd appBar: MDCAppBar,
    asChildOf viewController: UIViewController
  ) {
    MDCAppBarColorThemer.applySemanticColorScheme(
      viewController.semanticColorScheme,
      to: appBar
    )
    MDCAppBarTypographyThemer.applyTypographyScheme(
      viewController.typographyScheme,
      to: appBar
    )
    if var forwarder = viewController as? MDCScrollEventForwarder {
      forwarder.headerView = appBar.headerViewController.headerView
      appBar.headerViewController.headerView.observesTrackingScrollViewScrollEvents = false
      appBar.headerViewController.headerView.shiftBehavior = forwarder.desiredShiftBehavior
    }
  }
}
