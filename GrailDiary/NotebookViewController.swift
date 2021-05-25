// Copyright (c) 2018-2021  Brian Dewey. Covered by the Apache 2.0 license.

import Logging
import SnapKit
import UIKit

/// Protocol for any UIViewController that displays "reference" material for which we can also show related notes
protocol ReferenceViewController: UIViewController {
  var relatedNotesViewController: UIViewController? { get set }
}

public extension UIViewController {
  /// Walks up parent view controllers to find one that is a NotebookViewController.
  var notebookViewController: NotebookViewController? {
    findParent(where: { $0 is NotebookViewController }) as? NotebookViewController
  }

  func findParent(where predicate: (UIViewController) -> Bool) -> UIViewController? {
    var currentViewController: UIViewController? = self
    while currentViewController != nil {
      // See the line above, we know this is non-nil
      if predicate(currentViewController!) {
        return currentViewController
      }
      currentViewController = currentViewController?.parent ?? currentViewController?.presentingViewController
    }
    return nil
  }
}

/// Manages the UISplitViewController that shows the contents of a notebook. It's a three-column design:
/// - primary: The overall notebook structure (currently based around hashtags)
/// - supplementary: A list of notes
/// - secondary: An individual note
public final class NotebookViewController: UIViewController {
  init(database: NoteDatabase) {
    self.database = database
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// The notebook we are viewing
  private let database: NoteDatabase

  public var fileURL: URL { database.fileURL }

  /// What are we viewing in the current structure?
  // TODO: Get rid of this copy, just read from documentListViewController
  private var focusedNotebookStructure: NotebookStructureViewController.StructureIdentifier = .read {
    didSet {
      documentListViewController.focusedStructure = focusedNotebookStructure
      if notebookSplitViewController.isCollapsed {
        let compactListViewController = DocumentListViewController(database: database)
        compactListViewController.focusedStructure = focusedNotebookStructure
        compactNavigationController.pushViewController(compactListViewController, animated: true)
      }
    }
  }

  public func setSecondaryViewController(_ viewController: NotebookSecondaryViewController, pushIfCollapsed: Bool) {
    if notebookSplitViewController.isCollapsed {
      if pushIfCollapsed {
        if compactNavigationController.viewControllers.count < 3 {
          compactNavigationController.pushViewController(viewController, animated: true)
        } else {
          compactNavigationController.popToViewController(compactNavigationController.viewControllers[1], animated: true)
          compactNavigationController.pushViewController(viewController, animated: true)
        }
      }
    } else {
      notebookSplitViewController.setViewController(UINavigationController.notebookNavigationController(rootViewController: viewController), for: .secondary)
    }
  }

  public func pushSecondaryViewController(_ viewController: UIViewController) {
    if notebookSplitViewController.isCollapsed {
      compactNavigationController.pushViewController(viewController, animated: true)
    } else {
      notebookSplitViewController.setViewController(viewController, for: .secondary)
    }
  }

  private lazy var primaryNavigationController = UINavigationController.notebookNavigationController(rootViewController: structureViewController, prefersLargeTitles: true)

  private lazy var structureViewController = makeStructureViewController()

  private func makeStructureViewController() -> NotebookStructureViewController {
    let structureViewController = NotebookStructureViewController(
      database: documentListViewController.database
    )
    structureViewController.delegate = self
    return structureViewController
  }

  /// A list of notes inside the notebook, displayed in the supplementary column
  private lazy var documentListViewController: DocumentListViewController = {
    let documentListViewController = DocumentListViewController(database: database)
    return documentListViewController
  }()

  private lazy var compactNavigationController = UINavigationController.notebookNavigationController(rootViewController: makeStructureViewController(), prefersLargeTitles: true)

  /// The split view we are managing.
  private lazy var notebookSplitViewController: UISplitViewController = {
    let supplementaryNavigationController = UINavigationController.notebookNavigationController(rootViewController: documentListViewController)

    let splitViewController = UISplitViewController(style: .tripleColumn)
    splitViewController.setViewController(primaryNavigationController, for: .primary)
    splitViewController.setViewController(supplementaryNavigationController, for: .supplementary)
    splitViewController.setViewController(
      UINavigationController.notebookNavigationController(rootViewController: SavingTextEditViewController(database: database)),
      for: .secondary
    )
    splitViewController.setViewController(compactNavigationController, for: .compact)
    splitViewController.preferredDisplayMode = .oneBesideSecondary
    splitViewController.showsSecondaryOnlyButton = true
    splitViewController.delegate = self
    return splitViewController
  }()

  override public func viewDidLoad() {
    super.viewDidLoad()

    // Set up notebookSplitViewController as a child
    view.addSubview(notebookSplitViewController.view)
    notebookSplitViewController.view.snp.makeConstraints { make in
      make.edges.equalToSuperview()
    }
    addChild(notebookSplitViewController)
    notebookSplitViewController.didMove(toParent: self)
    configureKeyCommands()
  }

  override public var canBecomeFirstResponder: Bool { true }

  private func configureKeyCommands() {
    let newNoteCommand = UIKeyCommand(
      title: "New Note",
      action: #selector(makeNewNote),
      input: "n",
      modifierFlags: [.command]
    )
    addKeyCommand(newNoteCommand)

    let focusTagsCommand = UIKeyCommand(
      title: "View Tags",
      action: #selector(tagsBecomeFirstResponder),
      input: "1",
      modifierFlags: [.command]
    )
    addKeyCommand(focusTagsCommand)

    let focusNotesCommand = UIKeyCommand(
      title: "View Notes",
      action: #selector(notesBecomeFirstResponder),
      input: "2",
      modifierFlags: [.command]
    )
    addKeyCommand(focusNotesCommand)

    let searchKeyCommand = UIKeyCommand(
      title: "Find",
      action: #selector(searchBecomeFirstResponder),
      input: "f",
      modifierFlags: [.command]
    )
    addKeyCommand(searchKeyCommand)

    let toggleEditModeCommand = UIKeyCommand(
      title: "Toggle Edit Mode",
      action: #selector(toggleEditMode),
      input: "\r",
      modifierFlags: [.command]
    )
    addKeyCommand(toggleEditModeCommand)
  }

  @objc func searchBecomeFirstResponder() {
    notebookSplitViewController.show(.supplementary)
    documentListViewController.searchBecomeFirstResponder()
  }

  @objc func tagsBecomeFirstResponder() {
    notebookSplitViewController.show(.primary)
    structureViewController.becomeFirstResponder()
  }

  @objc func notesBecomeFirstResponder() {
    notebookSplitViewController.show(.supplementary)
    documentListViewController.becomeFirstResponder()
  }

  @objc func toggleEditMode() {
    assertionFailure("Not implemented")
//    if currentNoteEditor?.isEditing ?? false {
//      currentNoteEditor?.isEditing = false
//    } else {
//      UIView.animate(withDuration: 0.2) { [notebookSplitViewController] in
//        notebookSplitViewController.preferredDisplayMode = .secondaryOnly
//      } completion: { [currentNoteEditor] success in
//        if success { _ = currentNoteEditor?.editEndOfDocument() }
//      }
//    }
  }

  @objc func makeNewNote() {
    let hashtag = focusedNotebookStructure.hashtag
    let folder = focusedNotebookStructure.predefinedFolder
    let (text, offset) = Note.makeBlankNoteText(hashtag: hashtag)
    var note = Note(markdown: text)
    note.folder = folder?.rawValue
    let viewController = SavingTextEditViewController(note: note, database: database, initialSelectedRange: NSRange(location: offset, length: 0), autoFirstResponder: true)
    setSecondaryViewController(viewController, pushIfCollapsed: true)
    Logger.shared.info("Created a new view controller for a blank document")
  }

  public func makeNewNoteButtonItem() -> UIBarButtonItem {
    var extraActions = [UIAction]()
    if let apiKey = ApiKey.googleBooks, !apiKey.isEmpty {
      let bookNoteAction = UIAction(title: "Book Note", image: UIImage(systemName: "text.book.closed"), handler: { [weak self] _ in
        let bookSearchViewController = BookSearchViewController(apiKey: apiKey)
        bookSearchViewController.delegate = self
        bookSearchViewController.title = "New Note About Book"
        let navigationController = UINavigationController(rootViewController: bookSearchViewController)
        navigationController.navigationBar.tintColor = .grailTint
        self?.present(navigationController, animated: true)
      })
      extraActions.append(bookNoteAction)
    }
    let webImporters = WebImporterConfiguration.shared.map { config -> UIAction in
      UIAction(title: config.title, image: config.image, handler: { [weak self] _ in
        guard let self = self else { return }
        let webViewController = WebScrapingViewController(initialURL: config.initialURL, javascript: config.importJavascript)
        webViewController.delegate = self
        let navigationController = UINavigationController(rootViewController: webViewController)
        navigationController.navigationBar.tintColor = .grailTint
        self.present(navigationController, animated: true, completion: nil)
      })
    }
    extraActions.append(contentsOf: webImporters)
    let menu: UIMenu? = extraActions.isEmpty ? nil : UIMenu(options: [.displayInline], children: extraActions)
    let primaryAction = UIAction { [weak self] _ in
      self?.makeNewNote()
    }
    let button = UIBarButtonItem(image: UIImage(systemName: "square.and.pencil"), primaryAction: primaryAction, menu: menu)
    button.accessibilityIdentifier = "new-document"
    return button
  }

  func showNoteEditor(noteIdentifier: Note.Identifier?, note: Note, shiftFocus: Bool) {
    let actualNoteIdentifier = noteIdentifier ?? UUID().uuidString
    let noteViewController = SavingTextEditViewController(noteIdentifier: actualNoteIdentifier, note: note, database: database)
    setSecondaryViewController(noteViewController, pushIfCollapsed: shiftFocus)
  }

  // MARK: - State restoration

  private enum ActivityKey {
    static let notebookStructure = "org.brians-brain.GrailDiary.NotebookStructure"
    static let displayMode = "org.brians-brain.GrailDiary.notebookSplitViewController.displayMode"
    static let secondaryViewControllerType = "org.brians-brain.GrailDiary.notebookSplitViewController.secondaryType"
    static let secondaryViewControllerData = "org.brians-brain.GrailDiary.notebookSplitViewController.secondaryData"
  }

  func updateUserActivity(_ userActivity: NSUserActivity) {
    userActivity.addUserInfoEntries(from: [
      ActivityKey.notebookStructure: focusedNotebookStructure.rawValue,
      ActivityKey.displayMode: notebookSplitViewController.displayMode.rawValue,
    ])
    structureViewController.updateUserActivity(userActivity)

    if let secondaryViewController = self.secondaryViewController {
      do {
        let controllerType = type(of: secondaryViewController).notebookDetailType
        userActivity.addUserInfoEntries(
          from: [
            ActivityKey.secondaryViewControllerType: controllerType,
            ActivityKey.secondaryViewControllerData: try secondaryViewController.userActivityData(),
          ]
        )
      } catch {
        Logger.shared.error("Unexpected error saving secondary VC: \(error)")
      }
    }
  }

  var secondaryViewController: NotebookSecondaryViewController? {
    secondaryViewController(forCollaped: notebookSplitViewController.isCollapsed)
  }

  func secondaryViewController(forCollaped collapsed: Bool) -> NotebookSecondaryViewController? {
    if collapsed {
      if compactNavigationController.viewControllers.count >= 3 {
        return compactNavigationController.topViewController as? NotebookSecondaryViewController
      } else {
        return nil
      }
    } else if let navigationController = notebookSplitViewController.viewController(for: .secondary) as? UINavigationController {
      return navigationController.viewControllers.first as? NotebookSecondaryViewController
    }
    return nil
  }

  func configure(with userActivity: NSUserActivity) {
    if
      let structureString = userActivity.userInfo?[ActivityKey.notebookStructure] as? String,
      let focusedNotebookStructure = NotebookStructureViewController.StructureIdentifier(rawValue: structureString)
    {
      self.focusedNotebookStructure = focusedNotebookStructure
    }
    if let rawDisplayMode = userActivity.userInfo?[ActivityKey.displayMode] as? Int,
       let displayMode = UISplitViewController.DisplayMode(rawValue: rawDisplayMode)
    {
      notebookSplitViewController.preferredDisplayMode = displayMode
    }
    structureViewController.configure(with: userActivity)

    if let secondaryViewControllerType = userActivity.userInfo?[ActivityKey.secondaryViewControllerType] as? String,
       let secondaryViewControllerData = userActivity.userInfo?[ActivityKey.secondaryViewControllerData] as? Data
    {
      do {
        let secondaryViewController = try NotebookSecondaryViewControllerRegistry.shared.reconstruct(
          type: secondaryViewControllerType,
          data: secondaryViewControllerData,
          database: database
        )
        setSecondaryViewController(secondaryViewController, pushIfCollapsed: true)
      } catch {
        Logger.shared.error("Error recovering secondary view controller: \(error)")
      }
    }
  }
}

public extension NotebookViewController {
  func pushNote(with noteIdentifier: Note.Identifier, selectedText: String? = nil, autoFirstResponder: Bool = false) {
    Logger.shared.info("Handling openNoteCommand. Note id = \(noteIdentifier)")
    do {
      let note = try database.note(noteIdentifier: noteIdentifier)
      let rawText = note.text ?? ""
      let initialRange = selectedText.flatMap { (rawText as NSString).range(of: $0) }
      let noteViewController = SavingTextEditViewController(
        noteIdentifier: noteIdentifier,
        note: note,
        database: database,
        initialSelectedRange: initialRange,
        autoFirstResponder: autoFirstResponder
      )
      setSecondaryViewController(noteViewController, pushIfCollapsed: true)
      // TODO: Figure out how to make a "push" make sense in a split view controller
      //      pushSecondaryViewController(noteViewController)
      documentListViewController.selectPage(with: noteIdentifier)
    } catch {
      Logger.shared.error("Unexpected error getting note \(noteIdentifier): \(error)")
    }
  }
}

// MARK: - WebScrapingViewControllerDelegate

extension NotebookViewController: WebScrapingViewControllerDelegate {
  public func webScrapingViewController(_ viewController: WebScrapingViewController, didScrapeMarkdown markdown: String) {
    dismiss(animated: true, completion: nil)
    Logger.shared.info("Creating a new page with markdown: \(markdown)")
    let (text, offset) = Note.makeBlankNoteText(title: markdown, hashtag: focusedNotebookStructure.hashtag)
    var note = Note(markdown: text)
    note.folder = focusedNotebookStructure.predefinedFolder?.rawValue
    // TODO: I'm abusing the "title" parameter here
    let viewController = SavingTextEditViewController(
      note: note,
      database: database,
      initialSelectedRange: NSRange(location: offset, length: 0),
      autoFirstResponder: true
    )
    setSecondaryViewController(viewController, pushIfCollapsed: true)
    Logger.shared.info("Created a new view controller for a book!")
  }

  public func webScrapingViewControllerDidCancel(_ viewController: WebScrapingViewController) {
    dismiss(animated: true, completion: nil)
  }
}

// MARK: - BookSearchViewControllerDelegate

extension NotebookViewController: BookSearchViewControllerDelegate {
  public func bookSearchViewController(_ viewController: BookSearchViewController, didSelect book: Book, coverImage: UIImage?) {
    dismiss(animated: true, completion: nil)
    let (text, offset) = Note.makeBlankNoteText(title: book.markdownTitle, hashtag: focusedNotebookStructure.hashtag)
    var note = Note(markdown: text)
    note.folder = focusedNotebookStructure.predefinedFolder?.rawValue
    let viewController = SavingTextEditViewController(
      note: note,
      database: database,
      initialSelectedRange: NSRange(location: offset, length: 0),
      initialImage: coverImage,
      autoFirstResponder: true
    )
    setSecondaryViewController(viewController, pushIfCollapsed: true)
    Logger.shared.info("Created a new view controller for a book!")
  }

  public func bookSearchViewControllerDidCancel(_ viewController: BookSearchViewController) {
    dismiss(animated: true, completion: nil)
  }
}

// MARK: - NotebookStructureViewControllerDelegate

extension NotebookViewController: NotebookStructureViewControllerDelegate {
  func notebookStructureViewController(_ viewController: NotebookStructureViewController, didSelect structure: NotebookStructureViewController.StructureIdentifier) {
    focusedNotebookStructure = structure
  }

  func notebookStructureViewControllerDidRequestChangeFocus(_ viewController: NotebookStructureViewController) {
    notebookSplitViewController.show(.supplementary)
    documentListViewController.becomeFirstResponder()
  }
}

// MARK: - DocumentListViewControllerDelegate

extension NotebookViewController {
  func documentListViewControllerDidRequestChangeFocus(_ viewController: DocumentListViewController) {
    tagsBecomeFirstResponder()
  }

  private func referenceViewController(for note: Note) -> ReferenceViewController? {
    switch note.reference {
    case .none: return nil
    case .some(.webPage(let url)):
      return WebViewController(url: url)
    }
  }
}

private extension UINavigationController {
  /// Creates a UINavigationController with the expected configuration for being a notebook navigation controller.
  static func notebookNavigationController(rootViewController: UIViewController, prefersLargeTitles: Bool = false) -> UINavigationController {
    let navigationController = HackNavigationController(
      rootViewController: rootViewController
    )
    navigationController.navigationBar.prefersLargeTitles = prefersLargeTitles
    navigationController.navigationBar.barTintColor = .grailBackground
    return navigationController
  }
}

// MARK: - UISplitViewControllerDelegate

extension NotebookViewController: UISplitViewControllerDelegate {
  public func splitViewController(
    _ svc: UISplitViewController,
    displayModeForExpandingToProposedDisplayMode proposedDisplayMode: UISplitViewController.DisplayMode
  ) -> UISplitViewController.DisplayMode {
    if let secondaryViewController = self.secondaryViewController(forCollaped: true) {
      do {
        let activityData = try secondaryViewController.userActivityData()
        let viewController = try NotebookSecondaryViewControllerRegistry.shared.reconstruct(
          type: type(of: secondaryViewController).notebookDetailType,
          data: activityData,
          database: database
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
          self.setSecondaryViewController(viewController, pushIfCollapsed: false)
        }
      } catch {
        Logger.shared.error("Unexpected error rebuilding view hierarchy")
      }
    }
    return proposedDisplayMode
  }

  public func splitViewController(
    _ svc: UISplitViewController,
    topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column
  ) -> UISplitViewController.Column {
    let compactDocumentList = DocumentListViewController(database: database)
    compactDocumentList.focusedStructure = focusedNotebookStructure
    compactNavigationController.popToRootViewController(animated: false)
    compactNavigationController.pushViewController(compactDocumentList, animated: false)

    if let secondaryViewController = self.secondaryViewController(forCollaped: false) {
      do {
        let activityData = try secondaryViewController.userActivityData()
        let viewController = try NotebookSecondaryViewControllerRegistry.shared.reconstruct(
          type: type(of: secondaryViewController).notebookDetailType,
          data: activityData,
          database: database
        )
        compactNavigationController.pushViewController(viewController, animated: false)
      } catch {
        Logger.shared.error("Unexpected error rebuilding view hierarchy")
      }
    }
    return .compact
  }
}

private final class HackNavigationController: UINavigationController {
  override func pushViewController(_ viewController: UIViewController, animated: Bool) {
    if viewController is UINavigationController {
      Logger.shared.error("What are you doing bro?")
    }
    super.pushViewController(viewController, animated: animated)
  }
}
