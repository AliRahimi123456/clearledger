'use strict';

let state = {
  token: localStorage.getItem('cl_token') || null,
  email: localStorage.getItem('cl_email') || null,
  currentScreen: 'login',
  lastBalance: 0,
};

function $(id) {
  return document.getElementById(id);
}

function showScreen(name) {
  document.querySelectorAll('.screen').forEach((el) => el.classList.remove('active'));
  const screen = $('screen-' + name);
  if (screen) {
    screen.classList.add('active');
  }
  state.currentScreen = name;
}

function showBanner(el, message, type) {
  if (!el) return;
  const bannerClass = type === 'success' ? 'success-banner' : 'error-banner';
  el.className = bannerClass + (message ? '' : ' hidden');
  el.textContent = message || '';
}

function hideBanner(el) {
  if (el) {
    el.classList.add('hidden');
    el.textContent = '';
  }
}

function setLoading(btn, loading, label) {
  if (!btn) return;
  if (loading) {
    btn.dataset.originalText = btn.textContent;
    btn.textContent = '...';
    btn.disabled = true;
    btn.classList.add('loading');
  } else {
    btn.textContent = btn.dataset.originalText || label || btn.textContent;
    btn.disabled = false;
    btn.classList.remove('loading');
  }
}

function friendlyError(detail, status) {
  if (!detail) {
    if (status === 401) return 'Your session has expired. Please sign in again.';
    if (status === 403) return 'You do not have permission to perform this action.';
    if (status === 404) return 'The requested resource was not found.';
    if (status === 409) return 'An account with this email already exists.';
    if (status === 422) return 'Please check your input and try again.';
    if (status >= 500) return 'The server is temporarily unavailable. Try again shortly.';
    return 'Something went wrong. Please try again.';
  }

  if (typeof detail === 'string') {
    const map = {
      'Invalid credentials': 'Incorrect email or password.',
      'Email already registered': 'This email is already registered. Try signing in.',
      Unauthorized: 'Your session has expired. Please sign in again.',
      'amount must be positive': 'Amount must be greater than zero.',
    };
    return map[detail] || detail;
  }

  if (Array.isArray(detail)) {
    return detail.map((d) => d.msg || d.message || String(d)).join('. ');
  }

  return String(detail);
}

function isPublicAuthPath(path) {
  return path === '/auth/login' || path === '/auth/register';
}

async function api(path, options = {}) {
  const publicAuth = isPublicAuthPath(path);
  const headers = {
    'Content-Type': 'application/json',
    ...(options.headers || {}),
  };

  // Never send a stale token on login/register — it can confuse the auth service
  if (state.token && !publicAuth) {
    headers.Authorization = 'Bearer ' + state.token;
  }

  const response = await fetch(path, {
    ...options,
    headers,
  });

  let data = null;
  const text = await response.text();
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = { detail: text };
    }
  }

  if (response.status === 401) {
    if (publicAuth) {
      throw new Error(friendlyError(data?.detail, response.status));
    }
    logout();
    throw new Error('Your session has expired. Please sign in again.');
  }

  if (!response.ok) {
    throw new Error(friendlyError(data?.detail, response.status));
  }

  return data;
}

function formatMoney(amount) {
  const n = Number(amount);
  const formatted = Math.abs(n).toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  return (n < 0 ? '−' : '') + '$' + formatted;
}

function normalizeDirection(direction) {
  const d = String(direction || '').toLowerCase().trim();
  return d === 'credit' ? 'credit' : 'debit';
}

function formatTxAmount(amount, direction) {
  const dir = normalizeDirection(direction);
  const n = Math.abs(Number(amount));
  const formatted = (Number.isFinite(n) ? n : 0).toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  return dir === 'credit' ? '+$' + formatted : '−$' + formatted;
}

const EMPTY_TX_HTML =
  '<div class="empty-state">' +
  '<div class="empty-icon">↕</div>' +
  '<p class="empty-title">No transactions yet</p>' +
  '<p class="empty-sub">Create your first transaction using the form above.</p>' +
  '</div>';

const EMPTY_ALERTS_HTML =
  '<div class="empty-state">' +
  '<div class="empty-icon">✓</div>' +
  '<p class="empty-title">No alerts</p>' +
  '<p class="empty-sub">Transactions over $10,000 trigger a compliance alert.</p>' +
  '</div>';

const TX_SUBMIT_LABEL = 'Submit Transaction';

function formatDate(dateString) {
  if (!dateString) return '';
  const d = new Date(dateString);
  if (Number.isNaN(d.getTime())) return dateString;
  return (
    d.toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
    }) +
    ' at ' +
    d.toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit',
    })
  );
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

async function login(email, password) {
  const btn = $('btn-login');
  const errEl = $('login-error');
  hideBanner(errEl);
  setLoading(btn, true);

  try {
    const data = await api('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    });

    state.token = data.access_token;
    state.email = email;
    localStorage.setItem('cl_token', state.token);
    localStorage.setItem('cl_email', state.email);

    showScreen('dashboard');
    await loadDashboard();
  } catch (err) {
    showBanner(errEl, err.message, 'error');
  } finally {
    setLoading(btn, false, 'Sign In');
  }
}

async function register(email, password) {
  const btn = $('btn-register');
  const errEl = $('register-error');
  hideBanner(errEl);
  setLoading(btn, true);

  try {
    await api('/auth/register', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    });

    $('reg-email').value = '';
    $('reg-password').value = '';
    showScreen('login');
    showBanner($('login-error'), 'Account created. You can sign in now.', 'success');
  } catch (err) {
    showBanner(errEl, err.message, 'error');
  } finally {
    setLoading(btn, false, 'Create Account');
  }
}

function logout() {
  state.token = null;
  state.email = null;
  localStorage.removeItem('cl_token');
  localStorage.removeItem('cl_email');
  showScreen('login');
}

function setSeedOverlay(visible) {
  const el = $('seed-overlay');
  if (el) el.classList.toggle('hidden', !visible);
}

async function seedDemoData() {
  const transactions = [
    { amount: 4500.0, direction: 'credit', description: 'Salary — Acme Corp' },
    { amount: 1200.0, direction: 'debit', description: 'Rent — May 2026' },
    { amount: 89.99, direction: 'debit', description: 'Netflix Annual' },
    { amount: 234.5, direction: 'debit', description: 'Grocery — Whole Foods' },
    { amount: 500.0, direction: 'credit', description: 'Freelance invoice #142' },
    { amount: 15000.0, direction: 'debit', description: 'Equipment purchase — Dell' },
    { amount: 12000.0, direction: 'debit', description: 'Conference & travel — Q2' },
  ];

  for (const tx of transactions) {
    try {
      await api('/ledger/transactions', {
        method: 'POST',
        body: JSON.stringify({
          amount: tx.amount,
          direction: tx.direction,
          description: tx.description,
        }),
      });
      await new Promise((r) => setTimeout(r, 150));
    } catch (e) {
      console.warn('Seed transaction failed:', tx.description, e);
    }
  }
}

function renderSparkline(transactions) {
  const el = $('balance-sparkline');
  if (!el) return;

  if (!transactions || transactions.length < 2) {
    el.innerHTML = '';
    return;
  }

  const points = [];
  let running = 0;
  const chronological = [...transactions].reverse().slice(-10);

  chronological.forEach((tx) => {
    const dir = normalizeDirection(tx.direction);
    running += dir === 'credit' ? Math.abs(Number(tx.amount)) : -Math.abs(Number(tx.amount));
    points.push(running);
  });

  const width = 120;
  const height = 32;
  const min = Math.min(...points);
  const max = Math.max(...points);
  const range = max - min || 1;

  const coords = points.map((val, i) => {
    const x = (i / (points.length - 1)) * width;
    const y = height - ((val - min) / range) * height;
    return x + ',' + y;
  });

  const color = state.lastBalance >= 0 ? '#10b981' : '#ef4444';
  const polyline = coords.join(' ');
  const last = coords[coords.length - 1].split(',');

  el.innerHTML =
    '<svg width="' +
    width +
    '" height="' +
    height +
    '" viewBox="0 0 ' +
    width +
    ' ' +
    height +
    '" style="overflow:visible">' +
    '<polyline points="' +
    polyline +
    '" fill="none" stroke="' +
    color +
    '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" opacity="0.8"/>' +
    '<circle cx="' +
    last[0] +
    '" cy="' +
    last[1] +
    '" r="3" fill="' +
    color +
    '"/>' +
    '</svg>';
}

async function loadDashboard() {
  $('nav-email').textContent = state.email || '';
  await loadBalance();
  const txs = await loadTransactions();
  await loadAlerts();

  if (!txs || txs.length === 0) {
    setSeedOverlay(true);
    await seedDemoData();
    setSeedOverlay(false);
    await loadBalance();
    await loadTransactions();
    await loadAlerts();
  }
}

async function loadBalance() {
  const data = await api('/ledger/balance');
  const el = $('balance-amount');
  const balance = Number(data.balance);
  state.lastBalance = balance;
  el.textContent = formatMoney(balance);
  el.classList.remove('positive', 'negative');
  if (balance > 0) el.classList.add('positive');
  else if (balance < 0) el.classList.add('negative');

  const updatedEl = $('balance-updated');
  if (updatedEl) {
    const time = new Date().toLocaleTimeString([], {
      hour: '2-digit',
      minute: '2-digit',
    });
    updatedEl.textContent = 'Last updated at ' + time;
  }
}

function updateBalanceCount(count) {
  const el = $('balance-count');
  if (!el) return;
  el.textContent =
    count === 0
      ? '0 transactions'
      : count === 1
        ? '1 transaction'
        : count + ' transactions';
}

function updateDirectionHint() {
  const hint = $('tx-direction-hint');
  const direction = $('tx-direction')?.value;
  if (!hint || !direction) return;
  if (direction === 'credit') {
    hint.textContent = 'Money coming in — salary, payment received';
    hint.className = 'tx-hint hint-credit';
  } else {
    hint.textContent = 'Money going out — rent, purchase, withdrawal';
    hint.className = 'tx-hint hint-debit';
  }
}

async function loadTransactions() {
  const txs = await api('/ledger/transactions');
  const list = $('tx-list');
  const items = txs || [];
  const total = items.length;
  updateBalanceCount(total);

  if (total === 0) {
    list.innerHTML = EMPTY_TX_HTML;
    renderSparkline([]);
    return [];
  }

  const recent = items.slice(0, 10);
  list.innerHTML = recent
    .map((tx) => {
      const dir = normalizeDirection(tx.direction);
      const arrow = dir === 'credit' ? '↑' : '↓';
      const amountText = formatTxAmount(tx.amount, dir);
      const desc = tx.description
        ? escapeHtml(tx.description)
        : '<span class="muted">No description</span>';
      const date = escapeHtml(formatDate(tx.created_at));
      return (
        '<div class="tx-item">' +
        '<div class="tx-main">' +
        '<div class="tx-dir-badge ' +
        escapeHtml(dir) +
        '">' +
        arrow +
        '</div>' +
        '<div class="tx-body"><div class="tx-desc">' +
        desc +
        '</div><div class="tx-date">' +
        date +
        '</div></div></div>' +
        '<div class="tx-amount ' +
        escapeHtml(dir) +
        '">' +
        escapeHtml(amountText) +
        '</div></div>'
      );
    })
    .join('');

  renderSparkline(items);
  return items;
}

async function createTransaction() {
  const btn = $('btn-create-tx');
  const errEl = $('tx-error');
  const okEl = $('tx-success');
  hideBanner(errEl);
  hideBanner(okEl);

  const amount = parseFloat($('tx-amount').value);
  const direction = normalizeDirection($('tx-direction').value);
  const description = $('tx-description').value.trim();

  if (!amount || amount <= 0) {
    showBanner(errEl, 'Please enter an amount greater than zero.', 'error');
    return;
  }

  if (btn.classList.contains('loading')) return;

  btn.classList.add('loading');
  btn.disabled = true;
  btn.textContent = 'Processing...';

  try {
    await api('/ledger/transactions', {
      method: 'POST',
      body: JSON.stringify({
        amount,
        direction,
        description: description || null,
      }),
    });

    $('tx-amount').value = '';
    $('tx-description').value = '';
    showBanner(okEl, 'Transaction created successfully.', 'success');

    await loadBalance();
    await loadTransactions();
    if (amount >= 10000) {
      await loadAlerts();
    }
  } catch (err) {
    showBanner(errEl, err.message, 'error');
  } finally {
    btn.classList.remove('loading');
    btn.disabled = false;
    btn.textContent = TX_SUBMIT_LABEL;
  }
}

async function loadAlerts() {
  const data = await api('/notifications/alerts');
  const alerts = data.alerts || [];
  const list = $('alert-list');
  const badge = $('alert-badge');

  if (alerts.length === 0) {
    list.innerHTML = EMPTY_ALERTS_HTML;
    badge.classList.add('hidden');
    return;
  }

  badge.textContent = String(data.total || alerts.length);
  badge.classList.remove('hidden');

  list.innerHTML = alerts
    .slice()
    .reverse()
    .slice(0, 10)
    .map((alert) => {
      const dir = normalizeDirection(alert.direction);
      return (
        '<div class="alert-item">' +
        '<span class="alert-type-badge">' +
        escapeHtml(alert.type || 'ALERT') +
        '</span>' +
        '<div class="alert-detail">' +
        escapeHtml(formatTxAmount(alert.amount, dir)) +
        ' (' +
        escapeHtml(dir) +
        ')</div>' +
        '<div class="alert-time">' +
        escapeHtml(formatDate(alert.triggered_at)) +
        '</div></div>'
      );
    })
    .join('');
}

document.addEventListener('DOMContentLoaded', async () => {
  $('btn-login').addEventListener('click', () => {
    login($('email').value.trim(), $('password').value);
  });

  $('btn-register').addEventListener('click', () => {
    register($('reg-email').value.trim(), $('reg-password').value);
  });

  $('btn-show-register').addEventListener('click', () => {
    hideBanner($('login-error'));
    showScreen('register');
  });

  $('btn-show-login').addEventListener('click', () => {
    hideBanner($('register-error'));
    showScreen('login');
  });

  $('btn-logout').addEventListener('click', logout);

  $('btn-create-tx').addEventListener('click', createTransaction);

  $('tx-amount')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') createTransaction();
  });

  $('tx-description')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') createTransaction();
  });

  $('tx-direction')?.addEventListener('change', updateDirectionHint);
  updateDirectionHint();

  $('btn-refresh').addEventListener('click', () => {
    Promise.all([loadBalance(), loadTransactions()]).catch((err) => {
      showBanner($('tx-error'), err.message, 'error');
    });
  });

  $('btn-refresh-alerts').addEventListener('click', () => {
    loadAlerts().catch((err) => {
      showBanner($('tx-error'), err.message, 'error');
    });
  });

  $('password').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') login($('email').value.trim(), $('password').value);
  });

  $('reg-password').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') register($('reg-email').value.trim(), $('reg-password').value);
  });

  if (state.token) {
    try {
      const verified = await api('/auth/verify');
      if (verified.email) {
        state.email = verified.email;
        localStorage.setItem('cl_email', state.email);
      }
      showScreen('dashboard');
      await loadDashboard();
    } catch {
      logout();
      hideBanner($('login-error'));
      showScreen('login');
    }
  } else {
    showScreen('login');
  }
});
