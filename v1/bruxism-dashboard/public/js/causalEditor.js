/**
 * Causal Chain Editor Module
 * Allows editing the causal chain diagram
 */

import * as storage from './storage.js';

// Default chain structure
const DEFAULT_CHAIN = {
    nodes: [
        { id: 'upstream', label: 'Upstream', description: 'Triggers & Causes', pathway: 'upstream' },
        { id: 'midstream', label: 'Midstream', description: 'Arousals & Sleep', pathway: 'midstream' },
        { id: 'downstream', label: 'Downstream', description: 'Grinding & Damage', pathway: 'downstream' }
    ]
};

let currentChain = null;
let isEditMode = false;
let interventionCounts = { upstream: 0, midstream: 0, downstream: 0 };
let onFilterCallback = null;

export function initCausalEditor(interventions, onFilter) {
    onFilterCallback = onFilter;

    // Count interventions per pathway
    interventionCounts = {
        upstream: interventions.filter(i => i.causalPathway === 'upstream').length,
        midstream: interventions.filter(i => i.causalPathway === 'midstream').length,
        downstream: interventions.filter(i => i.causalPathway === 'downstream').length
    };

    // Load custom diagram or use default
    const savedDiagram = storage.getDiagram();
    currentChain = savedDiagram || { ...DEFAULT_CHAIN };

    // Add edit button to the UI
    addEditControls();

    // Initial render
    renderChain();
}

function addEditControls() {
    const chainContainer = document.getElementById('causal-chain');

    // Create edit controls container
    const controls = document.createElement('div');
    controls.className = 'chain-controls';
    controls.innerHTML = `
        <button id="edit-chain-btn" class="chain-edit-btn" title="Edit causal chain">✏️ Edit</button>
        <button id="reset-chain-btn" class="chain-reset-btn hidden" title="Reset to default">↺ Reset</button>
        <button id="done-chain-btn" class="chain-done-btn hidden" title="Done editing">✓ Done</button>
    `;

    chainContainer.parentNode.insertBefore(controls, chainContainer);

    // Event listeners
    document.getElementById('edit-chain-btn').addEventListener('click', enterEditMode);
    document.getElementById('reset-chain-btn').addEventListener('click', resetChain);
    document.getElementById('done-chain-btn').addEventListener('click', exitEditMode);
}

function enterEditMode() {
    isEditMode = true;
    document.getElementById('edit-chain-btn').classList.add('hidden');
    document.getElementById('reset-chain-btn').classList.remove('hidden');
    document.getElementById('done-chain-btn').classList.remove('hidden');
    document.getElementById('causal-chain').classList.add('edit-mode');
    renderChain();
}

function exitEditMode() {
    isEditMode = false;
    document.getElementById('edit-chain-btn').classList.remove('hidden');
    document.getElementById('reset-chain-btn').classList.add('hidden');
    document.getElementById('done-chain-btn').classList.add('hidden');
    document.getElementById('causal-chain').classList.remove('edit-mode');

    // Save to localStorage
    storage.saveDiagram(currentChain);

    renderChain();
}

function resetChain() {
    if (confirm('Reset to default causal chain? Your custom nodes will be removed.')) {
        currentChain = JSON.parse(JSON.stringify(DEFAULT_CHAIN));
        storage.clearDiagram();
        renderChain();
    }
}

function renderChain() {
    const container = document.getElementById('causal-chain');
    container.innerHTML = '';

    currentChain.nodes.forEach((node, index) => {
        // Add "+" button before node (except first) in edit mode
        if (isEditMode && index > 0) {
            const addBtn = document.createElement('button');
            addBtn.className = 'chain-add-btn';
            addBtn.innerHTML = '+';
            addBtn.title = 'Add node here';
            addBtn.addEventListener('click', () => addNodeAt(index));
            container.appendChild(addBtn);
        }

        // Render node
        const nodeEl = createNodeElement(node, index);
        container.appendChild(nodeEl);

        // Add arrow after node (except last)
        if (index < currentChain.nodes.length - 1) {
            const arrow = document.createElement('div');
            arrow.className = 'chain-arrow';
            arrow.textContent = '→';
            container.appendChild(arrow);
        }
    });

    // Add "+" button at end in edit mode
    if (isEditMode) {
        const addBtn = document.createElement('button');
        addBtn.className = 'chain-add-btn';
        addBtn.innerHTML = '+';
        addBtn.title = 'Add node at end';
        addBtn.addEventListener('click', () => addNodeAt(currentChain.nodes.length));
        container.appendChild(addBtn);
    }
}

function createNodeElement(node, index) {
    const nodeEl = document.createElement('div');
    nodeEl.className = 'chain-node';
    nodeEl.dataset.pathway = node.pathway;
    nodeEl.dataset.nodeId = node.id;

    const count = interventionCounts[node.pathway] || 0;
    const isCustom = !['upstream', 'midstream', 'downstream'].includes(node.id);

    nodeEl.innerHTML = `
        <div class="node-circle"></div>
        <div class="node-label">${escapeHtml(node.label)}</div>
        <div class="node-description">${escapeHtml(node.description)}</div>
        <div class="node-count"><span>${count}</span></div>
        ${isEditMode ? `
            <div class="node-edit-controls">
                <button class="node-edit-btn" title="Edit node">✏️</button>
                ${isCustom ? `<button class="node-delete-btn" title="Delete node">🗑️</button>` : ''}
            </div>
        ` : ''}
    `;

    // Click to filter (when not in edit mode)
    if (!isEditMode) {
        nodeEl.addEventListener('click', () => handleNodeClick(node));
    }

    // Edit mode handlers
    if (isEditMode) {
        const editBtn = nodeEl.querySelector('.node-edit-btn');
        if (editBtn) {
            editBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                editNode(index);
            });
        }

        const deleteBtn = nodeEl.querySelector('.node-delete-btn');
        if (deleteBtn) {
            deleteBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                deleteNode(index);
            });
        }
    }

    return nodeEl;
}

function handleNodeClick(node) {
    // Toggle filter
    const nodes = document.querySelectorAll('.chain-node');
    const isCurrentlyActive = document.querySelector(`.chain-node[data-node-id="${node.id}"]`)?.classList.contains('active');

    nodes.forEach(n => n.classList.remove('active'));

    if (!isCurrentlyActive) {
        document.querySelector(`.chain-node[data-node-id="${node.id}"]`)?.classList.add('active');
        // Update filter dropdown and trigger filter
        document.getElementById('filter-pathway').value = node.pathway;
    } else {
        document.getElementById('filter-pathway').value = '';
    }

    if (onFilterCallback) {
        onFilterCallback();
    }
}

function addNodeAt(index) {
    const label = prompt('Enter node label:', 'New Stage');
    if (!label) return;

    const description = prompt('Enter description:', 'Description');

    // Determine pathway based on position
    let pathway = 'midstream';
    if (index === 0) pathway = 'upstream';
    else if (index >= currentChain.nodes.length) pathway = 'downstream';
    else {
        // Ask which pathway this belongs to
        const choice = prompt('Which pathway? (upstream, midstream, downstream):', 'midstream');
        if (choice && ['upstream', 'midstream', 'downstream'].includes(choice.toLowerCase())) {
            pathway = choice.toLowerCase();
        }
    }

    const newNode = {
        id: 'custom_' + Date.now(),
        label: label,
        description: description || '',
        pathway: pathway
    };

    currentChain.nodes.splice(index, 0, newNode);
    renderChain();
}

function editNode(index) {
    const node = currentChain.nodes[index];

    const newLabel = prompt('Edit label:', node.label);
    if (newLabel === null) return;

    const newDescription = prompt('Edit description:', node.description);
    if (newDescription === null) return;

    // For custom nodes, allow changing pathway
    const isCustom = !['upstream', 'midstream', 'downstream'].includes(node.id);
    if (isCustom) {
        const newPathway = prompt('Which pathway? (upstream, midstream, downstream):', node.pathway);
        if (newPathway && ['upstream', 'midstream', 'downstream'].includes(newPathway.toLowerCase())) {
            node.pathway = newPathway.toLowerCase();
        }
    }

    node.label = newLabel;
    node.description = newDescription;
    renderChain();
}

function deleteNode(index) {
    const node = currentChain.nodes[index];
    if (confirm(`Delete "${node.label}"?`)) {
        currentChain.nodes.splice(index, 1);
        renderChain();
    }
}

function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

export function getCustomChain() {
    return currentChain;
}
