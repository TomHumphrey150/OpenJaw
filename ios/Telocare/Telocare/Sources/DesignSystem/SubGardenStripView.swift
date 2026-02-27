import SwiftUI

struct SubGardenStripView: View {
    let clusters: [SubGardenSnapshot]
    let selectedNodeID: String?
    let onSelectNode: (String) -> Void

    var body: some View {
        GardenGridView(
            clusters: clusters,
            selectedNodeID: selectedNodeID,
            onSelectNode: onSelectNode
        )
    }
}
