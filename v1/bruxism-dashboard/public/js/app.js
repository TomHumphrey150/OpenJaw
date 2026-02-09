import { checkServerHealth, showServerError, showLoading, showApp } from './serverCheck.js';
import { buildCitationMap, renderCitations } from './citations.js';
import { initFilters, applyFilters, getFilteredInterventions } from './filters.js';
import { initResearch } from './research.js';
import { initExperiments, renderExperiments, renderEffectivenessGrid } from './experiments.js';
import { initCausalEditor } from './causalEditor.js';
import * as storage from './storage.js';

let interventionsData = null;
let bruxismInfoData = null;
let citationMap = {};
let currentView = 'list'; // 'list' or 'scatter'
let allCitations = [];

async function init() {
    showLoading();

    // Check server health first
    const serverOk = await checkServerHealth();
    if (!serverOk) {
        showServerError();
        return;
    }

    // Fetch data
    try {
        const [interventionsRes, infoRes] = await Promise.all([
            fetch('/api/interventions'),
            fetch('/api/bruxism-info')
        ]);

        if (!interventionsRes.ok || !infoRes.ok) {
            throw new Error('Failed to fetch data');
        }

        interventionsData = await interventionsRes.json();
        bruxismInfoData = await infoRes.json();

        // Merge citations from both sources
        allCitations = [
            ...(interventionsData.citations || []),
            ...(bruxismInfoData.citations || [])
        ];
        citationMap = buildCitationMap(allCitations);

        // Initialize UI
        showApp();
        initFilters(interventionsData.interventions, renderInterventions, updateScatterIfVisible);
        renderInterventions(interventionsData.interventions);
        renderInfoSections(bruxismInfoData.sections);

        // Set disclaimer
        const disclaimerEl = document.getElementById('disclaimer');
        if (disclaimerEl && bruxismInfoData.disclaimer) {
            disclaimerEl.textContent = bruxismInfoData.disclaimer;
        }

        // Set up tab switching
        setupTabs();

        // Set up causal chain editor (replaces old setupCausalChain)
        initCausalEditor(interventionsData.interventions, applyFilters);

        // Set up view toggle
        setupViewToggle();

        // Initialize Research and Experiments tabs
        initResearch(allCitations);
        initExperiments(interventionsData.interventions);

        // Set up data management modal
        setupDataManagement();

    } catch (error) {
        console.error('Failed to load data:', error);
        showServerError();
    }
}

function setupTabs() {
    const tabButtons = document.querySelectorAll('.tab-button');
    const allTabs = {
        interventions: document.getElementById('interventions-tab'),
        info: document.getElementById('info-tab'),
        research: document.getElementById('research-tab'),
        experiments: document.getElementById('experiments-tab')
    };

    tabButtons.forEach(button => {
        button.addEventListener('click', () => {
            const tab = button.dataset.tab;

            // Update button states
            tabButtons.forEach(btn => btn.classList.remove('active'));
            button.classList.add('active');

            // Hide all tabs
            Object.values(allTabs).forEach(tabEl => {
                if (tabEl) tabEl.classList.remove('active');
            });

            // Show selected tab
            if (allTabs[tab]) {
                allTabs[tab].classList.add('active');
            }

            // Re-render experiments tab when switching to it (for fresh data)
            if (tab === 'experiments') {
                renderExperiments();
                renderEffectivenessGrid();
            }
        });
    });
}

function renderInterventions(interventions) {
    const grid = document.getElementById('interventions-grid');

    // Sort by evidence level (descending)
    const sorted = [...interventions].sort((a, b) => {
        return getEvidenceRank(b.evidenceLevel) - getEvidenceRank(a.evidenceLevel);
    });

    grid.innerHTML = sorted.map(i => renderInterventionCard(i)).join('');

    // Add click handlers for expanding/collapsing
    grid.querySelectorAll('.intervention-card').forEach(card => {
        const header = card.querySelector('.card-header');
        header.addEventListener('click', (e) => {
            // Don't toggle if clicking a link
            if (e.target.tagName === 'A') return;
            card.classList.toggle('expanded');
        });
    });
}

function getEvidenceRank(evidenceLevel) {
    const level = evidenceLevel.toLowerCase();
    if (level.includes('moderate-high')) return 4;
    if (level.includes('low-moderate')) return 2;
    if (level.includes('moderate')) return 3;
    return 1; // Low
}

function renderInterventionCard(intervention) {
    const evidenceClass = getEvidenceClass(intervention.evidenceLevel);
    const conditionClass = intervention.targetCondition || 'general';
    const conditionLabel = getConditionLabel(intervention.targetCondition);

    return `
        <article class="intervention-card" data-id="${intervention.id}">
            <div class="card-header">
                <span class="card-expand-icon">▶</span>
                <span class="card-emoji">${intervention.emoji}</span>
                <div class="card-title-area">
                    <h3 class="card-title">${escapeHtml(intervention.name)}</h3>
                    <div class="card-badges">
                        <span class="condition-badge ${conditionClass}">${conditionLabel}</span>
                        <span class="evidence-badge ${evidenceClass}">${intervention.evidenceLevel}</span>
                    </div>
                </div>
                <div class="card-meta-inline">
                    <span class="meta-item">
                        <span class="roi-badge roi-${intervention.roiTier.toLowerCase()}">${intervention.roiTier}</span>
                    </span>
                    <span class="meta-item">${intervention.timeOfDay[0]}</span>
                    <span class="meta-item">${intervention.estimatedDurationMinutes}m</span>
                </div>
            </div>

            <div class="card-body">
                <p class="card-description">${escapeHtml(intervention.description)}</p>

                <div class="card-details">
                    <details>
                        <summary>Evidence & Rationale</summary>
                        <div class="details-content">
                            <p class="evidence-summary">${escapeHtml(intervention.evidenceSummary)}</p>
                            ${renderCitations(intervention.citationIds, citationMap)}
                        </div>
                    </details>

                    <details>
                        <summary>Detailed Description</summary>
                        <div class="details-content">
                            <p>${escapeHtml(intervention.detailedDescription)}</p>
                            ${intervention.externalLink ? `
                                <a href="${intervention.externalLink}" target="_blank" rel="noopener" class="external-link">
                                    Learn More →
                                </a>
                            ` : ''}
                        </div>
                    </details>
                </div>

                <div class="card-footer">
                    <span class="meta-item">
                        <span class="meta-label">ROI:</span>
                        <span class="roi-badge roi-${intervention.roiTier.toLowerCase()}">${intervention.roiTier}</span>
                    </span>
                    <span class="meta-item">
                        <span class="meta-label">Ease:</span>
                        ${intervention.easeScore}/10
                    </span>
                    <span class="meta-item">
                        <span class="meta-label">Cost:</span>
                        ${intervention.costRange}
                    </span>
                    <span class="meta-item">
                        <span class="meta-label">Time:</span>
                        ${intervention.timeOfDay.join(', ')}
                    </span>
                    <span class="meta-item">
                        <span class="meta-label">Duration:</span>
                        ${intervention.estimatedDurationMinutes} min
                    </span>
                    <span class="meta-item">
                        <span class="meta-label">Tier:</span>
                        ${getTierLabel(intervention.tier)}
                    </span>
                </div>
            </div>
        </article>
    `;
}

function renderInfoSections(sections) {
    const container = document.getElementById('info-sections');
    container.innerHTML = sections.map((section, index) => renderInfoSection(section, index === 0)).join('');

    // Add click handlers for collapsible sections
    container.querySelectorAll('.info-section-header').forEach(header => {
        header.addEventListener('click', () => {
            const section = header.closest('.info-section');
            section.classList.toggle('open');
        });
    });
}

function renderInfoSection(section, isOpen = false) {
    const iconMap = {
        'questionmark.circle.fill': '❓',
        'waveform.path.ecg': '📈',
        'list.bullet.clipboard.fill': '📋',
        'arrow.triangle.branch': '🔀',
        'flame.fill': '🔥',
        'cross.case.fill': '💊',
        'calendar': '📅',
        'book.fill': '📚'
    };

    const icon = iconMap[section.icon] || '📌';

    return `
        <div class="info-section ${isOpen ? 'open' : ''}" data-id="${section.id}">
            <div class="info-section-header">
                <span class="info-section-icon">${icon}</span>
                <h2 class="info-section-title">${escapeHtml(section.title)}</h2>
                <span class="info-section-toggle"></span>
            </div>
            <div class="info-section-content">
                ${section.content.map(content => renderSectionContent(content)).join('')}
            </div>
        </div>
    `;
}

function renderSectionContent(content) {
    switch (content.type) {
        case 'paragraph':
            return `
                <p class="info-paragraph">
                    ${escapeHtml(content.text)}
                    ${renderCitations(content.citationIds, citationMap)}
                </p>
            `;

        case 'bulletList':
            return `
                <ul class="info-bullet-list">
                    ${content.items.map(item => `<li>${escapeHtml(item)}</li>`).join('')}
                </ul>
                ${renderCitations(content.citationIds, citationMap)}
            `;

        case 'treatmentList':
            return `
                <div class="treatment-list">
                    ${content.items.map(item => `
                        <div class="treatment-item">
                            <div class="treatment-name">${escapeHtml(item.name)}</div>
                            <div class="treatment-description">${escapeHtml(item.description)}</div>
                            ${renderCitations(item.citationIds, citationMap)}
                        </div>
                    `).join('')}
                </div>
            `;

        case 'resourceList':
            return `
                <div class="resource-list">
                    ${content.items.map(item => `
                        <div class="resource-item ${item.isPrimary ? 'primary' : ''}">
                            <div>
                                <div class="resource-title">${escapeHtml(item.title)}</div>
                                <div class="resource-subtitle">${escapeHtml(item.subtitle)}</div>
                            </div>
                            <a href="${item.url}" target="_blank" rel="noopener" class="resource-link">
                                Visit →
                            </a>
                        </div>
                    `).join('')}
                </div>
            `;

        default:
            return '';
    }
}

function getEvidenceClass(evidenceLevel) {
    const level = evidenceLevel.toLowerCase();
    if (level.includes('moderate-high')) return 'moderate-high';
    if (level.includes('low-moderate')) return 'low-moderate';
    if (level.includes('moderate')) return 'moderate';
    return 'low';
}

function getTierLabel(tier) {
    switch (tier) {
        case 1: return 'Tier 1';
        case 2: return 'Tier 2';
        case 3: return 'Tier 3';
        default: return `Tier ${tier}`;
    }
}

function getConditionLabel(condition) {
    switch (condition) {
        case 'bruxism': return 'B';
        case 'reflux': return 'R';
        case 'both': return 'B+R';
        case 'general': return 'Gen';
        default: return 'Gen';
    }
}

function setupViewToggle() {
    const listBtn = document.getElementById('list-view-btn');
    const scatterBtn = document.getElementById('scatter-view-btn');
    const grid = document.getElementById('interventions-grid');
    const scatter = document.getElementById('scatter-plot');

    listBtn.addEventListener('click', () => {
        currentView = 'list';
        listBtn.classList.add('active');
        scatterBtn.classList.remove('active');
        grid.style.display = 'flex';
        scatter.classList.add('hidden');
    });

    scatterBtn.addEventListener('click', () => {
        currentView = 'scatter';
        scatterBtn.classList.add('active');
        listBtn.classList.remove('active');
        grid.style.display = 'none';
        scatter.classList.remove('hidden');
        // Use filtered interventions instead of all
        renderScatterPlot(getFilteredInterventions());
    });
}

function updateScatterIfVisible(filteredInterventions) {
    if (currentView === 'scatter') {
        renderScatterPlot(filteredInterventions);
    }
}

function renderScatterPlot(interventions) {
    const chart = document.getElementById('scatter-chart');
    chart.innerHTML = '';

    // Get chart dimensions
    const rect = chart.getBoundingClientRect();
    const width = rect.width || 600;
    const height = rect.height || 350;
    const padding = 20;

    // Find max duration for x-axis scale
    const maxDuration = Math.max(...interventions.map(i => i.estimatedDurationMinutes));
    const xScale = (width - padding * 2) / Math.max(maxDuration, 60);

    interventions.forEach(intervention => {
        const dot = document.createElement('div');
        dot.className = `scatter-dot ${intervention.targetCondition || 'general'}`;

        // Calculate position
        const x = padding + intervention.estimatedDurationMinutes * xScale;
        const evidenceRank = getEvidenceRank(intervention.evidenceLevel);
        const y = height - padding - ((evidenceRank - 0.5) / 4) * (height - padding * 2);

        // Size based on ease score (6-16px)
        const size = 6 + (intervention.easeScore / 10) * 10;

        dot.style.left = `${x - size/2}px`;
        dot.style.top = `${y - size/2}px`;
        dot.style.width = `${size}px`;
        dot.style.height = `${size}px`;

        // Tooltip on hover
        dot.addEventListener('mouseenter', (e) => {
            showTooltip(e, intervention);
        });

        dot.addEventListener('mouseleave', () => {
            hideTooltip();
        });

        // Click to expand in list
        dot.addEventListener('click', () => {
            // Switch to list view and expand this card
            document.getElementById('list-view-btn').click();
            setTimeout(() => {
                const card = document.querySelector(`.intervention-card[data-id="${intervention.id}"]`);
                if (card) {
                    card.classList.add('expanded');
                    card.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }
            }, 100);
        });

        chart.appendChild(dot);
    });
}

function showTooltip(event, intervention) {
    hideTooltip();

    const tooltip = document.createElement('div');
    tooltip.className = 'scatter-tooltip';
    tooltip.innerHTML = `
        <strong>${intervention.name}</strong><br>
        Evidence: ${intervention.evidenceLevel}<br>
        Time: ${intervention.estimatedDurationMinutes} min<br>
        Ease: ${intervention.easeScore}/10
    `;

    const chart = document.getElementById('scatter-chart');
    chart.appendChild(tooltip);

    // Position tooltip
    const rect = event.target.getBoundingClientRect();
    const chartRect = chart.getBoundingClientRect();
    tooltip.style.left = `${rect.left - chartRect.left + 20}px`;
    tooltip.style.top = `${rect.top - chartRect.top - 10}px`;
}

function hideTooltip() {
    const existing = document.querySelector('.scatter-tooltip');
    if (existing) existing.remove();
}

function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

function setupDataManagement() {
    const dataBtn = document.getElementById('data-management-btn');
    const modal = document.getElementById('data-modal');
    const closeBtn = document.getElementById('close-modal-btn');
    const exportBtn = document.getElementById('export-data-btn');
    const importBtn = document.getElementById('import-data-btn');
    const importInput = document.getElementById('import-file');
    const clearBtn = document.getElementById('clear-data-btn');

    // Open modal
    dataBtn.addEventListener('click', () => {
        modal.classList.remove('hidden');
    });

    // Close modal
    closeBtn.addEventListener('click', () => {
        modal.classList.add('hidden');
    });

    // Close on outside click
    modal.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.classList.add('hidden');
        }
    });

    // Export data
    exportBtn.addEventListener('click', () => {
        storage.downloadExport();
    });

    // Import data
    importBtn.addEventListener('click', () => {
        importInput.click();
    });

    importInput.addEventListener('change', async (e) => {
        const file = e.target.files[0];
        if (!file) return;

        try {
            const text = await file.text();
            const result = storage.importData(text);

            if (result.success) {
                alert('Data imported successfully!');
                // Refresh the experiments and research views
                renderExperiments();
                renderEffectivenessGrid();
                // Re-render research if we have the function
                if (typeof window.refreshResearch === 'function') {
                    window.refreshResearch();
                }
            } else {
                alert('Invalid data format: ' + (result.errors ? result.errors.join(', ') : 'Unknown error'));
            }
        } catch (err) {
            alert('Error reading file: ' + err.message);
        }

        // Reset input
        importInput.value = '';
        modal.classList.add('hidden');
    });

    // Clear data
    clearBtn.addEventListener('click', () => {
        if (confirm('Are you sure you want to clear all personal data? This cannot be undone.')) {
            storage.clearData();
            renderExperiments();
            renderEffectivenessGrid();
            alert('All personal data has been cleared.');
            modal.classList.add('hidden');
        }
    });
}

// Initialize the app
document.addEventListener('DOMContentLoaded', init);
