export function buildInterventionMaps(graphData) {
    const interventionNodeMap = new Map();
    graphData.nodes.forEach(n => {
        if (n.data.styleClass === 'intervention') {
            interventionNodeMap.set(n.data.id, n.data);
        }
    });

    const interventionTargets = new Map();
    const targetInterventions = new Map();

    graphData.edges.forEach(e => {
        const src = e.data.source;
        const tgt = e.data.target;
        if (interventionNodeMap.has(src)) {
            if (!interventionTargets.has(src)) interventionTargets.set(src, []);
            interventionTargets.get(src).push({ target: tgt, label: e.data.label, tooltip: e.data.tooltip });
            if (!targetInterventions.has(tgt)) targetInterventions.set(tgt, []);
            if (!targetInterventions.get(tgt).includes(src)) {
                targetInterventions.get(tgt).push(src);
            }
        }
    });

    return { interventionNodeMap, interventionTargets, targetInterventions };
}
