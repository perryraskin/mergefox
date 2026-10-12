import SwiftUI
import gitdiff

/// A flat diff surface: the MR owns vertical scrolling, each file owns horizontal scrolling.
struct EdgeDiffView: View {
    let patch: String
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric private var fontSize = 13.0
    @State private var lines: [DiffLine] = []
    @State private var loading = true
    @State private var failed = false

    private var theme: DiffTheme { colorScheme == .dark ? .dark : .light }
    private var rowHeight: CGFloat { ceil(fontSize * 1.55) }
    private var gutterWidth: CGFloat {
        let digits = String(lines.compactMap { $0.newLineNumber ?? $0.oldLineNumber }.max() ?? 1).count
        return max(32, CGFloat(digits) * fontSize * 0.61 + 10)
    }
    private var contentWidth: CGFloat {
        let font = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let longest = lines.map { ($0.content as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return ceil(longest + gutterWidth + 28)
    }

    var body: some View {
        Group {
            if loading {
                ProgressView("Preparing diff…").frame(maxWidth: .infinity).padding(16)
            } else if failed || lines.isEmpty {
                Text("Couldn’t display this diff. Open GitLab to see the changes.")
                    .font(.caption).foregroundStyle(PajamasTheme.secondary).padding(16)
            } else {
                GeometryReader { geometry in
                    let width = max(geometry.size.width, contentWidth)
                    ScrollView(.horizontal) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(lines) { line in
                                row(line, width: width)
                            }
                        }.frame(width: width).background(BackSwipePriority())
                    }
                    .accessibilityHint("Swipe horizontally to read long code lines")
                }.frame(height: CGFloat(lines.count) * rowHeight)
            }
        }
        .task(id: patch) {
            loading = true; failed = false
            do {
                let files = try await UnifiedDiffParser().parse(patch)
                guard !Task.isCancelled else { return }
                lines = files.flatMap { $0.hunks.flatMap { hunk in
                    [DiffLine(type: .header, content: hunk.header, oldLineNumber: nil, newLineNumber: nil)] + hunk.lines
                } }
            } catch {
                guard !Task.isCancelled else { return }
                lines = []; failed = true
            }
            loading = false
        }
    }

    @ViewBuilder private func row(_ line: DiffLine, width: CGFloat) -> some View {
        let background = line.type == .added ? theme.addedBackground : line.type == .removed ? theme.removedBackground : line.type == .header ? theme.headerBackground : theme.contextBackground
        HStack(spacing: 0) {
            if line.type == .header {
                Text(line.content).foregroundStyle(theme.headerText).padding(.leading, gutterWidth + 6)
            } else {
                let number = line.type == .removed ? line.oldLineNumber : line.newLineNumber ?? line.oldLineNumber
                Text(number.map(String.init) ?? "")
                    .font(.system(size: fontSize * 0.85, design: .monospaced))
                    .foregroundStyle(theme.lineNumberText)
                    .frame(width: gutterWidth, height: rowHeight, alignment: .trailing)
                    .padding(.trailing, 6)
                    .background(background)
                Text(line.type == .added ? "+" : line.type == .removed ? "−" : " ")
                    .frame(width: 12).foregroundStyle(PajamasTheme.secondary)
                Text(line.content).foregroundStyle(PajamasTheme.text)
            }
            Spacer(minLength: 8)
        }
        .font(.system(size: fontSize, design: .monospaced))
        .lineLimit(1).fixedSize(horizontal: false, vertical: true)
        .frame(width: width, height: rowHeight, alignment: .leading)
        .background(background)
        .textSelection(.enabled)
    }
}
