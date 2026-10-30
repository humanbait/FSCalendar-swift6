import UIKit

/// Pinned content above the agenda, matching a calendar hosted in native scrolling chrome.
@MainActor final class ConnectedRangeChromeView: UIVisualEffectView {
    let scrollEdgeContainerView = UIView()
    private var separatorHeight: NSLayoutConstraint!

    init(scrollView: UIScrollView) {
        let surfaceEffect: UIVisualEffect?
        if #available(iOS 26.0, *) {
            surfaceEffect = nil // The agenda's native edge effect supplies the material.
        } else {
            surfaceEffect = UIBlurEffect(style: .regular)
        }
        super.init(effect: surfaceEffect)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.clipsToBounds = true
        clipsToBounds = true
        accessibilityIdentifier = "connected-range-chrome"

        // Scrolling dates and month fills are siblings of this fixed boundary, so
        // they do not change the native effect's shape. Keep colors outside vibrancy.
        scrollEdgeContainerView.translatesAutoresizingMaskIntoConstraints = false
        scrollEdgeContainerView.backgroundColor = .clear
        scrollEdgeContainerView.isUserInteractionEnabled = false
        scrollEdgeContainerView.accessibilityElementsHidden = true
        contentView.addSubview(scrollEdgeContainerView)
        NSLayoutConstraint.activate([
            scrollEdgeContainerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollEdgeContainerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollEdgeContainerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollEdgeContainerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        // A stable image edge also works on versions that inspect the descendants.
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }.withRenderingMode(.alwaysTemplate)
        let separator = UIImageView(image: image)
        separator.tintColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        scrollEdgeContainerView.addSubview(separator)
        separatorHeight = separator.heightAnchor.constraint(equalToConstant: 1 / max(1, traitCollection.displayScale))
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: scrollEdgeContainerView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: scrollEdgeContainerView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: scrollEdgeContainerView.bottomAnchor),
            separatorHeight
        ])
        if #available(iOS 26.0, *) {
            scrollView.topEdgeEffect.style = .hard
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.scrollView = scrollView
            interaction.edge = .top
            scrollEdgeContainerView.addInteraction(interaction)
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(scrollView:)") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        separatorHeight.constant = 1 / max(1, traitCollection.displayScale)
    }
}
