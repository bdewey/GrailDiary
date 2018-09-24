// Copyright © 2018 Brian's Brain. All rights reserved.

import CommonplaceBook
import MaterialComponents
import UIKit

public protocol UIScrollViewForTracking {
  var scrollViewForTracking: UIScrollView { get }
}

/// Displays an MDCAppBar that contains an MDCTabBar inside the flexible header.
public final class ScrollingTopTabBarViewController: UIViewController {

  public var viewControllers: [UIViewController] = [] {
    didSet {
      if isViewLoaded {
        configureTabBar()
        configureScrollView()
      }
    }
  }

  private lazy var appBarViewController: MDCAppBarViewController = {
    let appBarViewController = MDCAppBarViewController()
    appBarViewController.inferTopSafeAreaInsetFromViewController = false
    appBarViewController.headerView.minMaxHeightIncludesSafeArea = false
    // Since we're adding a tab bar as a bottom bar, we need to adjust the minimum height.
    // 56 is the default height for a navigation bar. It's not provided as a constant though.
    appBarViewController.headerView.minimumHeight =
        56.0 + MDCTabBar.defaultHeight(for: .top, itemAppearance: .titles)
    appBarViewController.headerView.sharedWithManyScrollViews = true
    appBarViewController.headerStackView.bottomBar = tabBar
    appBarViewController.topLayoutGuideViewController = self
    appBarViewController.isTopLayoutGuideAdjustmentEnabled = true
    MDCAppBarColorThemer.applyColorScheme(
      Stylesheet.hablaEspanol.colorScheme,
      to: appBarViewController
    )
    MDCAppBarTypographyThemer.applyTypographyScheme(
      Stylesheet.hablaEspanol.typographyScheme,
      to: appBarViewController
    )
    return appBarViewController
  }()

  private lazy var tabBar: MDCTabBar = {
    let tabBar = MDCTabBar(frame: .zero)
    tabBar.delegate = self
    tabBar.alignment = .justified
    MDCTabBarColorThemer.applySemanticColorScheme(Stylesheet.hablaEspanol.colorScheme, toTabs: tabBar)
    MDCTabBarTypographyThemer.applyTypographyScheme(
      Stylesheet.hablaEspanol.typographyScheme,
      to: tabBar
    )
    return tabBar
  }()

  private lazy var scrollView: UIScrollView = {
    let scrollView = UIScrollView(frame: .zero)
    scrollView.scrollsToTop = false
    scrollView.isScrollEnabled = false
    scrollView.isPagingEnabled = true
    scrollView.backgroundColor = Stylesheet.hablaEspanol.colorScheme.backgroundColor
    scrollView.autoresizingMask = [.flexibleHeight, .flexibleWidth]
    return scrollView
  }()

  public override func viewDidLoad() {
    title = Stylesheet.hablaEspanol.appTitle
    super.viewDidLoad()
    scrollView.frame = view.bounds
    view.addSubview(scrollView)
    addChild(appBarViewController)
    view.addSubview(appBarViewController.view)
    appBarViewController.didMove(toParent: self)
    appBarViewController.headerView.observesTrackingScrollViewScrollEvents = true
    configureTabBar()
    configureScrollView()
  }

  override public var childForStatusBarStyle: UIViewController? {
    return appBarViewController
  }

  private func configureTabBar() {
    tabBar.items = viewControllers.map { (viewController) -> UITabBarItem in
      return UITabBarItem(title: viewController.title, image: nil, tag: 0)
    }
  }

  private func configureScrollView() {
    let bounds = scrollView.bounds
    scrollView.contentSize = CGSize(
      width: CGFloat(viewControllers.count) * bounds.size.width,
      height: bounds.size.height
    )
    for i in 0 ..< viewControllers.count {
      let viewController = viewControllers[i]
      viewController.view.frame = frameForIndex(i)
      addChild(viewController)
      scrollView.addSubview(viewController.view)
      viewController.didMove(toParent: self)
      // Set MDCFlexibleHeaderView.trackingScrollView so the proper contentInset gets applied
      // to account for the header.
      if let scrollView = viewController as? UIScrollViewForTracking {
        appBarViewController.headerView.trackingScrollView = scrollView.scrollViewForTracking
      }
    }
    if !viewControllers.isEmpty {
      setSelectedViewController(viewControllers[0], animated: false)
    }
  }

  private func frameForIndex(_ index: Int) -> CGRect {
    let bounds = scrollView.bounds
    let origin = CGPoint(x: CGFloat(index) * bounds.size.width, y: 0)
    return CGRect(origin: origin, size: bounds.size)
  }

  public func setSelectedViewController(_ viewController: UIViewController, animated: Bool) {
    guard let index = viewControllers.firstIndex(of: viewController) else { return }
    appBarViewController.navigationBar.leadingBarButtonItem =
      viewController.navigationItem.leftBarButtonItem
    appBarViewController.navigationBar.trailingBarButtonItem =
      viewController.navigationItem.rightBarButtonItem
    if let scrollView = viewController as? UIScrollViewForTracking {
      appBarViewController.headerView.trackingScrollView = scrollView.scrollViewForTracking
    } else {
      appBarViewController.headerView.trackingScrollView = nil
    }
    scrollView.scrollRectToVisible(frameForIndex(index), animated: animated)
  }
}

extension ScrollingTopTabBarViewController: MDCTabBarDelegate {
  public func tabBar(_ tabBar: MDCTabBar, didSelect item: UITabBarItem) {
    guard let index = tabBar.items.firstIndex(of: item),
          viewControllers.completeRange.contains(index)
          else { return }
    setSelectedViewController(viewControllers[index], animated: true)
  }
}
