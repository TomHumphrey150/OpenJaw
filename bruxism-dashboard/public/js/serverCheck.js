const HEALTH_ENDPOINT = '/api/health';
const CHECK_TIMEOUT = 3000;
const POLL_INTERVAL = 5000;

export async function checkServerHealth() {
    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), CHECK_TIMEOUT);

        const response = await fetch(HEALTH_ENDPOINT, {
            signal: controller.signal
        });

        clearTimeout(timeoutId);
        return response.ok;
    } catch (error) {
        return false;
    }
}

export function showServerError() {
    document.getElementById('server-error-banner').classList.remove('hidden');
    document.getElementById('loading').classList.add('hidden');
    document.getElementById('app').classList.add('hidden');

    // Start polling for server
    startServerPolling();
}

export function showLoading() {
    document.getElementById('loading').classList.remove('hidden');
    document.getElementById('server-error-banner').classList.add('hidden');
    document.getElementById('app').classList.add('hidden');
}

export function showApp() {
    document.getElementById('app').classList.remove('hidden');
    document.getElementById('loading').classList.add('hidden');
    document.getElementById('server-error-banner').classList.add('hidden');
}

function startServerPolling() {
    let countdown = POLL_INTERVAL / 1000;
    const countdownEl = document.getElementById('retry-countdown');

    const updateCountdown = () => {
        if (countdownEl) {
            countdownEl.textContent = `(retrying in ${countdown}s)`;
        }
        countdown--;

        if (countdown < 0) {
            countdown = POLL_INTERVAL / 1000;
            checkAndReload();
        }
    };

    const checkAndReload = async () => {
        const serverOk = await checkServerHealth();
        if (serverOk) {
            location.reload();
        }
    };

    updateCountdown();
    setInterval(updateCountdown, 1000);
}
