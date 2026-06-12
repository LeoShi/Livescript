import AppKit
import SwiftUI

struct SelectableTranscriptTextView: NSViewRepresentable {
    let attributedText: NSAttributedString

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textView = makeTextView()
        scrollView.documentView = textView
        context.coordinator.scrollView = scrollView

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        textView.textStorage?.setAttributedString(attributedText)
        resizeDocumentView(textView, in: scrollView)
        scrollToBottom(scrollView)
        context.coordinator.followBottom = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let contentChanged = textView.string != attributedText.string
        guard contentChanged else { return }

        let shouldFollow = context.coordinator.followBottom
        textView.textStorage?.setAttributedString(attributedText)
        resizeDocumentView(textView, in: scrollView)

        if shouldFollow {
            scrollToBottom(scrollView)
            DispatchQueue.main.async {
                scrollToBottom(scrollView)
            }
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    private func makeTextView() -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        if let container = textView.textContainer {
            container.lineFragmentPadding = 0
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }
        textView.font = .preferredFont(forTextStyle: .body)
        return textView
    }

    private func resizeDocumentView(_ textView: NSTextView, in scrollView: NSScrollView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)
        let inset = textView.textContainerInset
        let width = max(scrollView.contentSize.width, 1)
        let height = max(used.height + inset.height * 2, scrollView.contentSize.height)
        textView.setFrameSize(NSSize(width: width, height: height))
    }

    private func scrollToBottom(_ scrollView: NSScrollView) {
        guard let documentView = scrollView.documentView else { return }

        scrollView.layoutSubtreeIfNeeded()
        if let textView = documentView as? NSTextView,
           let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }

        let clipView = scrollView.contentView
        let targetY = max(0, documentView.frame.height - clipView.bounds.height)
        clipView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(clipView)
    }

    final class Coordinator: NSObject {
        weak var scrollView: NSScrollView?
        var followBottom = true

        @objc func scrollViewDidScroll(_ notification: Notification) {
            guard let clipView = notification.object as? NSClipView,
                  let scrollView,
                  let documentView = scrollView.documentView else { return }

            let maxY = max(0, documentView.frame.height - clipView.bounds.height)
            let distanceFromBottom = maxY - clipView.bounds.origin.y
            followBottom = distanceFromBottom <= 48
        }
    }
}
