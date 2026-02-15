let allInterventions = [];
let filteredInterventions = [];
let renderCallback = null;
let scatterCallback = null;

export function initFilters(interventions, onRender, onScatterRender = null) {
    allInterventions = interventions;
    filteredInterventions = interventions;
    renderCallback = onRender;
    scatterCallback = onScatterRender;

    // Add event listeners
    document.getElementById('search').addEventListener('input', applyFilters);
    document.getElementById('filter-timeOfDay').addEventListener('change', applyFilters);
    document.getElementById('filter-evidenceLevel').addEventListener('change', applyFilters);
    document.getElementById('filter-roiTier').addEventListener('change', applyFilters);
    document.getElementById('filter-tier').addEventListener('change', applyFilters);
    document.getElementById('filter-condition').addEventListener('change', applyFilters);
    document.getElementById('filter-pathway').addEventListener('change', handlePathwayFilterChange);

    // Clear filters button
    document.getElementById('clear-filters').addEventListener('click', clearFilters);
}

function handlePathwayFilterChange() {
    const pathway = document.getElementById('filter-pathway').value;

    // Sync with causal chain nodes
    document.querySelectorAll('.chain-node').forEach(node => {
        if (node.dataset.pathway === pathway) {
            node.classList.add('active');
        } else {
            node.classList.remove('active');
        }
    });

    applyFilters();
}

export function applyFilters() {
    const search = document.getElementById('search').value.toLowerCase().trim();
    const timeOfDay = document.getElementById('filter-timeOfDay').value;
    const evidenceLevel = document.getElementById('filter-evidenceLevel').value;
    const roiTier = document.getElementById('filter-roiTier').value;
    const tier = document.getElementById('filter-tier').value;
    const condition = document.getElementById('filter-condition').value;
    const pathway = document.getElementById('filter-pathway').value;

    let filtered = allInterventions.filter(intervention => {
        // Search filter
        if (search) {
            const searchFields = [
                intervention.name,
                intervention.description,
                intervention.detailedDescription,
                intervention.evidenceSummary
            ].join(' ').toLowerCase();

            if (!searchFields.includes(search)) {
                return false;
            }
        }

        // Time of day filter
        if (timeOfDay && !intervention.timeOfDay.includes(timeOfDay)) {
            return false;
        }

        // Evidence level filter
        if (evidenceLevel && !intervention.evidenceLevel.includes(evidenceLevel)) {
            return false;
        }

        // ROI tier filter
        if (roiTier && intervention.roiTier !== roiTier) {
            return false;
        }

        // Priority tier filter
        if (tier && intervention.tier !== parseInt(tier)) {
            return false;
        }

        // Condition filter
        if (condition && intervention.targetCondition !== condition) {
            return false;
        }

        // Pathway filter
        if (pathway && intervention.causalPathway !== pathway) {
            return false;
        }

        return true;
    });

    // Store filtered interventions
    filteredInterventions = filtered;

    // Update filter count
    const countEl = document.getElementById('filter-count');
    if (filtered.length === allInterventions.length) {
        countEl.textContent = `Showing all ${allInterventions.length} interventions`;
    } else {
        countEl.textContent = `Showing ${filtered.length} of ${allInterventions.length} interventions`;
    }

    // Re-render with filtered data
    if (renderCallback) {
        renderCallback(filtered);
    }

    // Also update scatter plot if callback provided
    if (scatterCallback) {
        scatterCallback(filtered);
    }
}

export function getFilteredInterventions() {
    return filteredInterventions;
}

function clearFilters() {
    document.getElementById('search').value = '';
    document.getElementById('filter-timeOfDay').value = '';
    document.getElementById('filter-evidenceLevel').value = '';
    document.getElementById('filter-roiTier').value = '';
    document.getElementById('filter-tier').value = '';
    document.getElementById('filter-condition').value = '';
    document.getElementById('filter-pathway').value = '';

    // Clear causal chain active states
    document.querySelectorAll('.chain-node').forEach(node => {
        node.classList.remove('active');
    });

    applyFilters();
}
