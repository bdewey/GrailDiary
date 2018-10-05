// Copyright © 2018 Brian's Brain. All rights reserved.

import AVFoundation
import CommonplaceBook
import MaterialComponents
import SnapKit
import UIKit

// TODO: Find commmon code with VocabularyAssociationCardView and create a single reusable class?

final class ClozeCardView: CardView {
  init(card: ClozeCard, stylesheet: Stylesheet) {
    self.card = card
    super.init(frame: .zero)
    self.addSubview(columnStack)
    columnStack.snp.makeConstraints { (make) in
      make.edges.equalToSuperview().inset(16)
    }

    self.addTarget(self, action: #selector(revealAnswer), for: .touchUpInside)

    contextLabel.attributedText = card.context(with: stylesheet)
    frontLabel.attributedText = card.cardFront(with: stylesheet)
    backLabel.attributedText = card.cardBack(with: stylesheet)
    setAnswerVisible(false, animated: false)
  }

  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private let card: ClozeCard

  private func setAnswerVisible(_ answerVisible: Bool, animated: Bool) {
    let animations = {
      UIView.performWithoutAnimation {
        self.frontLabel.isHidden = answerVisible
      }
      self.backLabel.isHidden = !answerVisible
      self.gotItButton.isHidden = !answerVisible
      self.buttonRow.isHidden = !answerVisible
      self.studyMoreButton.isHidden = !answerVisible
      self.columnStack.isUserInteractionEnabled = answerVisible
      self.setNeedsLayout()
      if animated { self.layoutIfNeeded() }
    }
    if animated {
      UIView.animate(withDuration: 0.2, animations: animations, completion: { (_) in
        self.didTapPronounce()
      })
    } else {
      animations()
    }
  }

  private lazy var columnStack: UIStackView = {
    let columnStack = UIStackView(
      arrangedSubviews: [contextLabel, frontLabel, backLabel, buttonRow]
    )
    columnStack.axis = .vertical
    columnStack.alignment = .leading
    columnStack.spacing = 8
    return columnStack
  }()

  private lazy var buttonRow: UIStackView = {
    let buttonRow = UIStackView(arrangedSubviews: [gotItButton, studyMoreButton])
    buttonRow.axis = .horizontal
    buttonRow.spacing = 8
    return buttonRow
  }()

  private let contextLabel: UILabel = {
    let contextLabel = UILabel(frame: .zero)
    contextLabel.numberOfLines = 0
    contextLabel.textAlignment = .center
    contextLabel.isUserInteractionEnabled = false
    return contextLabel
  }()

  private let frontLabel: UILabel = {
    let frontLabel = UILabel(frame: .zero)
    frontLabel.numberOfLines = 0
    frontLabel.textAlignment = .center
    frontLabel.isUserInteractionEnabled = false
    return frontLabel
  }()

  private let backLabel: UILabel = {
    let backLabel = UILabel(frame: .zero)
    backLabel.numberOfLines = 0
    backLabel.textAlignment = .center
    backLabel.isUserInteractionEnabled = false
    return backLabel
  }()

  private lazy var gotItButton: MDCButton = {
    let button = MDCButton(frame: .zero)
    MDCContainedButtonThemer.applyScheme(Stylesheet.hablaEspanol.buttonScheme, to: button)
    button.setTitle("Got it", for: .normal)
    button.addTarget(self, action: #selector(didTapGotIt), for: .touchUpInside)
    return button
  }()

  private lazy var studyMoreButton: MDCButton = {
    let button = MDCButton(frame: .zero)
    MDCTextButtonThemer.applyScheme(Stylesheet.hablaEspanol.buttonScheme, to: button)
    button.setTitle("Study More", for: .normal)
    button.addTarget(self, action: #selector(didTapStudyMore), for: .touchUpInside)
    return button
  }()

  private lazy var prounounceSpanishButton: MDCButton = {
    let button = MDCButton(frame: .zero)
    MDCTextButtonThemer.applyScheme(Stylesheet.hablaEspanol.buttonScheme, to: button)
    button.setTitle("Say it", for: .normal)
    button.addTarget(self, action: #selector(didTapPronounce), for: .touchUpInside)
    return button
  }()

  @objc private func revealAnswer() {
    setAnswerVisible(true, animated: true)
  }

  @objc private func didTapGotIt() {
    delegate?.cardView(self, didAnswerCorrectly: true)
  }

  @objc private func didTapStudyMore() {
    delegate?.cardView(self, didAnswerCorrectly: false)
  }

  @objc private func didTapPronounce() {
    delegate?.cardView(self, didRequestSpeech: card.utterance)
  }
}