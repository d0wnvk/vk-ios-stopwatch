import Combine
import MobileVLCKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DestinationFolderPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onSelect: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.folder],
            asCopy: false
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: DestinationFolderPicker

        init(parent: DestinationFolderPicker) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            guard let destination = urls.first else { return }
            parent.isPresented = false
            parent.onSelect(destination)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}



struct VLCPlayerView: UIViewRepresentable {
    let controller: VLCPlayerController

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        controller.attachPhoneView(view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        controller.attachPhoneView(uiView)
    }
}

