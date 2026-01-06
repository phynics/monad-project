import SwiftUI

/// Simple flow layout
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews, cache: &cache)
        return rows.last?.maxY ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrangeSubviews(proposal: proposal, subviews: subviews, cache: &cache)
        for row in rows {
            for element in row.elements {
                element.subview.place(at: CGPoint(x: bounds.minX + element.x, y: bounds.minY + row.y), proposal: proposal)
            }
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> [Row] {
        var rows: [Row] = []
        var currentRow = Row(y: 0, maxY: .zero, elements: [])
        var currentX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            if currentX + size.width > (proposal.width ?? .infinity) {
                // New row
                currentRow.maxY = CGSize(width: currentX, height: currentRow.maxY.height)
                rows.append(currentRow)
                currentRow = Row(y: (rows.last?.maxY.height ?? 0) + spacing, maxY: CGSize(width: 0, height: size.height), elements: [])
                currentX = 0
            }

            currentRow.elements.append(RowElement(x: currentX, subview: subview))
            currentRow.maxY.height = max(currentRow.maxY.height, size.height)
            currentX += size.width + spacing
        }
        
        if !currentRow.elements.isEmpty {
            currentRow.maxY = CGSize(width: currentX, height: currentRow.maxY.height + currentRow.y)
            rows.append(currentRow)
        }

        return rows
    }

    struct Row {
        var y: CGFloat
        var maxY: CGSize
        var elements: [RowElement]
    }

    struct RowElement {
        var x: CGFloat
        var subview: LayoutSubview
    }
}
