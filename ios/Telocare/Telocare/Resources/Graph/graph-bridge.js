(function () {
  const container = document.getElementById('graph');
  const tooltip = document.getElementById('tooltip');

  const NODE_TIERS = {
    HEALTH_ANXIETY: 1, OSA: 1, EXTERNAL_TRIGGERS: 1, GENETICS: 1, SSRI: 1,
    STRESS: 2, SLEEP_DEP: 2, CAFFEINE: 2, ALCOHOL: 2, SMOKING: 2, AIRWAY_OBS: 2,
    CORTISOL: 3, CATECHOL: 3, GERD: 3, NEG_PRESSURE: 3, MG_DEF: 3, VIT_D: 3,
    SYMPATHETIC: 4, ACID: 4, PEPSIN: 4, TLESR: 4, GABA_DEF: 4, DOPAMINE: 4,
    VAGAL: 5,
    MICRO: 6,
    RMMA: 7,
    GRINDING: 8, TMD: 8, SALIVA: 8, FHP: 8,
    CERVICAL: 9, HYOID: 9, CS: 9, TOOTH: 9, HEADACHES: 9, EAR: 9,
    WINDUP: 10, NECK_TIGHTNESS: 10, GLOBUS: 10,
  };

  const displayFlags = {
    showFeedbackEdges: false,
    showProtectiveEdges: false,
    showInterventionNodes: false,
  };
  const BASE_VISUAL_STYLE = Object.freeze({
    nodeFontSize: 8,
    nodeBorderWidth: 2,
    nodeTextMaxWidth: 120,
    nodePadding: 10,
    edgeWidth: 2,
    edgeFontSize: 7,
    edgeArrowScale: 0.7,
  });
  const DEACTIVATED_NODE_OPACITY = 0.35;
  const DEACTIVATED_EDGE_OPACITY = 0.22;

  const defaultGraphData = {
    nodes: [
      { data: { id: 'STRESS', label: 'Stress & Anxiety\nOR 2.07', styleClass: 'moderate', confirmed: 'yes', tier: 2, tooltip: { evidence: 'Moderate', stat: 'OR 2.07', citation: 'Chemelo 2020', mechanism: 'Stress increases cortisol and arousal' } } },
      { data: { id: 'GERD', label: 'GERD / Silent Reflux\nOR 6.87', styleClass: 'robust', confirmed: 'yes', tier: 3, tooltip: { evidence: 'Robust', stat: 'OR 6.87', citation: 'Li 2018', mechanism: 'Acid exposure can trigger microarousal' } } },
      { data: { id: 'SLEEP_DEP', label: 'Sleep Deprivation', styleClass: 'moderate', confirmed: 'yes', tier: 2, tooltip: { evidence: 'Moderate', stat: 'Dose-dependent', citation: 'Sleep studies', mechanism: 'Fragmented sleep increases arousal' } } },
      { data: { id: 'MICRO', label: 'Microarousal\n79% precede RMMA', styleClass: 'robust', confirmed: 'yes', tier: 6, tooltip: { evidence: 'Robust', stat: '79%', citation: 'Kato 2001', mechanism: 'Microarousal is upstream of RMMA' } } },
      { data: { id: 'RMMA', label: 'RMMA / Sleep Bruxism', styleClass: 'robust', confirmed: 'yes', tier: 7, tooltip: { evidence: 'Robust', stat: 'Replicated', citation: 'Kato 2003', mechanism: 'Central motor event' } } },
      { data: { id: 'NECK_TIGHTNESS', label: 'Neck Tightness\n& Spasm', styleClass: 'symptom', confirmed: 'yes', tier: 10, tooltip: { evidence: 'Symptom', citation: 'Clinical', mechanism: 'Downstream symptom burden' } } },
      { data: { id: 'PPI_TX', label: 'PPI / Lansoprazole', styleClass: 'intervention', tooltip: { evidence: 'Robust', stat: 'RCT', citation: 'Ohmure 2016', mechanism: 'Reduces acid production' } } },
    ],
    edges: [
      { data: { source: 'STRESS', target: 'SLEEP_DEP', label: 'hyperarousal', edgeType: 'forward', edgeColor: '#b45309', tooltip: 'Stress can worsen sleep deprivation' } },
      { data: { source: 'STRESS', target: 'GERD', label: 'visceral hypersens.', edgeType: 'forward', edgeColor: '#b45309', tooltip: 'Stress can increase reflux sensitivity' } },
      { data: { source: 'GERD', target: 'MICRO', edgeType: 'forward', edgeColor: '#1b4332', tooltip: 'Reflux can contribute to microarousal' } },
      { data: { source: 'SLEEP_DEP', target: 'MICRO', edgeType: 'forward', edgeColor: '#b45309', tooltip: 'Sleep debt increases microarousal' } },
      { data: { source: 'MICRO', target: 'RMMA', label: '79% precede', edgeType: 'forward', edgeColor: '#1b4332', tooltip: 'Microarousal precedes RMMA' } },
      { data: { source: 'RMMA', target: 'NECK_TIGHTNESS', edgeType: 'dashed', edgeColor: '#1e3a5f', tooltip: 'RMMA may worsen neck tightness' } },
      { data: { source: 'PPI_TX', target: 'GERD', edgeType: 'forward', edgeColor: '#065f46', tooltip: 'Intervention reduces reflux burden' } },
    ],
  };

  let currentGraphData = defaultGraphData;
  let cy = null;
  let viewportThrottle = null;
  let resizeThrottle = null;
  let zoomStyleFrame = null;
  let currentSkin = readSkinFromCSS();
  let lastNodeTap = null;

  const LEGACY_EDGE_COLOR_TOKEN_BY_HEX = Object.freeze({
    b45309: 'edgeCausalColor',
    '1b4332': 'edgeProtectiveColor',
    '1e3a5f': 'edgeMechanismColor',
    '065f46': 'edgeInterventionColor',
  });

  function postEvent(event, payload) {
    const bridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.graphBridge;
    if (!bridge) return;
    bridge.postMessage({ event, payload: payload || {} });
  }

  function firstLine(label) {
    if (typeof label !== 'string') return '';
    const idx = label.indexOf('\n');
    return idx >= 0 ? label.slice(0, idx) : label;
  }

  function normalizeGraphData(value) {
    if (!value || !Array.isArray(value.nodes) || !Array.isArray(value.edges)) {
      return defaultGraphData;
    }
    return value;
  }

  function withClass(item, className) {
    const existing = typeof item.classes === 'string' ? item.classes.trim() : '';
    const classes = existing ? `${existing} ${className}` : className;
    return {
      ...item,
      classes,
    };
  }

  function parentIDsForNode(node) {
    if (!node) return [];

    if (Array.isArray(node.parentIds)) {
      return node.parentIds
        .filter((value) => typeof value === 'string')
        .map((value) => value.trim())
        .filter((value) => value.length > 0);
    }

    if (typeof node.parentId === 'string' && node.parentId.length > 0) {
      return [node.parentId];
    }

    return [];
  }

  function hierarchyMaps(nodes) {
    const parentsByID = new Map();

    nodes.forEach((item) => {
      const node = item && item.data ? item.data : null;
      if (!node || typeof node.id !== 'string') return;

      const parentIDs = parentIDsForNode(node);
      if (parentIDs.length === 0) {
        return;
      }

      parentsByID.set(node.id, parentIDs);
    });

    return { parentsByID };
  }

  function visibleNodeIDsByHierarchy(nodes, nodeByID, parentsByID) {
    const visibilityByID = new Map();
    const resolving = new Set();

    function isVisible(nodeID) {
      if (visibilityByID.has(nodeID)) {
        return visibilityByID.get(nodeID);
      }

      if (resolving.has(nodeID)) {
        return true;
      }

      const node = nodeByID.get(nodeID);
      if (!node) {
        return false;
      }

      resolving.add(nodeID);
      const parentIDs = parentsByID.get(nodeID) || [];
      let visible = false;

      if (parentIDs.length === 0) {
        visible = true;
      } else {
        for (const parentID of parentIDs) {
          const parentNode = nodeByID.get(parentID);
          if (!parentNode) {
            visible = true;
            break;
          }

          if (!isVisible(parentID)) {
            continue;
          }

          if (parentNode.isExpanded === false) {
            continue;
          }

          visible = true;
          break;
        }
      }

      resolving.delete(nodeID);
      visibilityByID.set(nodeID, visible);
      return visible;
    }

    nodes.forEach((item) => {
      const node = item && item.data ? item.data : null;
      if (!node || typeof node.id !== 'string') return;
      isVisible(node.id);
    });

    return new Set(
      [...visibilityByID.entries()]
        .filter((entry) => entry[1] === true)
        .map((entry) => entry[0])
    );
  }

  function nearestVisibleAncestor(nodeID, visibleNodeIDs, parentsByID) {
    if (visibleNodeIDs.has(nodeID)) {
      return nodeID;
    }

    const visited = new Set([nodeID]);
    const queue = [nodeID];

    while (queue.length > 0) {
      const currentNodeID = queue.shift();
      const parentIDs = parentsByID.get(currentNodeID) || [];

      for (const parentID of parentIDs) {
        if (visited.has(parentID)) {
          continue;
        }

        if (visibleNodeIDs.has(parentID)) {
          return parentID;
        }

        visited.add(parentID);
        queue.push(parentID);
      }
    }

    return null;
  }

  function hierarchyMembershipEdges(visibleNodeIDs, nodeByID, parentsByID, existingEdges) {
    const existingEdgeKeys = new Set();
    existingEdges.forEach((item) => {
      const edge = item && item.data ? item.data : null;
      if (!edge) return;
      existingEdgeKeys.add(`${edge.source}->${edge.target}`);
    });

    const hierarchyEdges = [];
    parentsByID.forEach((parentIDs, childID) => {
      if (!visibleNodeIDs.has(childID)) return;

      parentIDs.forEach((parentID) => {
        if (!visibleNodeIDs.has(parentID)) return;

        const parentNode = nodeByID.get(parentID);
        if (!parentNode || parentNode.isExpanded === false) return;

        const key = `${parentID}->${childID}`;
        if (existingEdgeKeys.has(key)) return;
        existingEdgeKeys.add(key);

        hierarchyEdges.push({
          data: {
            id: `hierarchy::${parentID}::${childID}`,
            source: parentID,
            target: childID,
            label: null,
            edgeType: 'hierarchy',
            edgeColor: currentSkin.edgeMechanismColor,
            tooltip: 'Hierarchy membership',
            originalSource: parentID,
            originalTarget: childID,
            isSyntheticHierarchy: true,
          },
        });
      });
    });

    return hierarchyEdges;
  }

  function filteredGraphData(graphData) {
    const interventionIDs = new Set();
    const filteredNodes = graphData.nodes.filter((item) => {
      const node = item && item.data ? item.data : null;
      if (!node || typeof node.id !== 'string') return false;
      if (node.styleClass === 'intervention') {
        interventionIDs.add(node.id);
        return displayFlags.showInterventionNodes;
      }
      return true;
    });

    const nodeByID = new Map(
      filteredNodes
        .map((item) => (item && item.data ? item.data : null))
        .filter((node) => node && typeof node.id === 'string')
        .map((node) => [node.id, node])
    );
    const { parentsByID } = hierarchyMaps(filteredNodes);
    const visibleNodeIDs = visibleNodeIDsByHierarchy(filteredNodes, nodeByID, parentsByID);
    const visibleNodesByHierarchy = filteredNodes.filter((item) => {
      const node = item && item.data ? item.data : null;
      return node && visibleNodeIDs.has(node.id);
    });

    const filteredEdges = graphData.edges
      .filter((item) => {
        const edge = item && item.data ? item.data : null;
        if (!edge || typeof edge.source !== 'string' || typeof edge.target !== 'string') return false;
        if (!displayFlags.showInterventionNodes && (interventionIDs.has(edge.source) || interventionIDs.has(edge.target))) return false;
        if (!displayFlags.showFeedbackEdges && edge.edgeType === 'feedback') return false;
        if (!displayFlags.showProtectiveEdges && edge.edgeType === 'protective') return false;
        return true;
      })
      .map((item) => {
        const edge = item && item.data ? item.data : null;
        if (!edge) return null;

        const routedSourceID = nearestVisibleAncestor(
          edge.source,
          visibleNodeIDs,
          parentsByID
        );
        const routedTargetID = nearestVisibleAncestor(
          edge.target,
          visibleNodeIDs,
          parentsByID
        );

        if (!routedSourceID || !routedTargetID) {
          return null;
        }
        if (routedSourceID === routedTargetID) {
          return null;
        }

        const edgeColor = resolvedEdgeColor(edge, nodeByID);
        return {
          ...item,
          data: {
            ...edge,
            source: routedSourceID,
            target: routedTargetID,
            edgeColor,
            originalSource: edge.source,
            originalTarget: edge.target,
          },
        };
      })
      .filter((item) => item !== null);
    const hierarchyEdges = hierarchyMembershipEdges(
      visibleNodeIDs,
      nodeByID,
      parentsByID,
      filteredEdges
    );
    const combinedEdges = filteredEdges.concat(hierarchyEdges);

    const deactivatedNodeIDs = new Set(
      filteredNodes
        .map((item) => (item && item.data ? item.data : null))
        .filter((node) => node && node.isDeactivated === true)
        .map((node) => node.id)
    );

    const visibleNodes = visibleNodesByHierarchy.map((item) => {
      const node = item && item.data ? item.data : null;
      if (!node || node.isDeactivated !== true) {
        return item;
      }

      return withClass(item, 'is-deactivated');
    });

    const edgesAfterNodeDeactivation = combinedEdges.filter((item) => {
      const edge = item && item.data ? item.data : null;
      if (!edge) return false;
      const originalSourceID = edge.originalSource || edge.source;
      return !deactivatedNodeIDs.has(originalSourceID);
    });

    const visibleEdges = edgesAfterNodeDeactivation.map((item) => {
      const edge = item && item.data ? item.data : null;
      if (!edge) return item;

      const originalTargetID = edge.originalTarget || edge.target;
      const isDeactivated = edge.isDeactivated === true
        || deactivatedNodeIDs.has(originalTargetID)
        || deactivatedNodeIDs.has(edge.target);
      if (!isDeactivated) {
        return item;
      }

      return withClass(item, 'is-deactivated');
    });

    return {
      nodes: visibleNodes,
      edges: visibleEdges,
    };
  }

  function getCSSVar(name) {
    return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  }

  function readSkinFromCSS() {
    return {
      backgroundColor: getCSSVar('--bg-color') || '#FAF5EE',
      textColor: getCSSVar('--text-color') || '#403B38',
      nodeBackgroundColor: getCSSVar('--node-bg') || '#FFFDF7',
      nodeBorderDefaultColor: getCSSVar('--node-border-default') || '#BFB8B3',
      nodeBorderRobustColor: getCSSVar('--node-border-robust') || '#85C28F',
      nodeBorderModerateColor: getCSSVar('--node-border-moderate') || '#FF9966',
      nodeBorderPreliminaryColor: getCSSVar('--node-border-preliminary') || '#D4A5FF',
      nodeBorderMechanismColor: getCSSVar('--node-border-mechanism') || '#7DD3FC',
      nodeBorderSymptomColor: getCSSVar('--node-border-symptom') || '#FF7060',
      nodeBorderInterventionColor: getCSSVar('--node-border-intervention') || '#FF7060',
      edgeTextBackgroundColor: getCSSVar('--edge-text-bg') || '#FAF5EE',
      tooltipBackgroundColor: getCSSVar('--tooltip-bg') || 'rgba(255, 253, 247, 0.97)',
      tooltipBorderColor: getCSSVar('--tooltip-border') || 'rgba(140, 133, 128, 0.4)',
      selectionOverlayColor: getCSSVar('--selection-overlay') || '#FF7060',
      edgeCausalColor: getCSSVar('--edge-causal') || '#B45309',
      edgeProtectiveColor: getCSSVar('--edge-protective') || '#1B4332',
      edgeFeedbackColor: getCSSVar('--edge-feedback') || '#FF9966',
      edgeMechanismColor: getCSSVar('--edge-mechanism') || '#1E3A5F',
      edgeInterventionColor: getCSSVar('--edge-intervention') || '#065F46',
    };
  }

  function sanitizedString(value, fallback) {
    if (typeof value !== 'string') return fallback;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : fallback;
  }

  function normalizeSkinPayload(payload) {
    const base = currentSkin || readSkinFromCSS();
    const source = payload && typeof payload === 'object' ? payload : {};

    return {
      backgroundColor: sanitizedString(source.backgroundColor, base.backgroundColor),
      textColor: sanitizedString(source.textColor, base.textColor),
      nodeBackgroundColor: sanitizedString(source.nodeBackgroundColor, base.nodeBackgroundColor),
      nodeBorderDefaultColor: sanitizedString(source.nodeBorderDefaultColor, base.nodeBorderDefaultColor),
      nodeBorderRobustColor: sanitizedString(source.nodeBorderRobustColor, base.nodeBorderRobustColor),
      nodeBorderModerateColor: sanitizedString(source.nodeBorderModerateColor, base.nodeBorderModerateColor),
      nodeBorderPreliminaryColor: sanitizedString(source.nodeBorderPreliminaryColor, base.nodeBorderPreliminaryColor),
      nodeBorderMechanismColor: sanitizedString(source.nodeBorderMechanismColor, base.nodeBorderMechanismColor),
      nodeBorderSymptomColor: sanitizedString(source.nodeBorderSymptomColor, base.nodeBorderSymptomColor),
      nodeBorderInterventionColor: sanitizedString(source.nodeBorderInterventionColor, base.nodeBorderInterventionColor),
      edgeTextBackgroundColor: sanitizedString(source.edgeTextBackgroundColor, base.edgeTextBackgroundColor),
      tooltipBackgroundColor: sanitizedString(source.tooltipBackgroundColor, base.tooltipBackgroundColor),
      tooltipBorderColor: sanitizedString(source.tooltipBorderColor, base.tooltipBorderColor),
      selectionOverlayColor: sanitizedString(source.selectionOverlayColor, base.selectionOverlayColor),
      edgeCausalColor: sanitizedString(source.edgeCausalColor, base.edgeCausalColor),
      edgeProtectiveColor: sanitizedString(source.edgeProtectiveColor, base.edgeProtectiveColor),
      edgeFeedbackColor: sanitizedString(source.edgeFeedbackColor, base.edgeFeedbackColor),
      edgeMechanismColor: sanitizedString(source.edgeMechanismColor, base.edgeMechanismColor),
      edgeInterventionColor: sanitizedString(source.edgeInterventionColor, base.edgeInterventionColor),
    };
  }

  function applySkin(payload) {
    currentSkin = normalizeSkinPayload(payload);
    const rootStyle = document.documentElement.style;
    rootStyle.setProperty('--bg-color', currentSkin.backgroundColor);
    rootStyle.setProperty('--text-color', currentSkin.textColor);
    rootStyle.setProperty('--node-bg', currentSkin.nodeBackgroundColor);
    rootStyle.setProperty('--node-border-default', currentSkin.nodeBorderDefaultColor);
    rootStyle.setProperty('--node-border-robust', currentSkin.nodeBorderRobustColor);
    rootStyle.setProperty('--node-border-moderate', currentSkin.nodeBorderModerateColor);
    rootStyle.setProperty('--node-border-preliminary', currentSkin.nodeBorderPreliminaryColor);
    rootStyle.setProperty('--node-border-mechanism', currentSkin.nodeBorderMechanismColor);
    rootStyle.setProperty('--node-border-symptom', currentSkin.nodeBorderSymptomColor);
    rootStyle.setProperty('--node-border-intervention', currentSkin.nodeBorderInterventionColor);
    rootStyle.setProperty('--edge-text-bg', currentSkin.edgeTextBackgroundColor);
    rootStyle.setProperty('--tooltip-bg', currentSkin.tooltipBackgroundColor);
    rootStyle.setProperty('--tooltip-border', currentSkin.tooltipBorderColor);
    rootStyle.setProperty('--selection-overlay', currentSkin.selectionOverlayColor);
    rootStyle.setProperty('--edge-causal', currentSkin.edgeCausalColor);
    rootStyle.setProperty('--edge-protective', currentSkin.edgeProtectiveColor);
    rootStyle.setProperty('--edge-feedback', currentSkin.edgeFeedbackColor);
    rootStyle.setProperty('--edge-mechanism', currentSkin.edgeMechanismColor);
    rootStyle.setProperty('--edge-intervention', currentSkin.edgeInterventionColor);
  }

  function normalizedHexColor(value) {
    if (typeof value !== 'string') return null;
    const cleaned = value.trim().toLowerCase().replace('#', '');
    if (!/^[0-9a-f]{6}$/.test(cleaned)) return null;
    return cleaned;
  }

  function edgeColorFromType(edgeType) {
    const normalizedType = typeof edgeType === 'string'
      ? edgeType.trim().toLowerCase()
      : '';

    if (normalizedType === 'protective' || normalizedType === 'inhibits') {
      return currentSkin.edgeProtectiveColor;
    }
    if (normalizedType === 'feedback') {
      return currentSkin.edgeFeedbackColor;
    }
    if (normalizedType === 'dashed') {
      return currentSkin.edgeMechanismColor;
    }
    if (normalizedType === 'causal' || normalizedType === 'causes' || normalizedType === 'triggers') {
      return currentSkin.edgeCausalColor;
    }

    return null;
  }

  function resolvedEdgeColor(edge, nodeByID) {
    const explicitColor = typeof edge.edgeColor === 'string' ? edge.edgeColor.trim() : '';
    const normalizedExplicitHex = normalizedHexColor(explicitColor);

    if (normalizedExplicitHex && LEGACY_EDGE_COLOR_TOKEN_BY_HEX[normalizedExplicitHex]) {
      const token = LEGACY_EDGE_COLOR_TOKEN_BY_HEX[normalizedExplicitHex];
      return currentSkin[token];
    }

    const lowerExplicitColor = explicitColor.toLowerCase();
    if (lowerExplicitColor.includes('protective') || lowerExplicitColor.includes('green')) {
      return currentSkin.edgeProtectiveColor;
    }
    if (lowerExplicitColor.includes('feedback')) {
      return currentSkin.edgeFeedbackColor;
    }
    if (lowerExplicitColor.includes('mechanism') || lowerExplicitColor.includes('blue')) {
      return currentSkin.edgeMechanismColor;
    }
    if (lowerExplicitColor.includes('intervention')) {
      return currentSkin.edgeInterventionColor;
    }
    if (lowerExplicitColor.includes('causal') || lowerExplicitColor.includes('red') || lowerExplicitColor.includes('harmful')) {
      return currentSkin.edgeCausalColor;
    }

    if (explicitColor && normalizedExplicitHex === null) {
      return explicitColor;
    }

    if (explicitColor && normalizedExplicitHex !== null) {
      return explicitColor;
    }

    const typeColor = edgeColorFromType(edge.edgeType);
    if (typeColor) {
      return typeColor;
    }

    const sourceNode = nodeByID.get(edge.source);
    const targetNode = nodeByID.get(edge.target);
    if ((sourceNode && sourceNode.styleClass === 'intervention') || (targetNode && targetNode.styleClass === 'intervention')) {
      return currentSkin.edgeInterventionColor;
    }

    return currentSkin.edgeCausalColor;
  }

  function cyStyles() {
    const textColor = getCSSVar('--text-color') || '#403B38';
    const nodeBg = getCSSVar('--node-bg') || '#FFFDF7';
    const borderDefault = getCSSVar('--node-border-default') || '#BFB8B3';
    const borderRobust = getCSSVar('--node-border-robust') || '#85C28F';
    const borderModerate = getCSSVar('--node-border-moderate') || '#FF9966';
    const borderPreliminary = getCSSVar('--node-border-preliminary') || '#D4A5FF';
    const borderMechanism = getCSSVar('--node-border-mechanism') || '#7DD3FC';
    const borderSymptom = getCSSVar('--node-border-symptom') || '#FF7060';
    const borderIntervention = getCSSVar('--node-border-intervention') || '#FF7060';
    const edgeTextBg = getCSSVar('--edge-text-bg') || '#FAF5EE';
    const selectionOverlay = getCSSVar('--selection-overlay') || '#FF7060';

    return [
      {
        selector: 'node',
        style: {
          'z-index-compare': 'manual',
          'z-index': 20,
          'shape': 'round-rectangle',
          'background-color': nodeBg,
          'border-width': BASE_VISUAL_STYLE.nodeBorderWidth,
          'border-color': borderDefault,
          'label': 'data(label)',
          'font-size': BASE_VISUAL_STYLE.nodeFontSize,
          'text-wrap': 'wrap',
          'text-max-width': BASE_VISUAL_STYLE.nodeTextMaxWidth,
          'text-valign': 'center',
          'text-halign': 'center',
          'color': textColor,
          'width': 'label',
          'height': 'label',
          'padding': BASE_VISUAL_STYLE.nodePadding,
          'overlay-padding': 6,
          'overlay-opacity': 0,
        },
      },
      {
        selector: 'node[styleClass = "robust"]',
        style: {
          'border-color': borderRobust,
        },
      },
      {
        selector: 'node[styleClass = "moderate"]',
        style: {
          'border-color': borderModerate,
        },
      },
      {
        selector: 'node[styleClass = "preliminary"]',
        style: {
          'border-color': borderPreliminary,
        },
      },
      {
        selector: 'node[styleClass = "mechanism"]',
        style: {
          'border-color': borderMechanism,
        },
      },
      {
        selector: 'node[styleClass = "symptom"]',
        style: {
          'border-color': borderSymptom,
        },
      },
      {
        selector: 'node[styleClass = "intervention"]',
        style: {
          'border-color': borderIntervention,
          'border-style': 'dashed',
        },
      },
      {
        selector: 'node.is-deactivated',
        style: {
          'z-index': 2,
          'opacity': DEACTIVATED_NODE_OPACITY,
        },
      },
      {
        selector: 'edge',
        style: {
          'z-index-compare': 'manual',
          'z-index': 10,
          'curve-style': 'bezier',
          'line-color': 'data(edgeColor)',
          'target-arrow-color': 'data(edgeColor)',
          'target-arrow-shape': 'triangle',
          'arrow-scale': 0.7,
          'width': 2,
          'label': 'data(label)',
          'font-size': 9,
          'color': textColor,
          'text-background-color': edgeTextBg,
          'text-background-opacity': 0.9,
          'text-background-padding': 2,
        },
      },
      {
        selector: 'edge[edgeType = "dashed"]',
        style: {
          'line-style': 'dashed',
          'line-dash-pattern': [5, 4],
        },
      },
      {
        selector: 'edge[edgeType = "hierarchy"]',
        style: {
          'line-style': 'dotted',
          'line-dash-pattern': [2, 4],
          'target-arrow-shape': 'none',
          'width': 1.3,
          'opacity': 0.75,
        },
      },
      {
        selector: 'edge[edgeType = "protective"]',
        style: {
          'line-style': 'dashed',
        },
      },
      {
        selector: 'edge.is-deactivated',
        style: {
          'z-index': 1,
          'opacity': DEACTIVATED_EDGE_OPACITY,
        },
      },
      {
        selector: ':selected',
        style: {
          'overlay-color': selectionOverlay,
          'overlay-opacity': 0.18,
        },
      },
    ];
  }

  function clamp(min, value, max) {
    return Math.max(min, Math.min(max, value));
  }

  function zoomVisualScale(zoom) {
    const safeZoom = Math.max(0.01, Number.isFinite(zoom) ? zoom : 1);
    return clamp(0.52, Math.pow(1 / safeZoom, 0.62), 1);
  }

  function applyZoomAdaptiveStyle() {
    if (!cy) return;

    const zoom = cy.zoom();
    const visualScale = zoomVisualScale(zoom);
    const nodeTextScale = clamp(0.62, Math.pow(1 / Math.max(0.01, zoom), 0.35), 1.05);
    const edgeTextScale = clamp(0.56, Math.pow(1 / Math.max(0.01, zoom), 0.4), 1);
    const edgeTextOpacity = zoom < 1 ? 0 : (zoom < 1.2 ? 0.55 : 1);

    cy.batch(() => {
      cy.style()
        .selector('node')
        .style({
          'font-size': BASE_VISUAL_STYLE.nodeFontSize * nodeTextScale,
          'border-width': BASE_VISUAL_STYLE.nodeBorderWidth * visualScale,
          'text-max-width': BASE_VISUAL_STYLE.nodeTextMaxWidth * nodeTextScale,
          'padding': BASE_VISUAL_STYLE.nodePadding * visualScale,
          'overlay-padding': 8,
        })
        .selector('edge')
        .style({
          'width': BASE_VISUAL_STYLE.edgeWidth * visualScale,
          'font-size': BASE_VISUAL_STYLE.edgeFontSize * edgeTextScale,
          'arrow-scale': BASE_VISUAL_STYLE.edgeArrowScale * visualScale,
          'text-opacity': edgeTextOpacity,
        })
        .update();
    });
  }

  function scheduleZoomAdaptiveStyleUpdate() {
    if (zoomStyleFrame !== null) return;

    zoomStyleFrame = window.requestAnimationFrame(() => {
      zoomStyleFrame = null;
      applyZoomAdaptiveStyle();
    });
  }

  function rowY(tier, height) {
    const minY = 60;
    const maxY = Math.max(minY + 1, height - 60);
    return minY + ((tier - 1) / 9) * (maxY - minY);
  }

  function computeTieredPositions(elements, width, height) {
    const buckets = new Map();

    elements.nodes.forEach((node) => {
      const data = node.data;
      const tier = typeof data.tier === 'number' ? data.tier : (NODE_TIERS[data.id] || 5);
      const clampedTier = Math.max(1, Math.min(10, tier));

      if (!buckets.has(clampedTier)) {
        buckets.set(clampedTier, []);
      }

      buckets.get(clampedTier).push(data.id);
    });

    const positions = {};
    const minX = 56;
    const maxX = Math.max(minX + 1, width - 56);

    for (let tier = 1; tier <= 10; tier += 1) {
      const ids = buckets.get(tier) || [];
      if (ids.length === 0) continue;

      const y = rowY(tier, height);
      ids.forEach((id, index) => {
        const x = ids.length === 1
          ? (minX + maxX) / 2
          : minX + (index / (ids.length - 1)) * (maxX - minX);
        positions[id] = { x, y };
      });
    }

    return positions;
  }

  function destroyGraph() {
    if (zoomStyleFrame !== null) {
      window.cancelAnimationFrame(zoomStyleFrame);
      zoomStyleFrame = null;
    }

    if (cy) {
      cy.destroy();
      cy = null;
    }
  }

  function captureViewport() {
    if (!cy) return null;

    const pan = cy.pan();
    const zoom = cy.zoom();
    if (!pan || !Number.isFinite(pan.x) || !Number.isFinite(pan.y) || !Number.isFinite(zoom)) {
      return null;
    }

    return {
      pan: {
        x: pan.x,
        y: pan.y,
      },
      zoom,
    };
  }

  function restoreViewport(viewport) {
    if (!cy || !viewport || !viewport.pan) {
      return false;
    }

    const pan = viewport.pan;
    const zoom = viewport.zoom;
    if (!Number.isFinite(pan.x) || !Number.isFinite(pan.y) || !Number.isFinite(zoom)) {
      return false;
    }

    const clampedZoom = clamp(cy.minZoom(), zoom, cy.maxZoom());
    cy.zoom(clampedZoom);
    cy.pan({ x: pan.x, y: pan.y });
    return true;
  }

  function showTooltip(x, y, title, body) {
    if (!title && !body) {
      hideTooltip();
      return;
    }

    const titleHTML = title ? `<div class=\"tooltip-title\">${title}</div>` : '';
    const bodyHTML = body ? `<div>${body}</div>` : '';
    tooltip.innerHTML = `${titleHTML}${bodyHTML}`;
    tooltip.style.left = `${Math.max(8, Math.min(window.innerWidth - 288, x + 12))}px`;
    tooltip.style.top = `${Math.max(8, Math.min(window.innerHeight - 120, y + 12))}px`;
    tooltip.style.display = 'block';
  }

  function hideTooltip() {
    tooltip.style.display = 'none';
    tooltip.innerHTML = '';
  }

  function centerSelectionInVisibleSpace(renderedPosition) {
    if (!cy || !renderedPosition) return;

    const x = Number(renderedPosition.x);
    const y = Number(renderedPosition.y);
    if (!Number.isFinite(x) || !Number.isFinite(y)) return;

    const targetX = cy.width() / 2;
    const targetY = cy.height() * 0.25;
    const currentPan = cy.pan();

    cy.animate({
      pan: {
        x: currentPan.x + (targetX - x),
        y: currentPan.y + (targetY - y),
      },
      duration: 220,
    });
  }

  function bindGraphEvents(nodeLabelMap) {
    cy.on('zoom', () => {
      scheduleZoomAdaptiveStyleUpdate();
    });

    cy.on('tap', 'node', (event) => {
      const node = event.target;
      const data = node.data();
      const now = Date.now();
      if (lastNodeTap && lastNodeTap.id === data.id && (now - lastNodeTap.timestamp) <= 280) {
        postEvent('nodeDoubleTapped', {
          id: data.id,
          label: firstLine(data.label),
        });
        lastNodeTap = null;
      } else {
        lastNodeTap = {
          id: data.id,
          timestamp: now,
        };
      }

      hideTooltip();
      centerSelectionInVisibleSpace(event.renderedPosition);
      postEvent('nodeSelected', {
        id: data.id,
        label: firstLine(data.label),
      });
    });

    cy.on('tap', 'edge', (event) => {
      const edge = event.target;
      const data = edge.data();
      if (data.isSyntheticHierarchy === true) {
        lastNodeTap = null;
        hideTooltip();
        return;
      }
      lastNodeTap = null;
      const originalSourceID = data.originalSource || data.source;
      const originalTargetID = data.originalTarget || data.target;
      const sourceLabel = nodeLabelMap.get(originalSourceID) || originalSourceID;
      const targetLabel = nodeLabelMap.get(originalTargetID) || originalTargetID;
      hideTooltip();
      centerSelectionInVisibleSpace(event.renderedPosition);

      postEvent('edgeSelected', {
        source: originalSourceID,
        target: originalTargetID,
        sourceLabel,
        targetLabel,
        label: data.label || null,
        edgeType: data.edgeType || null,
      });
    });

    cy.on('tap', (event) => {
      if (event.target === cy) {
        lastNodeTap = null;
        hideTooltip();
      }
    });

    cy.on('zoom pan', () => {
      if (viewportThrottle !== null) {
        clearTimeout(viewportThrottle);
      }

      viewportThrottle = setTimeout(() => {
        viewportThrottle = null;
        postEvent('viewportChanged', {
          zoom: cy.zoom(),
        });
      }, 120);
    });
  }

  function renderGraph(graphData, options) {
    try {
      const preserveViewport = Boolean(options && options.preserveViewport);
      const previousViewport = preserveViewport ? captureViewport() : null;
      const filtered = filteredGraphData(graphData);
      const elements = {
        nodes: filtered.nodes,
        edges: filtered.edges,
      };

      lastNodeTap = null;
      destroyGraph();

      cy = window.cytoscape({
        container,
        elements,
        style: cyStyles(),
        wheelSensitivity: 0.18,
        minZoom: 0.2,
        maxZoom: 3.0,
      });

      const width = Math.max(320, container.clientWidth || window.innerWidth || 320);
      const height = Math.max(280, container.clientHeight || window.innerHeight || 280);
      const positions = computeTieredPositions(elements, width, height);

      cy.layout({
        name: 'preset',
        positions: (node) => positions[node.id()] || undefined,
        animate: false,
        fit: previousViewport === null,
        padding: 28,
      }).run();

      if (previousViewport && !restoreViewport(previousViewport)) {
        cy.fit(undefined, 28);
      }

      applyZoomAdaptiveStyle();

      const labelMap = new Map(
        currentGraphData.nodes.map((node) => [node.data.id, firstLine(node.data.label)])
      );
      bindGraphEvents(labelMap);
      postEvent('graphReady');
    } catch (error) {
      postEvent('renderError', { message: String(error && error.message ? error.message : error) });
    }
  }

  function refreshLayoutForContainerSizeChange() {
    if (resizeThrottle !== null) {
      clearTimeout(resizeThrottle);
    }

    resizeThrottle = setTimeout(() => {
      resizeThrottle = null;
      renderGraph(currentGraphData, { preserveViewport: true });
    }, 90);
  }

  function focusNode(nodeID) {
    if (!cy || !nodeID) return;
    const node = cy.getElementById(nodeID);
    if (!node || node.empty()) return;

    cy.$(':selected').unselect();
    node.select();
    cy.animate({
      center: { eles: node },
      zoom: Math.max(0.7, cy.zoom()),
      duration: 220,
    });
  }

  function handleCommand(envelope) {
    if (!envelope || typeof envelope.command !== 'string') {
      return;
    }

    if (envelope.command === 'setSkin') {
      applySkin(envelope.payload);
      if (cy) {
        renderGraph(currentGraphData, { preserveViewport: true });
      }
      return;
    }

    if (envelope.command === 'setGraphData') {
      currentGraphData = normalizeGraphData(envelope.payload);
      renderGraph(currentGraphData, { preserveViewport: true });
      return;
    }

    if (envelope.command === 'setDisplayFlags') {
      const payload = envelope.payload || {};
      displayFlags.showFeedbackEdges = Boolean(payload.showFeedbackEdges);
      displayFlags.showProtectiveEdges = Boolean(payload.showProtectiveEdges);
      displayFlags.showInterventionNodes = Boolean(payload.showInterventionNodes);
      renderGraph(currentGraphData, { preserveViewport: true });
      return;
    }

    if (envelope.command === 'focusNode') {
      focusNode(envelope.payload && envelope.payload.nodeID ? envelope.payload.nodeID : '');
      return;
    }
  }

  function receiveSwiftMessage(rawJSON) {
    try {
      const envelope = JSON.parse(rawJSON);
      handleCommand(envelope);
    } catch (error) {
      postEvent('renderError', { message: String(error && error.message ? error.message : error) });
    }
  }

  window.TelocareGraph = {
    receiveSwiftMessage,
  };

  if (typeof ResizeObserver === 'function') {
    const observer = new ResizeObserver(() => {
      refreshLayoutForContainerSizeChange();
    });
    observer.observe(container);
  }

  window.addEventListener('resize', refreshLayoutForContainerSizeChange);
})();
