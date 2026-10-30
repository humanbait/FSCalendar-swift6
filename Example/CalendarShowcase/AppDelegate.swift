import CalendarDemoSupport
import UIKit

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var showcaseWindow: UIWindow? {
        UIApplication.shared.connectedScenes.compactMap { ($0.delegate as? SceneDelegate)?.window }.first
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Calendar Lab", sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        // Keep UI-test captures independent of the device's current appearance.
        switch ProcessInfo.processInfo.environment["FSCALENDAR_TEST_APPEARANCE"] {
        case "light": window.overrideUserInterfaceStyle = .light
        case "dark": window.overrideUserInterfaceStyle = .dark
        default: break
        }
        let arguments = ProcessInfo.processInfo.arguments
        func argument(_ name: String) -> String? {
            guard let i = arguments.firstIndex(of: name), arguments.indices.contains(i + 1) else { return nil }
            return arguments[i + 1]
        }
        let root = ScenarioListController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.navigationBar.prefersLargeTitles = true
        if let name = argument("--scenario"), let scenario = DemoScenario(rawValue: name) {
            navigation.pushViewController(ScenarioController(scenario: scenario), animated: false)
        }
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        self.window = window
    }
}

@MainActor
final class ScenarioListController: UITableViewController {
    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("Use init()") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Calendar Lab"
        tableView.accessibilityIdentifier = "scenarios"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "scenario")
    }
    override func numberOfSections(in tableView: UITableView) -> Int { DemoScenario.groups.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        DemoScenario.groups[section].title
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        DemoScenario.groups[section].scenarios.count
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "scenario", for: indexPath)
        let scenario = DemoScenario.groups[indexPath.section].scenarios[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = scenario.title
        content.image = UIImage(systemName: "calendar")
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "scenario.\(scenario.rawValue)"
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let scenario = DemoScenario.groups[indexPath.section].scenarios[indexPath.row]
        navigationController?.pushViewController(ScenarioController(scenario: scenario), animated: true)
    }
}

@MainActor
final class ScenarioController: UIViewController, UITableViewDataSource, UIGestureRecognizerDelegate {
    let scenario: DemoScenario
    let driver: any UIKitCalendarDemoDriver
    private let pageLabel = UILabel()
    private let selectionLabel = UILabel()
    private let eventLabel = UILabel()
    private let table = UITableView(frame: .zero, style: .plain)
    private var heightConstraint: NSLayoutConstraint!
    private var connectedRangeChrome: ConnectedRangeChromeView?

    init(scenario: DemoScenario) {
        self.scenario = scenario
        self.driver = SwiftCalendarDriver(scenario: scenario)
        super.init(nibName: nil, bundle: nil)
        title = scenario.title
    }
    required init?(coder: NSCoder) { fatalError("Use init(scenario:)") }
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if scenario == .largeText {
            parent?.setOverrideTraitCollection(UITraitCollection(preferredContentSizeCategory: .accessibilityMedium), forChild: self)
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        if scenario == .dark { overrideUserInterfaceStyle = .dark }
        if scenario == .rtl { view.semanticContentAttribute = .forceRightToLeft }
        let controls = UIStackView(arrangedSubviews: [button("Previous", action: #selector(previousPage)), button("Next", action: #selector(nextPage)), button("Scope", action: #selector(scope)), button("Reset", action: #selector(reset))])
        controls.distribution = .fillEqually
        controls.spacing = 6
        let stack = UIStackView(arrangedSubviews: [controls, driver.view, pageLabel, selectionLabel, eventLabel])
        if scenario != .connectedRange { stack.addArrangedSubview(table) }
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        if scenario == .connectedRange {
            configureConnectedRangeLayout(stack)
        } else if scenario == .largeText {
            scroll.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(scroll); scroll.addSubview(stack)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
                stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -12),
                stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
                stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -8),
                stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -24),
                table.heightAnchor.constraint(equalToConstant: 200)
            ])
        } else {
            view.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
                stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
                stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
        }
        heightConstraint = driver.view.heightAnchor.constraint(equalToConstant: driver.initialHeight)
        heightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            controls.heightAnchor.constraint(equalToConstant: 42), heightConstraint,
            table.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
        for (label, id) in [(pageLabel, "page-state"), (selectionLabel, "selection-state"), (eventLabel, "event-state")] {
            label.font = .preferredFont(forTextStyle: .caption1)
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 2
            label.accessibilityIdentifier = id
            label.setContentCompressionResistancePriority(.required, for: .vertical)
        }
        table.dataSource = self
        table.accessibilityIdentifier = "agenda"
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        driver.onChange = { [weak self] in self?.updateState() }
        driver.onHeightChange = { [weak self] height, _ in
            guard let self else { return }
            self.heightConstraint.constant = height
            self.view.layoutIfNeeded()
            self.updateState()
        }
        if scenario == .scope {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            pan.delegate = self
            view.addGestureRecognizer(pan)
        }
        updateState()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateState()
        updateAgendaInsets()
    }

    private func configureConnectedRangeLayout(_ stack: UIStackView) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        navigationItem.standardAppearance = appearance
        navigationItem.scrollEdgeAppearance = appearance
        navigationItem.compactAppearance = appearance
        navigationItem.compactScrollEdgeAppearance = appearance

        table.translatesAutoresizingMaskIntoConstraints = false
        table.contentInsetAdjustmentBehavior = .never
        table.automaticallyAdjustsScrollIndicatorInsets = false
        table.backgroundColor = .systemBackground
        view.addSubview(table)
        setContentScrollView(table, for: .top)

        let chrome = ConnectedRangeChromeView(scrollView: table)
        connectedRangeChrome = chrome
        chrome.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chrome)
        chrome.contentView.addSubview(stack)
        chrome.contentView.bringSubviewToFront(chrome.scrollEdgeContainerView)
        NSLayoutConstraint.activate([
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            chrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: view.topAnchor),
            chrome.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 10),
            // Allow the calendar viewport to shrink on short landscape screens.
            chrome.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -80),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
        ])
    }

    private func updateAgendaInsets() {
        guard let chrome = connectedRangeChrome else { return }
        let insets = UIEdgeInsets(top: chrome.frame.maxY - table.frame.minY, left: 0,
                                  bottom: view.safeAreaInsets.bottom, right: 0)
        guard table.contentInset != insets else { return }
        // Keep the same agenda position as the pinned header resizes in the
        // calendar's existing animation, including a list already scrolled down.
        let position = table.contentOffset.y + table.contentInset.top
        table.contentInset = insets
        table.verticalScrollIndicatorInsets = insets
        table.setContentOffset(CGPoint(x: table.contentOffset.x, y: position - insets.top), animated: false)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pageLabel.accessibilityValue = view.bounds.width > view.bounds.height ? "landscape" : "portrait"
    }
    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        pageLabel.accessibilityValue = "rotating"
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.pageLabel.accessibilityValue = size.width > size.height ? "landscape" : "portrait"
        }
    }
    private func button(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = title.lowercased()
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
    private func updateState() {
        let state = driver.state
        pageLabel.text = "Page: \(DemoFixtures.text(state.page)) | Scope: \(state.scope)"
        selectionLabel.text = "Selected: " + (state.selection.isEmpty ? "none" : state.selection.map(DemoFixtures.text).joined(separator: ", "))
        eventLabel.text = "Events: " + (state.events.suffix(2).joined(separator: " | "))
    }
    @objc private func previousPage() { driver.navigate(-1) }
    @objc private func nextPage() { driver.navigate(1) }
    @objc private func scope() { driver.toggleScope() }
    @objc private func reset() { driver.reset() }
    @objc private func pan(_ sender: UIPanGestureRecognizer) { driver.handleScopeGesture(sender) }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x) && (table.contentOffset.y <= 0 || velocity.y < 0)
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 30 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = "Agenda item \(indexPath.row + 1)"
        content.secondaryText = "Scroll to exercise calendar and list coordination"
        if scenario == .connectedRange {
            let colors: [UIColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPink]
            content.image = UIImage(systemName: "checkmark.circle.fill")
            content.imageProperties.tintColor = colors[indexPath.row % colors.count]
        }
        cell.contentConfiguration = content
        return cell
    }
}
