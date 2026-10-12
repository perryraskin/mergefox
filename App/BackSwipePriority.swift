import SwiftUI
import UIKit

/// Let the native edge-back gesture win over horizontal diff/filename scrolling.
/// Interior drags still belong to the scroll view; root share-sheet viewers
/// have no navigation pop gesture to prioritize.
struct BackSwipePriority: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView(); view.isUserInteractionEnabled = false; return view
    }
    func updateUIView(_ view: ProbeView, context: Context) { view.install() }

    final class ProbeView: UIView {
        private weak var registeredPan: UIGestureRecognizer?
        private weak var registeredPop: UIGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.install() }
        }
        override func layoutSubviews() { super.layoutSubviews(); install() }

        func install() {
            guard window != nil else { return }
            var ancestor = superview
            var scroll: UIScrollView?
            while let view = ancestor {
                if let value = view as? UIScrollView { scroll = value; break }
                ancestor = view.superview
            }
            var responder: UIResponder? = self
            var navigation: UINavigationController?
            while let current = responder {
                if let controller = current as? UIViewController,
                   let value = controller.navigationController { navigation = value; break }
                responder = current.next
            }
            guard let scroll, let navigation, navigation.viewControllers.count > 1,
                  let pop = navigation.interactivePopGestureRecognizer,
                  registeredPan !== scroll.panGestureRecognizer || registeredPop !== pop else { return }
            scroll.panGestureRecognizer.require(toFail: pop)
            if #available(iOS 26.0, *), let contentPop = navigation.interactiveContentPopGestureRecognizer {
                ContentPopDelegate.register(scroll, navigation: navigation, gesture: contentPop)
                scroll.panGestureRecognizer.require(toFail: contentPop)
            }
            registeredPan = scroll.panGestureRecognizer; registeredPop = pop
        }
    }

    /// iOS 26's content-wide pop must yield to interior code drags. Forward
    /// every other delegate decision to UIKit rather than replacing its rules.
    private final class ContentPopDelegate: NSObject, UIGestureRecognizerDelegate {
        private static let delegates = NSMapTable<UINavigationController, ContentPopDelegate>.weakToStrongObjects()
        private weak var original: UIGestureRecognizerDelegate?
        private let scrollViews = NSHashTable<UIScrollView>.weakObjects()

        static func register(_ scroll: UIScrollView, navigation: UINavigationController, gesture: UIGestureRecognizer) {
            let proxy: ContentPopDelegate
            if let existing = delegates.object(forKey: navigation) { proxy = existing }
            else { proxy = ContentPopDelegate(); delegates.setObject(proxy, forKey: navigation) }
            if gesture.delegate !== proxy { proxy.original = gesture.delegate; gesture.delegate = proxy }
            proxy.scrollViews.add(scroll)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if let view = gestureRecognizer.view {
                let point = touch.location(in: view)
                let leadingDistance = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? view.bounds.width - point.x : point.x
                if leadingDistance > 24 && scrollViews.allObjects.contains(where: {
                    $0.window != nil && $0.convert($0.bounds, to: view).contains(point)
                }) { return false }
            }
            return original?.gestureRecognizer?(gestureRecognizer, shouldReceive: touch) ?? true
        }
        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (original?.responds(to: selector) ?? false)
        }
        override func forwardingTarget(for selector: Selector!) -> Any? {
            if original?.responds(to: selector) == true { return original }
            return super.forwardingTarget(for: selector)
        }
    }
}
