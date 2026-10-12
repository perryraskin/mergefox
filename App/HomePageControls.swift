import SwiftUI

struct HomePageControls: View {
    let section: String
    let page: Int
    let hasNext: Bool
    let loading: Bool
    let select: (Int) -> Void

    var body: some View {
        HStack {
            Button { select(page - 1) } label: { Label("Previous", systemImage: "chevron.left") }
                .disabled(page <= 1 || loading)
                .accessibilityLabel("Previous page of \(section)")
            Spacer(minLength: 4)
            Text("Page \(page)").font(.caption).foregroundStyle(PajamasTheme.secondary)
            Spacer(minLength: 4)
            Button { select(page + 1) } label: { Label("Next", systemImage: "chevron.right") }
                .disabled(!hasNext || loading)
                .accessibilityLabel("Next page of \(section)")
        }
        .font(.caption.weight(.semibold))
        .buttonStyle(PajamasDefaultButtonStyle())
        .padding(.top, 4)
    }
}
