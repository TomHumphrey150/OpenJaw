import { checkServerHealth, showServerError, showLoading, showApp } from './serverCheck.js';
import { initCausalEditor } from './causalEditor.js';
import * as storage from './storage.js';

async function init() {
    showLoading();

    const serverOk = await checkServerHealth();
    if (!serverOk) {
        showServerError();
        return;
    }

    try {
        const [interventionsRes, infoRes] = await Promise.all([
            fetch('/api/interventions'),
            fetch('/api/bruxism-info')
        ]);

        if (!interventionsRes.ok || !infoRes.ok) {
            throw new Error('Failed to fetch data');
        }

        const interventionsData = await interventionsRes.json();
        const bruxismInfoData = await infoRes.json();

        showApp();

        // Set disclaimer
        const disclaimerEl = document.getElementById('disclaimer');
        if (disclaimerEl && bruxismInfoData.disclaimer) {
            disclaimerEl.textContent = bruxismInfoData.disclaimer;
        }

        // Initialize causal graph + defense check-in
        initCausalEditor(interventionsData.interventions);

        // Data management modal
        setupDataManagement();

    } catch (error) {
        console.error('Failed to load data:', error);
        showServerError();
    }
}

function setupDataManagement() {
    const dataBtn = document.getElementById('data-management-btn');
    const modal = document.getElementById('data-modal');
    const closeBtn = document.getElementById('close-modal-btn');
    const exportBtn = document.getElementById('export-data-btn');
    const importBtn = document.getElementById('import-data-btn');
    const importInput = document.getElementById('import-file');
    const clearBtn = document.getElementById('clear-data-btn');

    dataBtn.addEventListener('click', () => modal.classList.remove('hidden'));
    closeBtn.addEventListener('click', () => modal.classList.add('hidden'));
    modal.addEventListener('click', (e) => {
        if (e.target === modal) modal.classList.add('hidden');
    });

    exportBtn.addEventListener('click', () => storage.downloadExport());

    importBtn.addEventListener('click', () => importInput.click());
    importInput.addEventListener('change', async (e) => {
        const file = e.target.files[0];
        if (!file) return;
        try {
            const text = await file.text();
            const result = storage.importData(text);
            if (result.success) {
                alert('Data imported successfully! Reloading...');
                window.location.reload();
            } else {
                alert('Invalid data format: ' + (result.errors ? result.errors.join(', ') : 'Unknown error'));
            }
        } catch (err) {
            alert('Error reading file: ' + err.message);
        }
        importInput.value = '';
        modal.classList.add('hidden');
    });

    clearBtn.addEventListener('click', () => {
        if (confirm('Are you sure you want to clear all personal data? This cannot be undone.')) {
            storage.clearData();
            alert('All personal data has been cleared.');
            modal.classList.add('hidden');
            window.location.reload();
        }
    });
}

document.addEventListener('DOMContentLoaded', init);
