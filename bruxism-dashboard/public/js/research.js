/**
 * Research Tab Module
 * Handles citation display, filtering, and personal studies
 */

import * as storage from './storage.js';

let allCitations = [];
let personalStudies = [];

export function initResearch(citations) {
    allCitations = citations;
    personalStudies = storage.getPersonalStudies();

    // Set up filters
    document.getElementById('research-search').addEventListener('input', renderCitations);
    document.getElementById('filter-causality').addEventListener('change', renderCitations);
    document.getElementById('filter-replication').addEventListener('change', renderCitations);
    document.getElementById('filter-study-type').addEventListener('change', renderCitations);

    // Set up add study modal
    document.getElementById('add-study-btn').addEventListener('click', openAddStudyModal);
    document.querySelectorAll('.close-add-study').forEach(btn => {
        btn.addEventListener('click', closeAddStudyModal);
    });
    document.getElementById('add-study-form').addEventListener('submit', handleAddStudy);

    // Initial render
    renderCitations();
    renderPersonalStudies();
}

export function renderCitations() {
    const container = document.getElementById('citations-list');
    const search = document.getElementById('research-search').value.toLowerCase();
    const causality = document.getElementById('filter-causality').value;
    const replication = document.getElementById('filter-replication').value;
    const studyType = document.getElementById('filter-study-type').value;

    // Filter citations
    let filtered = allCitations.filter(citation => {
        // Search filter
        if (search) {
            const searchText = `${citation.title} ${citation.source} ${citation.keyFindings || ''}`.toLowerCase();
            if (!searchText.includes(search)) return false;
        }

        // Causality filter
        if (causality && citation.causalityType !== causality) return false;

        // Replication filter
        if (replication && citation.replicationStatus !== replication) return false;

        // Study type filter
        if (studyType && citation.type !== studyType) return false;

        return true;
    });

    if (filtered.length === 0) {
        container.innerHTML = `
            <div class="empty-state">
                <p>No citations match your filters</p>
            </div>
        `;
        return;
    }

    container.innerHTML = filtered.map(citation => renderCitationCard(citation, false)).join('');

    // Add event listeners
    container.querySelectorAll('.btn-expand').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const card = e.target.closest('.citation-card');
            const details = card.querySelector('.citation-details');
            details.classList.toggle('hidden');
            e.target.textContent = details.classList.contains('hidden') ? '▶ Details' : '▼ Details';
        });
    });

    container.querySelectorAll('.btn-note').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const citationId = e.target.dataset.citationId;
            toggleNoteForm(citationId);
        });
    });
}

function renderCitationCard(citation, isPersonal = false) {
    const notes = storage.getNotesFor('citation', citation.id);
    const typeLabel = getTypeLabel(citation.type);

    return `
        <div class="citation-card ${isPersonal ? 'personal' : ''}" data-id="${citation.id}">
            <div class="citation-header">
                <span class="citation-type-badge ${citation.type}">${typeLabel}</span>
                <h4 class="citation-title">${escapeHtml(citation.title)}</h4>
            </div>

            <div class="citation-meta">
                ${citation.source} · ${citation.year}
                ${isPersonal ? ' · <em>Personal</em>' : ''}
            </div>

            ${renderStudyBadges(citation)}

            <div class="citation-details hidden">
                ${renderCitationDetails(citation)}
            </div>

            ${notes.length > 0 ? renderNotes(notes) : ''}

            <div class="citation-actions">
                <button class="btn-expand">▶ Details</button>
                <button class="btn-note" data-citation-id="${citation.id}">📝 Add Note</button>
                ${citation.url ? `<a href="${citation.url}" target="_blank" rel="noopener" class="btn-external">View Source →</a>` : ''}
            </div>

            <div class="add-note-form hidden" id="note-form-${citation.id}">
                <input type="text" placeholder="Add a note..." id="note-input-${citation.id}">
                <button onclick="window.addCitationNote('${citation.id}')">Add</button>
            </div>
        </div>
    `;
}

function renderStudyBadges(citation) {
    const badges = [];

    // Sample size badge
    if (citation.sampleSize || citation.sampleSizeNote) {
        const sizeClass = getSampleSizeClass(citation.sampleSize);
        const label = citation.sampleSize ? `n=${citation.sampleSize}` : citation.sampleSizeNote;
        badges.push(`<span class="study-badge sample-size ${sizeClass}" title="Sample size">${label}</span>`);
    }

    // Effect size badge
    if (citation.effectSize) {
        const es = citation.effectSize;
        let label = '';
        if (es.value !== null) {
            label = `${es.type === 'smd' ? 'd' : es.type}=${es.value}`;
        } else if (es.description) {
            label = es.description.substring(0, 20);
        }
        if (label) {
            badges.push(`<span class="study-badge effect-size" title="Effect size: ${es.description || ''}">${label}</span>`);
        }
    }

    // Causality badge
    if (citation.causalityType) {
        const icons = { causal: '🎯', correlational: '📊', mechanistic: '⚙️' };
        const labels = { causal: 'Causal', correlational: 'Correlational', mechanistic: 'Mechanistic' };
        badges.push(`<span class="study-badge causality ${citation.causalityType}" title="${labels[citation.causalityType]}">${icons[citation.causalityType]} ${labels[citation.causalityType]}</span>`);
    }

    // Replication badge
    if (citation.replicationStatus) {
        const icons = { replicated: '✓', single_study: '⚠️', conflicting: '✗' };
        const labels = { replicated: 'Replicated', single_study: 'Single Study', conflicting: 'Conflicting' };
        badges.push(`<span class="study-badge replication ${citation.replicationStatus}" title="${labels[citation.replicationStatus]}">${icons[citation.replicationStatus]} ${labels[citation.replicationStatus]}</span>`);
    }

    if (badges.length === 0) return '';

    return `<div class="study-badges">${badges.join('')}</div>`;
}

function renderCitationDetails(citation) {
    const rows = [];

    if (citation.population) {
        const pop = citation.population;
        if (pop.ageRange) rows.push(detailRow('Age Range', pop.ageRange));
        if (pop.demographics) rows.push(detailRow('Population', pop.demographics));
        if (pop.inclusionCriteria) rows.push(detailRow('Inclusion', pop.inclusionCriteria));
    }

    if (citation.comparisonGroup) {
        rows.push(detailRow('Comparison', citation.comparisonGroup));
    }

    if (citation.primaryOutcome) {
        rows.push(detailRow('Primary Outcome', citation.primaryOutcome));
    }

    if (citation.secondaryOutcomes && citation.secondaryOutcomes.length > 0) {
        rows.push(detailRow('Secondary', citation.secondaryOutcomes.join(', ')));
    }

    if (citation.pValue) {
        rows.push(detailRow('P-Value', `p = ${citation.pValue}`));
    }

    if (citation.keyFindings) {
        rows.push(detailRow('Key Findings', citation.keyFindings));
    }

    if (citation.limitations) {
        rows.push(detailRow('Limitations', citation.limitations));
    }

    if (citation.fundingSource) {
        rows.push(detailRow('Funding', citation.fundingSource));
    }

    if (rows.length === 0) {
        return '<p class="detail-row"><em>No detailed metadata available for this citation.</em></p>';
    }

    return rows.join('');
}

function detailRow(label, value) {
    return `
        <div class="detail-row">
            <span class="label">${label}:</span>
            <span class="value">${escapeHtml(value)}</span>
        </div>
    `;
}

function renderNotes(notes) {
    return `
        <div class="citation-notes">
            ${notes.map(note => `
                <div class="note" data-note-id="${note.id}">
                    <span class="note-content">${escapeHtml(note.content)}</span>
                    <span class="note-date">${formatDate(note.createdAt)}</span>
                    <button class="note-delete" onclick="window.deleteCitationNote('${note.id}')">&times;</button>
                </div>
            `).join('')}
        </div>
    `;
}

function toggleNoteForm(citationId) {
    const form = document.getElementById(`note-form-${citationId}`);
    form.classList.toggle('hidden');
    if (!form.classList.contains('hidden')) {
        form.querySelector('input').focus();
    }
}

// Expose to window for inline handlers
window.addCitationNote = function(citationId) {
    const input = document.getElementById(`note-input-${citationId}`);
    const content = input.value.trim();
    if (content) {
        storage.addNote('citation', citationId, content);
        input.value = '';
        renderCitations();
    }
};

window.deleteCitationNote = function(noteId) {
    storage.deleteNote(noteId);
    renderCitations();
};

function renderPersonalStudies() {
    const container = document.getElementById('personal-studies-list');
    personalStudies = storage.getPersonalStudies();

    if (personalStudies.length === 0) {
        container.innerHTML = `
            <div class="empty-state">
                <p>No personal studies added yet</p>
                <p>Click "Add Personal Study" to track studies you find.</p>
            </div>
        `;
        return;
    }

    container.innerHTML = personalStudies.map(study => renderCitationCard(study, true)).join('');
}

function openAddStudyModal() {
    document.getElementById('add-study-modal').classList.remove('hidden');
}

function closeAddStudyModal() {
    document.getElementById('add-study-modal').classList.add('hidden');
    document.getElementById('add-study-form').reset();
}

function handleAddStudy(e) {
    e.preventDefault();

    const study = {
        title: document.getElementById('study-title').value,
        source: document.getElementById('study-source').value || 'Personal',
        year: parseInt(document.getElementById('study-year').value) || new Date().getFullYear(),
        url: document.getElementById('study-url').value || null,
        type: 'review',
        sampleSize: parseInt(document.getElementById('study-sample-size').value) || null,
        causalityType: document.getElementById('study-causality').value || null,
        keyFindings: document.getElementById('study-findings').value || null,
        personalNotes: document.getElementById('study-notes').value || null
    };

    storage.addStudy(study);
    closeAddStudyModal();
    renderPersonalStudies();
}

// Helper functions
function getTypeLabel(type) {
    const labels = {
        cochrane: 'Cochrane',
        systematicReview: 'Systematic Review',
        metaAnalysis: 'Meta-Analysis',
        rct: 'RCT',
        review: 'Review',
        guideline: 'Guideline',
        observational: 'Observational'
    };
    return labels[type] || type;
}

function getSampleSizeClass(n) {
    if (!n) return '';
    if (n >= 500) return 'large';
    if (n >= 100) return 'medium';
    return 'small';
}

function formatDate(isoString) {
    const date = new Date(isoString);
    return date.toLocaleDateString();
}

function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}
