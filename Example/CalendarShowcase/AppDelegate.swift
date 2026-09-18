import CalendarDemoSupport
import UIKit

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
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
        return true
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
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { DemoScenario.allCases.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "scenario", for: indexPath)
        let scenario = DemoScenario.allCases[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = scenario.title
        content.image = UIImage(systemName: "calendar")
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "scenario.\(scenario.rawValue)"
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        navigationController?.pushViewController(ScenarioController(scenario: DemoScenario.allCases[indexPath.row]), animated: true)
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
        let stack = UIStackView(arrangedSubviews: [controls, driver.view, pageLabel, selectionLabel, eventLabel, table])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        if scenario == .largeText {
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
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); updateState() }
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
        cell.contentConfiguration = content
        return cell
    }
}
