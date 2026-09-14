import Flutter
import UIKit

/// UIKit supplies Liquid Glass on iOS 26+ and its system appearance on older iOS.
/// Do not override the tab bar's material or the system's transparency preference.
final class NativeControlsFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        NativeControlsView(frame: frame, id: viewId, messenger: messenger,
                           configuration: args as? [String: Any] ?? [:])
    }
}

private final class NativeControlContainer: UIView {
    var control: UIView?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let control else { return }
        if let tabBar = control as? UITabBar {
            // Keep the native safe-area inset: UIKit positions its floating pill.
            let height = tabBar.sizeThatFits(bounds.size).height
            tabBar.frame = CGRect(x: 0, y: max(0, bounds.height - height),
                                  width: bounds.width, height: height)
        } else {
            control.frame = bounds
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }
}

private final class NativeControlsView: NSObject, FlutterPlatformView, UITabBarDelegate {
    private let container: NativeControlContainer
    private let channel: FlutterMethodChannel
    private var tabBar: UITabBar?
    private var button: UIButton?
    private var badge: UIView?
    private var configuration: [String: Any] = [:]
    private var pendingAction = false
    private var itemLabels: [String] = []
    private var itemSymbols: [String] = []

    init(frame: CGRect, id: Int64, messenger: FlutterBinaryMessenger,
         configuration: [String: Any]) {
        container = NativeControlContainer(frame: frame)
        channel = FlutterMethodChannel(name: "com.delta.strnadi/native-controls/\(id)",
                                       binaryMessenger: messenger)
        super.init()
        container.backgroundColor = .clear
        container.clipsToBounds = false
        if configuration["kind"] as? String == "tabs" {
            let bar = UITabBar()
            bar.delegate = self
            // Default UIKit appearance is essential for native Liquid Glass,
            // including Clear/Tinted and Reduce Transparency changes at runtime.
            tabBar = bar
            container.control = bar
            container.addSubview(bar)
        } else {
            let control = UIButton(type: .system)
            control.addTarget(self, action: #selector(buttonPressed), for: .touchUpInside)
            button = control
            container.control = control
            container.addSubview(control)
        }
        update(configuration)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(nil); return }
            guard call.method == "update", let values = call.arguments as? [String: Any] else {
                result(FlutterMethodNotImplemented)
                return
            }
            self.update(values)
            result(nil)
        }
    }

    deinit { channel.setMethodCallHandler(nil) }

    func view() -> UIView { container }

    private func update(_ values: [String: Any]) {
        configuration = values
        if let tabBar {
            let labels = values["labels"] as? [String] ?? []
            let symbols = values["symbols"] as? [String] ?? []
            if labels != itemLabels || symbols != itemSymbols {
                itemLabels = labels
                itemSymbols = symbols
                tabBar.items = labels.enumerated().map { index, label in
                    let symbol = index < symbols.count ? symbols[index] : "circle"
                    return UITabBarItem(title: label, image: UIImage(systemName: symbol), tag: index)
                }
            }
            let index = values["selectedIndex"] as? Int ?? -1
            tabBar.selectedItem = tabBar.items?.first { $0.tag == index }
        }
        if let button {
            var style: UIButton.Configuration
            if #available(iOS 26.0, *) {
                style = .glass()
            } else {
                style = .gray()
            }
            style.cornerStyle = .capsule
            style.contentInsets = NSDirectionalEdgeInsets(
                top: 12, leading: 12, bottom: 12, trailing: 12
            )
            style.image = UIImage(systemName: values["symbol"] as? String ?? "xmark")
            style.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            button.configuration = style
            button.isEnabled = values["enabled"] as? Bool ?? false
            button.accessibilityLabel = values["label"] as? String
            badge?.removeFromSuperview()
            badge = nil
            if values["badge"] as? Bool == true {
                let dot = UIView()
                dot.backgroundColor = .systemRed
                dot.layer.cornerRadius = 4
                dot.isUserInteractionEnabled = false
                dot.isAccessibilityElement = false
                dot.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(dot)
                NSLayoutConstraint.activate([
                    dot.widthAnchor.constraint(equalToConstant: 8),
                    dot.heightAnchor.constraint(equalToConstant: 8),
                    dot.topAnchor.constraint(equalTo: button.topAnchor, constant: 10),
                    dot.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -10),
                ])
                badge = dot
            }
        }
        container.setNeedsLayout()
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        let committed = configuration["selectedIndex"] as? Int ?? -1
        guard !pendingAction else {
            tabBar.selectedItem = tabBar.items?.first { $0.tag == committed }
            return
        }
        guard item.tag != committed else { return }
        // Let UIKit animate its floating selection. Flutter returns the committed
        // index after its guards; cancellation restores the original selection.
        activate(item.tag)
    }

    @objc private func buttonPressed() { activate(0) }

    private func activate(_ index: Int) {
        guard !pendingAction else { return }
        pendingAction = true
        channel.invokeMethod("activate", arguments: index) { [weak self] response in
            guard let self else { return }
            self.pendingAction = false
            if let values = response as? [String: Any] { self.update(values) }
        }
    }
}
