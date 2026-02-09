/**
 * Experiments Tab Module
 * Handles personal experiment tracking
 */

import * as storage from './storage.js';

let allInterventions = [];
let currentObservationRating = 3;

export function initExperiments(interventions) {
    allInterventions = interventions;

    // Set up start experiment modal
    document.getElementById('start-experiment-btn').addEventListener('click', openStartExperimentModal);
    document.querySelectorAll('.close-experiment').forEach(btn => {
        btn.addEventListener('click', closeStartExperimentModal);
    });
    document.getElementById('start-experiment-form').addEventListener('submit', handleStartExperiment);

    // Set up observation modal
    document.querySelectorAll('.close-observation').forEach(btn => {
        btn.addEventListener('click', closeObservationModal);
    });
    document.getElementById('add-observation-form').addEventListener('submit', handleAddObservation);

    // Set up star rating
    const stars = document.querySelectorAll('#observation-rating span');
    stars.forEach(star => {
        star.addEventListener('click', () => {
            currentObservationRating = parseInt(star.dataset.value);
            updateStarDisplay();
        });
    });

    // Populate intervention dropdown
    populateInterventionDropdown();

    // Initial render
    renderExperiments();
    renderEffectivenessGrid();
}

function populateInterventionDropdown() {
    const select = document.getElementById('experiment-intervention');
    select.innerHTML = '<option value="">Choose an intervention...</option>';

    // Get interventions that don't have active experiments
    const activeExperiments = storage.getActiveExperiments();
    const activeInterventionIds = new Set(activeExperiments.map(e => e.interventionId));

    allInterventions.forEach(intervention => {
        if (!activeInterventionIds.has(intervention.id)) {
            const option = document.createElement('option');
            option.value = intervention.id;
            option.textContent = `${intervention.emoji} ${intervention.name}`;
            select.appendChild(option);
        }
    });
}

export function renderExperiments() {
    const activeContainer = document.getElementById('active-experiments');
    const completedContainer = document.getElementById('completed-experiments');

    const active = storage.getActiveExperiments();
    const completed = storage.getCompletedExperiments();

    // Render active experiments
    if (active.length === 0) {
        activeContainer.innerHTML = `
            <div class="empty-state">
                <p>No active experiments</p>
                <p>Start tracking an intervention to see how it works for you.</p>
            </div>
        `;
    } else {
        activeContainer.innerHTML = active.map(exp => renderExperimentCard(exp, true)).join('');
    }

    // Render completed experiments
    if (completed.length === 0) {
        completedContainer.innerHTML = `
            <div class="empty-state">
                <p>No completed experiments yet</p>
            </div>
        `;
    } else {
        completedContainer.innerHTML = completed.map(exp => renderExperimentCard(exp, false)).join('');
    }

    // Add event listeners
    activeContainer.querySelectorAll('.btn-add-observation').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const experimentId = e.target.dataset.experimentId;
            openObservationModal(experimentId);
        });
    });

    activeContainer.querySelectorAll('.btn-complete').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const experimentId = e.target.dataset.experimentId;
            handleCompleteExperiment(experimentId);
        });
    });

    activeContainer.querySelectorAll('.btn-abandon').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const experimentId = e.target.dataset.experimentId;
            handleAbandonExperiment(experimentId);
        });
    });
}

function renderExperimentCard(experiment, isActive) {
    const dayCount = getDayCount(experiment.startDate);
    const statusClass = isActive ? 'active' : 'completed';
    const statusLabel = isActive ? '🔬 Active' : '✓ Completed';

    return `
        <div class="experiment-card ${statusClass}">
            <div class="experiment-header">
                <span class="experiment-status ${statusClass}">${statusLabel}</span>
                <h4>${escapeHtml(experiment.interventionName)}</h4>
                <span class="experiment-duration">
                    ${isActive ? `Day ${dayCount}` : `${dayCount} days`}
                </span>
            </div>

            ${renderObservationTimeline(experiment.observations)}

            ${experiment.summary ? `
                <div class="experiment-summary">
                    <strong>Summary:</strong> ${escapeHtml(experiment.summary)}
                </div>
            ` : ''}

            ${experiment.effectiveness && experiment.effectiveness !== 'untested' ? `
                <div class="experiment-outcome">
                    <span class="effectiveness-badge ${experiment.effectiveness}">
                        ${getEffectivenessLabel(experiment.effectiveness)}
                    </span>
                </div>
            ` : ''}

            ${isActive ? `
                <div class="experiment-actions">
                    <button class="btn-add-observation" data-experiment-id="${experiment.id}">+ Add Observation</button>
                    <button class="btn-complete" data-experiment-id="${experiment.id}">Complete</button>
                    <button class="btn-abandon" data-experiment-id="${experiment.id}">Abandon</button>
                </div>
            ` : ''}
        </div>
    `;
}

function renderObservationTimeline(observations) {
    if (!observations || observations.length === 0) {
        return '<div class="observation-timeline"><p style="color: var(--text-muted); font-size: 13px;">No observations yet</p></div>';
    }

    // Sort by date descending (newest first)
    const sorted = [...observations].sort((a, b) => new Date(b.date) - new Date(a.date));

    // Show only last 3 observations
    const recent = sorted.slice(0, 3);

    return `
        <div class="observation-timeline">
            ${recent.map(obs => `
                <div class="observation">
                    <span class="date">${formatDate(obs.date)}</span>
                    ${obs.rating ? `<span class="rating">${'⭐'.repeat(obs.rating)}</span>` : ''}
                    <p>${escapeHtml(obs.note)}</p>
                </div>
            `).join('')}
            ${sorted.length > 3 ? `<p style="color: var(--text-muted); font-size: 11px; margin-top: 8px;">+ ${sorted.length - 3} more observations</p>` : ''}
        </div>
    `;
}

export function renderEffectivenessGrid() {
    const container = document.getElementById('effectiveness-grid');
    const ratings = storage.getAllRatings();

    if (ratings.length === 0) {
        container.innerHTML = `
            <div class="empty-state" style="grid-column: 1 / -1;">
                <p>No ratings yet</p>
                <p>Complete experiments to rate interventions.</p>
            </div>
        `;
        return;
    }

    // Get intervention names
    const ratedInterventions = ratings.map(rating => {
        const intervention = allInterventions.find(i => i.id === rating.interventionId);
        return {
            ...rating,
            name: intervention ? intervention.name : rating.interventionId,
            emoji: intervention ? intervention.emoji : '💊'
        };
    });

    container.innerHTML = ratedInterventions.map(r => `
        <div class="effectiveness-item">
            <span class="effectiveness-badge ${r.effectiveness}">${getEffectivenessEmoji(r.effectiveness)}</span>
            <span class="intervention-name">${r.emoji} ${escapeHtml(r.name)}</span>
        </div>
    `).join('');
}

// Modal handlers
function openStartExperimentModal() {
    populateInterventionDropdown();
    document.getElementById('start-experiment-modal').classList.remove('hidden');
}

function closeStartExperimentModal() {
    document.getElementById('start-experiment-modal').classList.add('hidden');
    document.getElementById('start-experiment-form').reset();
}

function handleStartExperiment(e) {
    e.preventDefault();

    const interventionId = document.getElementById('experiment-intervention').value;
    const intervention = allInterventions.find(i => i.id === interventionId);

    if (!intervention) return;

    const experiment = storage.startExperiment(interventionId, intervention.name);

    // Add initial observation if notes provided
    const notes = document.getElementById('experiment-notes').value.trim();
    if (notes) {
        storage.addObservation(experiment.id, notes, 3);
    }

    closeStartExperimentModal();
    renderExperiments();
    renderEffectivenessGrid();
}

function openObservationModal(experimentId) {
    document.getElementById('observation-experiment-id').value = experimentId;
    currentObservationRating = 3;
    updateStarDisplay();
    document.getElementById('add-observation-modal').classList.remove('hidden');
}

function closeObservationModal() {
    document.getElementById('add-observation-modal').classList.add('hidden');
    document.getElementById('add-observation-form').reset();
}

function handleAddObservation(e) {
    e.preventDefault();

    const experimentId = document.getElementById('observation-experiment-id').value;
    const note = document.getElementById('observation-note').value.trim();

    if (!note) return;

    storage.addObservation(experimentId, note, currentObservationRating);
    closeObservationModal();
    renderExperiments();
}

function handleCompleteExperiment(experimentId) {
    const effectiveness = prompt(
        'How effective was this intervention?\n\n' +
        '1 = Works for me\n' +
        '2 = Doesn\'t work\n' +
        '3 = Inconclusive\n\n' +
        'Enter 1, 2, or 3:'
    );

    const effectivenessMap = {
        '1': 'works_for_me',
        '2': 'doesnt_work',
        '3': 'inconclusive'
    };

    if (effectiveness && effectivenessMap[effectiveness]) {
        const summary = prompt('Any final summary? (optional)');
        storage.completeExperiment(experimentId, effectivenessMap[effectiveness], summary || '');
        renderExperiments();
        renderEffectivenessGrid();
    }
}

function handleAbandonExperiment(experimentId) {
    if (confirm('Are you sure you want to abandon this experiment?')) {
        storage.abandonExperiment(experimentId);
        renderExperiments();
    }
}

function updateStarDisplay() {
    const stars = document.querySelectorAll('#observation-rating span');
    stars.forEach((star, index) => {
        star.classList.toggle('active', index < currentObservationRating);
    });
}

// Helper functions
function getDayCount(startDate) {
    const start = new Date(startDate);
    const now = new Date();
    const diffTime = Math.abs(now - start);
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    return diffDays;
}

function formatDate(isoString) {
    const date = new Date(isoString);
    return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

function getEffectivenessLabel(effectiveness) {
    const labels = {
        works_for_me: '✓ Works for me',
        doesnt_work: '✗ Doesn\'t work',
        untested: 'Untested',
        inconclusive: '? Inconclusive'
    };
    return labels[effectiveness] || effectiveness;
}

function getEffectivenessEmoji(effectiveness) {
    const emojis = {
        works_for_me: '✓',
        doesnt_work: '✗',
        untested: '?',
        inconclusive: '~'
    };
    return emojis[effectiveness] || '?';
}

function escapeHtml(text) {
    if (!text) return '';
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}
