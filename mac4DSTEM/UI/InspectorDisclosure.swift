//
//  InspectorDisclosure.swift
//  An inspector's "Advanced" group that opens on its whole row. SwiftUI's `DisclosureGroup` on macOS opens on the
//  triangle only: a click on the word beside it did nothing (seen driving Crystal Maps, 5.3.0 walk).
//

import SwiftUI

struct InspectorDisclosure<Content: View>: View {
    private let title: String
    @Binding private var isExpanded: Bool
    private let content: Content

    init(_ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
        }
    }
}
