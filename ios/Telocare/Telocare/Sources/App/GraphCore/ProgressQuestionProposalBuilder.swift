import Foundation

struct ProgressQuestionProposalBuilder {
    private let maximumQuestionCount: Int

    init(maximumQuestionCount: Int = 6) {
        self.maximumQuestionCount = max(1, maximumQuestionCount)
    }

    func build(
        graphData: CausalGraphData,
        graphVersion: String,
        createdAt: String
    ) -> ProgressQuestionSetProposal {
        let availableNodes = graphData.nodes
            .map(\.data)
            .filter { node in
                node.isDeactivated != true
                    && node.styleClass.localizedCaseInsensitiveContains("intervention") == false
            }
            .sorted { lhs, rhs in
                let lhsTitle = firstLine(in: lhs.label)
                let rhsTitle = firstLine(in: rhs.label)
                if lhsTitle != rhsTitle {
                    return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
                }
                return lhs.id < rhs.id
            }

        let nodesForQuestions: [GraphNodeData]
        if availableNodes.isEmpty {
            nodesForQuestions = graphData.nodes
                .map(\.data)
                .filter { $0.isDeactivated != true }
                .sorted { $0.id < $1.id }
        } else {
            nodesForQuestions = availableNodes
        }

        let questions = nodesForQuestions
            .prefix(maximumQuestionCount)
            .map { node in
                GraphDerivedProgressQuestion(
                    id: "progress.\(node.id.lowercased())",
                    title: "How is \(firstLine(in: node.label)) today?",
                    sourceNodeIDs: [node.id],
                    sourceEdgeIDs: associatedEdgeIDs(for: node.id, in: graphData)
                )
            }

        return ProgressQuestionSetProposal(
            sourceGraphVersion: graphVersion,
            proposedQuestionSetVersion: "questions-\(graphVersion)",
            questions: questions,
            createdAt: createdAt
        )
    }

    private func associatedEdgeIDs(for nodeID: String, in graphData: CausalGraphData) -> [String] {
        graphData.edges
            .compactMap { edge in
                guard edge.data.source == nodeID || edge.data.target == nodeID else {
                    return nil
                }
                return edge.data.id
            }
            .sorted()
    }

    private func firstLine(in label: String) -> String {
        label.components(separatedBy: "\n").first ?? label
    }
}
