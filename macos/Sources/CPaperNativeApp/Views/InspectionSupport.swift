import Combine
import SwiftUI

@MainActor
final class Inspection<V>: @unchecked Sendable {
    let notice = PassthroughSubject<UInt, Never>()
    var callbacks = [UInt: (V) -> Void]()

    func visit(_ view: V, _ line: UInt) {
        if let callback = callbacks.removeValue(forKey: line) {
            callback(view)
        }
    }
}

extension View {
    func inspectableSheet<Sheet: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Sheet
    ) -> some View {
        modifier(
            InspectableSheet(
                isPresented: isPresented,
                onDismiss: onDismiss,
                popupBuilder: content
            )
        )
    }

    func inspectablePopover<Popover: View>(
        isPresented: Binding<Bool>,
        attachmentAnchor: PopoverAttachmentAnchor = .rect(.bounds),
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping () -> Popover
    ) -> some View {
        modifier(
            InspectablePopover(
                isPresented: isPresented,
                attachmentAnchor: attachmentAnchor,
                arrowEdge: arrowEdge,
                popupBuilder: content
            )
        )
    }
}

struct InspectableSheet<Sheet: View>: ViewModifier {
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let popupBuilder: () -> Sheet

    func body(content: Content) -> some View {
        content.sheet(isPresented: isPresented, onDismiss: onDismiss, content: popupBuilder)
    }
}

struct InspectablePopover<Popover: View>: ViewModifier {
    let isPresented: Binding<Bool>
    let attachmentAnchor: PopoverAttachmentAnchor
    let arrowEdge: Edge
    let popupBuilder: () -> Popover
    let onDismiss: (() -> Void)? = nil

    func body(content: Content) -> some View {
        content.popover(
            isPresented: isPresented,
            attachmentAnchor: attachmentAnchor,
            arrowEdge: arrowEdge,
            content: popupBuilder
        )
    }
}
