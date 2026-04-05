const resourceName = window.GetParentResourceName ? GetParentResourceName() : 'ascension_bank';

const state = {
    mode: 'bank',
    bank: null,
    activeTab: 'operations',
    market: null,
    tradeFilter: 'all',
    marketLoaded: false,
};

const TRADE_FILTERS = [
    { id: 'all', label: 'Tous' },
    { id: 'bluechip', label: 'Blue chips' },
    { id: 'index', label: 'Indices' },
    { id: 'equity', label: 'Entreprises' },
    { id: 'alt', label: 'Altcoins' },
    { id: 'volatile', label: 'Volatils' },
    { id: 'meme_risk', label: 'Mèmes' },
    { id: 'commodity', label: 'Métaux' },
    { id: 'oil', label: 'Énergie' },
    { id: 'institutional', label: 'Instit.' },
];

const body = document.body;
const modeText = document.getElementById('modeText');
const accessPill = document.getElementById('accessPill');
const ibanValue = document.getElementById('ibanValue');
const ownerValue = document.getElementById('ownerValue');
const mainShell = document.getElementById('mainShell');
const bankBalance = document.getElementById('bankBalance');
const heroMetaLine = document.getElementById('heroMetaLine');
const transactionCount = document.getElementById('transactionCount');
const cardSummary = document.getElementById('cardSummary');
const cardIban = document.getElementById('cardIban');
const cardOwner = document.getElementById('cardOwner');
const cardSerial = document.getElementById('cardSerial');
const cardStateText = document.getElementById('cardStateText');
const cardPanelState = document.getElementById('cardPanelState');
const cardPanelIban = document.getElementById('cardPanelIban');
const cardPanelOwner = document.getElementById('cardPanelOwner');
const cardPanelSerial = document.getElementById('cardPanelSerial');
const transactions = document.getElementById('transactions');
const depositCard = document.getElementById('depositCard');
const transferCard = document.getElementById('transferCard');
const tradeTabBtn = document.getElementById('tradeTabBtn');
const buyCardButton = document.getElementById('buyCardButton');
const replaceCardButton = document.getElementById('replaceCardButton');
const buyCardButtonAlt = document.getElementById('buyCardButtonAlt');
const replaceCardButtonAlt = document.getElementById('replaceCardButtonAlt');
const statusMessage = document.getElementById('statusMessage');
let statusTimer = null;

async function nui(action, data = {}) {
    const response = await fetch(`https://${resourceName}/${action}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    });
    return response.json();
}

function money(value) {
    return new Intl.NumberFormat('fr-FR').format(Number(value || 0));
}

function moneyDec(value) {
    return new Intl.NumberFormat('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 4 }).format(Number(value || 0));
}

function tradePositionMetrics(a) {
    const units = Number(a.units) || 0;
    const avg = Number(a.avgBuy) || 0;
    const mv = Number(a.marketValue) || 0;
    let ur = Number(a.unrealized);
    if (!Number.isFinite(ur)) ur = mv - units * avg;
    const cost = units * avg;
    const plPct = cost > 0.5 ? (ur / cost) * 100 : 0;
    return { units, avg, mv, ur, cost, plPct };
}

function setTab(tab) {
    state.activeTab = tab;
    document.querySelectorAll('.tab').forEach((button) => {
        const on = button.dataset.tab === tab;
        button.classList.toggle('active', on);
        button.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    document.querySelectorAll('.tab-panel').forEach((panel) => {
        panel.classList.toggle('active', panel.dataset.panel === tab);
    });
    if (mainShell) {
        mainShell.classList.toggle('shell--trade', tab === 'trade' && state.mode === 'bank');
    }
    if (tab === 'trade' && state.mode === 'bank') {
        loadMarket();
    }
}

async function loadMarket() {
    const res = await nui('marketBootstrap');
    if (res.ok && res.market) {
        state.market = res.market;
        state.marketLoaded = true;
        renderTradeFilters();
        renderTradeList();
    } else {
        state.market = null;
        const el = document.getElementById('tradeList');
        if (el) el.innerHTML = '<div class="trade-item"><p class="trade-item__blurb">Marché indisponible.</p></div>';
    }
}

function renderTradeFilters() {
    const row = document.getElementById('tradeFilterRow');
    if (!row) return;
    row.innerHTML = TRADE_FILTERS.map((f) => (
        `<button type="button" class="trade-chip${f.id === state.tradeFilter ? ' on' : ''}" data-fid="${f.id}">${f.label}</button>`
    )).join('');
    row.querySelectorAll('.trade-chip').forEach((btn) => {
        btn.addEventListener('click', () => {
            state.tradeFilter = btn.getAttribute('data-fid') || 'all';
            renderTradeFilters();
            renderTradeList();
        });
    });
}

function assetMatchesFilter(a) {
    if (state.tradeFilter === 'all') return true;
    return a.filterGroup === state.tradeFilter;
}

function renderTradeList() {
    const list = document.getElementById('tradeList');
    if (!list || !state.market || !state.market.assets) return;
    const assets = state.market.assets.filter(assetMatchesFilter);
    list.innerHTML = assets.length ? assets.map((a) => {
        const chg = Number(a.changePct || 0);
        const chgCls = chg >= 0 ? 'positive' : 'negative';
        const isPrime = a.id === 'CEDRIC_PT';
        const primeBadge = isPrime ? '<span class="trade-item__badge">Prime</span>' : '';
        const itemCls = `trade-item${isPrime ? ' trade-item--prime' : ''}`;
        const pm = tradePositionMetrics(a);
        const posExtra = pm.units > 0.000001
            ? `<div class="trade-item__position">
                <span><strong>Investi</strong> $${money(pm.cost)}</span>
                <span><strong>PRU</strong> $${moneyDec(pm.avg)}</span>
                <span><strong>P/L</strong> <span class="${pm.ur >= 0 ? 'positive' : 'negative'}">${pm.ur >= 0 ? '+' : ''}$${money(pm.ur)} (${pm.plPct >= 0 ? '+' : ''}${pm.plPct.toFixed(2)} %)</span></span>
               </div>`
            : '';
        return `
            <div class="${itemCls}" data-aid="${a.id}" role="listitem">
                <div class="trade-item__top">
                    <h4 class="trade-item__name">${escapeHtml(a.label)}${primeBadge}</h4>
                    <span class="trade-item__price">$${moneyDec(a.price)}</span>
                </div>
                <div class="trade-item__stats">
                    <span class="${chgCls}">Δ jour ${chg >= 0 ? '+' : ''}${chg.toFixed(2)} %</span>
                    · Pos. ${moneyDec(a.units)} u. · Valo $${money(a.marketValue)}
                    ${a.maxExposure != null ? ` · Max $${money(a.maxExposure)}` : ''}
                </div>
                ${posExtra}
                ${a.blurb ? `<p class="trade-item__blurb">${escapeHtml(a.blurb)}</p>` : ''}
                <div class="trade-item__row">
                    <input type="number" min="1" class="inp trade-amt" data-aid="${a.id}" placeholder="Montant $ (banque)" inputmode="numeric">
                    <button type="button" class="btn btn-primary btn-xs trade-buy" data-aid="${a.id}">Acheter</button>
                    <button type="button" class="btn btn-ghost btn-xs trade-sell" data-aid="${a.id}">Vendre</button>
                </div>
            </div>
        `;
    }).join('') : '<div class="trade-item"><p class="trade-item__blurb">Aucun actif dans ce filtre.</p></div>';

    list.querySelectorAll('.trade-buy').forEach((btn) => {
        btn.addEventListener('click', () => doTrade(btn.getAttribute('data-aid'), 'buy'));
    });
    list.querySelectorAll('.trade-sell').forEach((btn) => {
        btn.addEventListener('click', () => doTrade(btn.getAttribute('data-aid'), 'sell'));
    });
}

function tradeRowSelector(aid) {
    return `.trade-item[data-aid="${aid}"]`;
}

function escapeHtml(s) {
    return String(s || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

async function doTrade(assetId, kind) {
    const row = document.querySelector(tradeRowSelector(assetId));
    const inp = row && row.querySelector('.trade-amt');
    const amt = Math.floor(Number(inp && inp.value));
    if (!Number.isFinite(amt) || amt <= 0) {
        setStatus('Montant invalide.', 'error');
        return;
    }
    const action = kind === 'buy' ? 'marketBuy' : 'marketSell';
    const res = await nui(action, { assetId, amount: amt });
    if (res.ok) {
        state.market = res.market;
        await refreshBankQuiet();
        renderTradeList();
        setStatus(kind === 'buy' ? 'Ordre exécuté (banque).' : 'Vente créditée en banque.', 'success');
        if (inp) inp.value = '';
    } else {
        setStatus(res.error || 'Ordre refusé.', 'error');
    }
}

async function refreshBankQuiet() {
    const response = await nui('refresh');
    if (response.ok) {
        state.bank = response.bank;
        if (bankBalance) bankBalance.textContent = `$${money(state.bank.balances.bank)}`;
        if (heroMetaLine) heroMetaLine.textContent = `Cash · $${money(state.bank.balances.cash)}`;
    }
}

function setStatus(text, type = 'info') {
    if (!statusMessage) return;
    statusMessage.textContent = text || '';
    statusMessage.dataset.type = type;
    statusMessage.classList.toggle('show', !!text);
    if (statusTimer) clearTimeout(statusTimer);
    if (text) {
        statusTimer = setTimeout(() => statusMessage.classList.remove('show'), 3200);
    }
}

function renderTransactions() {
    const rows = state.bank.transactions || [];
    transactionCount.textContent = String(rows.length);
    transactions.innerHTML = rows.length ? rows.map((entry) => {
        const positive = ['deposit', 'transfer_in', 'trade_sell'].includes(entry.transaction_type);
        const label = entry.reason || entry.transaction_type || 'Transaction';
        const counterparty = [entry.counterparty_name, entry.counterparty_iban].filter(Boolean).join(' • ');
        return `
            <div class="tx">
                <div>
                    <strong>${label}</strong>
                    <small>${counterparty || '—'}</small>
                    <small>${entry.created_at || ''}</small>
                </div>
                <div>
                    <strong class="${positive ? 'positive' : 'negative'}">${positive ? '+' : '-'}$${money(entry.amount)}</strong>
                    <small>Solde: $${money(entry.balance_after)}</small>
                </div>
            </div>
        `;
    }).join('') : '<div class="tx"><div><strong>Aucune transaction</strong></div></div>';
}

function renderCard() {
    const card = state.bank.card || {};
    cardIban.textContent = state.bank.account.iban;
    cardOwner.textContent = state.bank.account.owner;
    cardSerial.textContent = card.hasCard ? (card.serial || '—') : 'Aucune carte';
    cardPanelIban.textContent = state.bank.account.iban;
    cardPanelOwner.textContent = state.bank.account.owner;
    cardPanelSerial.textContent = card.hasCard ? (card.serial || '—') : '—';
    cardSummary.textContent = card.hasCard ? 'Active' : 'Inactive';
    const stateText = card.hasCard
        ? `Rempl. $${money(card.replacementPrice)}`
        : `Achat $${money(card.price)}`;
    cardStateText.textContent = stateText;
    cardPanelState.textContent = stateText;
    const disableBuy = !!card.hasCard || state.mode === 'atm';
    const disableReplace = !card.hasCard || state.mode === 'atm';
    buyCardButton.disabled = disableBuy;
    buyCardButtonAlt.disabled = disableBuy;
    replaceCardButton.disabled = disableReplace;
    replaceCardButtonAlt.disabled = disableReplace;
}

function renderMode() {
    const isAtm = state.mode === 'atm';
    modeText.textContent = isAtm ? 'Distributeur' : 'Agence';
    if (accessPill) accessPill.textContent = isAtm ? 'ATM' : 'Agence';
    if (mainShell) mainShell.classList.toggle('atm-mode', isAtm);
    if (depositCard) depositCard.style.display = isAtm ? 'none' : '';
    if (transferCard) transferCard.style.display = isAtm ? 'none' : '';
    if (tradeTabBtn) tradeTabBtn.style.display = isAtm ? 'none' : '';
    if (isAtm && state.activeTab === 'trade') setTab('operations');
    if (isAtm && state.activeTab === 'card') setTab('operations');
    if (mainShell && !isAtm) {
        mainShell.classList.toggle('shell--trade', state.activeTab === 'trade');
    } else if (mainShell && isAtm) {
        mainShell.classList.remove('shell--trade');
    }
}

function render() {
    if (!state.bank) return;
    renderMode();
    ibanValue.textContent = state.bank.account.iban;
    ownerValue.textContent = state.bank.account.owner;
    bankBalance.textContent = `$${money(state.bank.balances.bank)}`;
    if (heroMetaLine) heroMetaLine.textContent = `Cash · $${money(state.bank.balances.cash)}`;
    const depLimit = state.bank.settings && state.bank.settings.depositLimit != null
        ? state.bank.settings.depositLimit
        : 20000;
    const depHint = document.getElementById('depositLimitHint');
    if (depHint) depHint.textContent = `Dépôt max. par opération : $${money(depLimit)}`;
    const depInput = document.getElementById('depositAmount');
    if (depInput) depInput.max = String(depLimit);
    renderCard();
    renderTransactions();
    document.querySelectorAll('.tab').forEach((button) => {
        const on = button.dataset.tab === state.activeTab;
        button.classList.toggle('active', on);
        button.setAttribute('aria-selected', on ? 'true' : 'false');
    });
    document.querySelectorAll('.tab-panel').forEach((panel) => {
        panel.classList.toggle('active', panel.dataset.panel === state.activeTab);
    });
    if (state.activeTab === 'trade' && state.mode === 'bank' && state.market) {
        renderTradeFilters();
        renderTradeList();
    }
}

async function refreshBank() {
    const response = await nui('refresh');
    if (response.ok) {
        state.bank = response.bank;
        render();
        setStatus('Compte actualisé.', 'success');
        return;
    }
    setStatus(response.error || 'Erreur.', 'error');
}

async function performCardAction(action) {
    const response = await nui(action);
    if (response.ok) {
        state.bank = response.bank;
        render();
        setStatus(action === 'buyCard' ? 'Carte achetée.' : 'Carte remplacée.', 'success');
        return;
    }
    setStatus(response.error || 'Impossible.', 'error');
}

window.addEventListener('message', (event) => {
    const { action, payload } = event.data;
    if (action === 'open') {
        state.mode = payload.mode || 'bank';
        state.bank = payload.bank;
        state.activeTab = 'operations';
        state.market = null;
        state.marketLoaded = false;
        body.classList.remove('ui-hidden');
        setStatus('', 'info');
        render();
        return;
    }
    if (action === 'close') {
        body.classList.add('ui-hidden');
    }
});

document.getElementById('closeButton').addEventListener('click', async () => {
    await nui('close');
    body.classList.add('ui-hidden');
});
document.getElementById('refreshButton').addEventListener('click', refreshBank);

document.getElementById('depositButton').addEventListener('click', async () => {
    const amount = Number(document.getElementById('depositAmount').value);
    if (!Number.isFinite(amount) || amount <= 0) {
        setStatus('Montant invalide.', 'error');
        return;
    }
    const response = await nui('deposit', { amount });
    if (response.ok) {
        state.bank = response.bank;
        document.getElementById('depositAmount').value = '';
        render();
        setStatus('Dépôt effectué.', 'success');
        return;
    }
    setStatus(response.error || 'Échec.', 'error');
});

document.getElementById('withdrawButton').addEventListener('click', async () => {
    const amount = Number(document.getElementById('withdrawAmount').value);
    if (!Number.isFinite(amount) || amount <= 0) {
        setStatus('Montant invalide.', 'error');
        return;
    }
    const response = await nui('withdraw', { amount, context: state.mode === 'atm' ? 'atm' : 'bank' });
    if (response.ok) {
        state.bank = response.bank;
        document.getElementById('withdrawAmount').value = '';
        render();
        setStatus('Retrait effectué.', 'success');
        return;
    }
    setStatus(response.error || 'Échec.', 'error');
});

document.getElementById('transferButton').addEventListener('click', async () => {
    const iban = document.getElementById('transferIban').value.trim();
    const amount = Number(document.getElementById('transferAmount').value);
    if (!iban) {
        setStatus('IBAN requis.', 'error');
        return;
    }
    if (!Number.isFinite(amount) || amount <= 0) {
        setStatus('Montant invalide.', 'error');
        return;
    }
    const response = await nui('transfer', {
        iban,
        amount,
        reason: document.getElementById('transferReason').value,
    });
    if (response.ok) {
        state.bank = response.bank;
        document.getElementById('transferIban').value = '';
        document.getElementById('transferAmount').value = '';
        document.getElementById('transferReason').value = '';
        render();
        setTab('history');
        setStatus('Virement envoyé.', 'success');
        return;
    }
    setStatus(response.error || 'Échec.', 'error');
});

buyCardButton.addEventListener('click', () => performCardAction('buyCard'));
buyCardButtonAlt.addEventListener('click', () => performCardAction('buyCard'));
replaceCardButton.addEventListener('click', () => performCardAction('replaceCard'));
replaceCardButtonAlt.addEventListener('click', () => performCardAction('replaceCard'));

document.querySelectorAll('.tab').forEach((button) => {
    button.addEventListener('click', () => setTab(button.dataset.tab));
});

window.addEventListener('keydown', async (event) => {
    if (event.key === 'Escape') {
        await nui('close');
        body.classList.add('ui-hidden');
    }
});
