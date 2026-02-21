(function () {
  const container = document.getElementById('graph');
  const tooltip = document.getElementById('tooltip');

  const NODE_TIERS = {
    HEALTH_ANXIETY: 1, OSA: 1, GENETICS: 1, SSRI: 1,
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
  };

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

  function filteredGraphData(graphData) {
    const interventionIDs = new Set();
    const filteredNodes = graphData.nodes.filter((item) => {
      const node = item && item.data ? item.data : null;
      if (!node || typeof node.id !== 'string') return false;
      if (node.styleClass === 'intervention') {
        interventionIDs.add(node.id);
        return false;
      }
      return true;
    });

    const dormantIDs = new Set(
      graphData.nodes
        .map((item) => (item && item.data ? item.data : null))
        .filter((node) => node && (node.confirmed === 'no' || node.confirmed === 'inactive' || node.confirmed === 'external'))
        .map((node) => node.id)
    );

    const filteredEdges = graphData.edges.filter((item) => {
      const edge = item && item.data ? item.data : null;
      if (!edge || typeof edge.source !== 'string' || typeof edge.target !== 'string') return false;
      if (interventionIDs.has(edge.source) || interventionIDs.has(edge.target)) return false;
      if (!displayFlags.showFeedbackEdges && edge.edgeType === 'feedback') return false;
      if (!displayFlags.showProtectiveEdges && edge.edgeType === 'protective') return false;
      if (dormantIDs.has(edge.source) || dormantIDs.has(edge.target)) return false;
      return true;
    });

    return {
      nodes: filteredNodes,
      edges: filteredEdges,
    };
  }

  function cyStyles() {
    return [
      {
        selector: 'node',
        style: {
          'background-color': '#111827',
          'border-width': 2,
          'border-color': '#475569',
          'label': 'data(label)',
          'font-size': 10,
          'text-wrap': 'wrap',
          'text-max-width': 120,
          'text-valign': 'center',
          'text-halign': 'center',
          'color': '#e2e8f0',
          'width': 44,
          'height': 44,
          'overlay-padding': 6,
          'overlay-opacity': 0,
        },
      },
      {
        selector: 'node[styleClass = "robust"]',
        style: {
          'border-color': '#22c55e',
        },
      },
      {
        selector: 'node[styleClass = "moderate"]',
        style: {
          'border-color': '#f59e0b',
        },
      },
      {
        selector: 'node[styleClass = "preliminary"]',
        style: {
          'border-color': '#a855f7',
        },
      },
      {
        selector: 'node[styleClass = "mechanism"]',
        style: {
          'border-color': '#38bdf8',
        },
      },
      {
        selector: 'node[styleClass = "symptom"]',
        style: {
          'border-color': '#ef4444',
        },
      },
      {
        selector: 'edge',
        style: {
          'curve-style': 'bezier',
          'line-color': 'data(edgeColor)',
          'target-arrow-color': 'data(edgeColor)',
          'target-arrow-shape': 'triangle',
          'arrow-scale': 0.7,
          'width': 2,
          'label': 'data(label)',
          'font-size': 9,
          'color': '#cbd5e1',
          'text-background-color': '#0f172a',
          'text-background-opacity': 0.8,
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
        selector: 'edge[edgeType = "protective"]',
        style: {
          'line-style': 'dashed',
        },
      },
      {
        selector: ':selected',
        style: {
          'overlay-color': '#38bdf8',
          'overlay-opacity': 0.14,
        },
      },
    ];
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
    if (cy) {
      cy.destroy();
      cy = null;
    }
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

  function bindGraphEvents(nodeLabelMap) {
    cy.on('tap', 'node', (event) => {
      const node = event.target;
      const data = node.data();
      const tooltipBody = data.tooltip && typeof data.tooltip === 'object'
        ? [data.tooltip.evidence, data.tooltip.stat, data.tooltip.citation, data.tooltip.mechanism].filter(Boolean).join(' · ')
        : '';

      showTooltip(event.renderedPosition.x, event.renderedPosition.y, firstLine(data.label), tooltipBody);
      postEvent('nodeSelected', {
        id: data.id,
        label: firstLine(data.label),
      });
    });

    cy.on('tap', 'edge', (event) => {
      const edge = event.target;
      const data = edge.data();
      const sourceLabel = nodeLabelMap.get(data.source) || data.source;
      const targetLabel = nodeLabelMap.get(data.target) || data.target;

      showTooltip(
        event.renderedPosition.x,
        event.renderedPosition.y,
        `${sourceLabel} -> ${targetLabel}`,
        data.tooltip || data.label || ''
      );

      postEvent('edgeSelected', {
        source: data.source,
        target: data.target,
        sourceLabel,
        targetLabel,
        label: data.label || null,
      });
    });

    cy.on('tap', (event) => {
      if (event.target === cy) {
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

  function renderGraph(graphData) {
    try {
      const filtered = filteredGraphData(graphData);
      const elements = {
        nodes: filtered.nodes,
        edges: filtered.edges,
      };

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
        fit: true,
        padding: 28,
      }).run();

      const labelMap = new Map(elements.nodes.map((node) => [node.data.id, firstLine(node.data.label)]));
      bindGraphEvents(labelMap);
      postEvent('graphReady');
    } catch (error) {
      postEvent('renderError', { message: String(error && error.message ? error.message : error) });
    }
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

    const data = node.data();
    postEvent('nodeSelected', { id: data.id, label: firstLine(data.label) });
  }

  function handleCommand(envelope) {
    if (!envelope || typeof envelope.command !== 'string') {
      return;
    }

    if (envelope.command === 'setGraphData') {
      currentGraphData = normalizeGraphData(envelope.payload);
      renderGraph(currentGraphData);
      return;
    }

    if (envelope.command === 'setDisplayFlags') {
      const payload = envelope.payload || {};
      displayFlags.showFeedbackEdges = Boolean(payload.showFeedbackEdges);
      displayFlags.showProtectiveEdges = Boolean(payload.showProtectiveEdges);
      renderGraph(currentGraphData);
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

  renderGraph(currentGraphData);
})();
