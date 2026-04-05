/**
 * Ascension Trade — marché filtré, profils de risque, guide intégré
 */
(function () {
    'use strict';

    const ROOT_ID = 'trade-app';
    const FALLBACK_RES = 'ascension_bank';

    const FILTERS = [
        { id: 'all', label: 'Tous' },
        { id: 'bluechip', label: 'Blue chips' },
        { id: 'index', label: 'Indices' },
        { id: 'equity', label: 'Entreprises' },
        { id: 'alt', label: 'Altcoins' },
        { id: 'volatile', label: 'Volatils' },
        { id: 'meme_risk', label: 'Mèmes / extr.' },
        { id: 'commodity', label: 'Métaux' },
        { id: 'oil', label: 'Énergie' },
        { id: 'institutional', label: 'Instit.' },
    ];

    const RISK_LABEL = {
        bluechip: 'Blue chip',
        standard: 'Standard',
        volatile: 'Volatile',
        meme: 'Mème',
        extreme: 'Extrême',
        metal: 'Métal',
        oil: 'Énergie',
        index: 'Indice',
        institutional: 'Instit.',
        stable: 'Stable',
    };

    function getRoot() {
        return document.getElementById(ROOT_ID);
    }

    function getResourceName() {
        var n = globalThis.resourceName;
        return typeof n === 'string' && n.length > 0 ? n : FALLBACK_RES;
    }

    function parseNuiBody(text) {
        if (text == null || text === '') return {};
        var t = String(text).trim();
        if (t === 'ok' || t === '"ok"') return { ok: true };
        try {
            return JSON.parse(t);
        } catch (e) {
            return {};
        }
    }

    async function callResource(event, data) {
        var payload = data ?? {};
        try {
            if (typeof globalThis.fetchNui === 'function') {
                var out = await globalThis.fetchNui(event, payload);
                if (out !== undefined && out !== null) return out;
            }
        } catch (err) {
            console.warn('[Ascension Trade] fetchNui', event, err);
        }
        var res = getResourceName();
        try {
            var response = await fetch('https://' + res + '/' + event, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(payload),
            });
            return parseNuiBody(await response.text());
        } catch (err2) {
            console.error('[Ascension Trade] fetch', event, err2);
            return {};
        }
    }

    function money(n) {
        return new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 0 }).format(Number(n || 0));
    }

    function moneyDec(n) {
        return new Intl.NumberFormat('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 4 }).format(Number(n || 0));
    }

    /** Coût d’entrée, P/L $ et % (latent vs PRU) */
    function positionMetrics(a) {
        var units = Number(a.units) || 0;
        var avg = Number(a.avgBuy) || 0;
        var mv = Number(a.marketValue) || 0;
        var ur = Number(a.unrealized);
        if (!Number.isFinite(ur)) {
            ur = mv - units * avg;
        }
        var cost = units * avg;
        var plPct = cost > 0.5 ? (ur / cost) * 100 : 0;
        return { units: units, avg: avg, mv: mv, ur: ur, cost: cost, plPct: plPct };
    }

    var state = { data: null, filterId: 'all' };
    var refreshTimer = null;

    function toast(msg, type) {
        var el = document.getElementById('toast');
        if (!el) return;
        el.textContent = msg || '';
        el.classList.remove('hidden', 'ok', 'err');
        if (!msg) {
            el.classList.add('hidden');
            return;
        }
        el.classList.add(type === 'err' ? 'err' : 'ok');
        setTimeout(function () {
            el.classList.add('hidden');
        }, 3200);
    }

    function syncThemeFromBody() {
        var root = getRoot();
        if (!root) return;
        var bt = document.body && document.body.getAttribute('data-theme');
        if (bt === 'dark' || bt === 'light') {
            root.dataset.theme = bt;
        }
    }

    function escapeHtml(s) {
        return String(s || '')
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;');
    }

    function tagClassForRisk(rp, cat) {
        var r = rp || 'standard';
        if (r === 'stable') return 'tag stable';
        if (cat === 'index') return 'tag index';
        if (cat === 'equity') return 'tag equity';
        if (r === 'metal' || r === 'oil') return r === 'oil' ? 'tag oil' : 'tag metal';
        if (r === 'institutional') return 'tag institutional';
        if (r === 'bluechip') return 'tag bluechip';
        if (r === 'meme' || r === 'extreme') return r === 'extreme' ? 'tag extreme' : 'tag meme';
        if (r === 'volatile') return 'tag volatile';
        return 'tag standard';
    }

    function riskBadgeText(rp, cat) {
        if (cat === 'index') return RISK_LABEL.index;
        return RISK_LABEL[rp] || rp || '—';
    }

    function assetMatchesFilter(a) {
        if (state.filterId === 'all') return true;
        return a.filterGroup === state.filterId;
    }

    function renderFilterChips() {
        var el = document.getElementById('filterChips');
        if (!el) return;
        el.innerHTML = FILTERS.map(function (f) {
            var on = f.id === state.filterId ? ' chip-on' : '';
            return '<button type="button" class="chip' + on + '" data-fid="' + escapeHtml(f.id) + '">' + escapeHtml(f.label) + '</button>';
        }).join('');
        el.querySelectorAll('.chip').forEach(function (btn) {
            btn.addEventListener('click', function () {
                state.filterId = btn.getAttribute('data-fid') || 'all';
                renderFilterChips();
                renderMarket();
            });
        });
    }

    function renderMarket() {
        var m = document.getElementById('assetScroll');
        if (!m || !state.data || !state.data.assets) return;
        var list = state.data.assets.filter(assetMatchesFilter);
        var html = list.map(function (a) {
            var chg = Number(a.changePct || 0);
            var chgClass = chg >= 0 ? 'chg-up' : 'chg-down';
            var tc = tagClassForRisk(a.riskProfile, a.category);
            var badge = riskBadgeText(a.riskProfile, a.category);
            var isPrime = a.id === 'CEDRIC_PT';
            var cardCls = 'card' + (isPrime ? ' card--prime' : '');
            var primeBadge = isPrime ? '<span class="badge-prime">Prime</span>' : '';
            var blurb = a.blurb ? '<p class="blurb">' + escapeHtml(a.blurb) + '</p>' : '';
            var maxE = a.maxExposure != null ? '<div class="expo-hint">Plafond max. · $' + money(a.maxExposure) + '</div>' : '';
            var pm = positionMetrics(a);
            var posBlock = '';
            if (pm.units > 0.000001) {
                var plCls = pm.ur >= 0 ? 'chg-up' : 'chg-down';
                var plSign = pm.ur >= 0 ? '+' : '';
                var pctSign = pm.plPct >= 0 ? '+' : '';
                posBlock =
                    '<div class="pos-metrics">' +
                    '<div class="pos-metrics__row"><span class="pos-metrics__k">Unités</span><span class="pos-metrics__v">' + moneyDec(pm.units) + '</span></div>' +
                    '<div class="pos-metrics__row"><span class="pos-metrics__k">Investi</span><span class="pos-metrics__v">$' + money(pm.cost) + '</span></div>' +
                    '<div class="pos-metrics__row"><span class="pos-metrics__k">PRU</span><span class="pos-metrics__v">$' + moneyDec(pm.avg) + '</span></div>' +
                    '<div class="pos-metrics__row"><span class="pos-metrics__k">Valo</span><span class="pos-metrics__v">$' + money(pm.mv) + '</span></div>' +
                    '<div class="pos-metrics__row pos-metrics__row--pl"><span class="pos-metrics__k">P/L</span><span class="pos-metrics__v ' + plCls + '">' +
                    plSign + '$' + money(pm.ur) + ' <span class="pos-metrics__pct">(' + pctSign + pm.plPct.toFixed(2) + ' %)</span></span></div>' +
                    '</div>';
            } else {
                posBlock = '<div class="pos-line pos-line--empty"><span><strong>Pos.</strong> 0 u.</span><span><strong>Valo</strong> $0</span></div>';
            }
            return (
                '<article class="' + cardCls + '" data-asset="' + escapeHtml(a.id) + '">' +
                '<div class="card__head">' +
                '<div class="card__title-row">' +
                '<h2>' + escapeHtml(a.label) + '</h2>' + primeBadge +
                '<span class="' + tc + '">' + escapeHtml(badge) + '</span></div>' +
                '<div class="card__price-block">' +
                '<span class="price">$' + moneyDec(a.price) + '</span>' +
                '<span class="chg ' + chgClass + '">Δ jour ' + (chg >= 0 ? '+' : '') + chg.toFixed(2) + ' %</span></div></div>' +
                blurb +
                posBlock +
                maxE +
                '<div class="trade-row-inputs">' +
                '<input type="number" min="1" class="amt-in" placeholder="Montant $" inputmode="numeric" data-asset="' + escapeHtml(a.id) + '" />' +
                '</div>' +
                '<div class="btn-row">' +
                '<button type="button" class="action btn-buy" data-asset="' + escapeHtml(a.id) + '">Acheter</button>' +
                '<button type="button" class="action btn-sell" data-asset="' + escapeHtml(a.id) + '">Vendre</button>' +
                '</div></article>'
            );
        }).join('');
        m.innerHTML = html || '<div class="empty">Aucun actif dans ce filtre.</div>';

        m.querySelectorAll('.btn-buy').forEach(function (btn) {
            btn.addEventListener('click', function () {
                doOrder(btn.getAttribute('data-asset'), 'buy', btn);
            });
        });
        m.querySelectorAll('.btn-sell').forEach(function (btn) {
            btn.addEventListener('click', function () {
                doOrder(btn.getAttribute('data-asset'), 'sell', btn);
            });
        });
    }

    function renderPortfolio() {
        var m = document.getElementById('view-port');
        if (!m || !state.data || !state.data.assets) return;
        var held = state.data.assets.filter(function (a) { return Number(a.units) > 0.000001; });
        if (!held.length) {
            m.innerHTML = '<div class="portfolio-scroll"><div class="empty">Aucune position ouverte.</div></div>';
            return;
        }
        m.innerHTML = '<div class="portfolio-scroll">' + held.map(function (a) {
            var chg = Number(a.changePct || 0);
            var chgClass = chg >= 0 ? 'chg-up' : 'chg-down';
            var tc = tagClassForRisk(a.riskProfile, a.category);
            var badge = riskBadgeText(a.riskProfile, a.category);
            var isPrime = a.id === 'CEDRIC_PT';
            var cardCls = 'card' + (isPrime ? ' card--prime' : '');
            var primeBadge = isPrime ? '<span class="badge-prime">Prime</span>' : '';
            var maxE = a.maxExposure != null ? '<div class="expo-hint">Plafond · $' + money(a.maxExposure) + '</div>' : '';
            var pm = positionMetrics(a);
            var plCls = pm.ur >= 0 ? 'chg-up' : 'chg-down';
            var plSign = pm.ur >= 0 ? '+' : '';
            var pctSign = pm.plPct >= 0 ? '+' : '';
            return (
                '<article class="' + cardCls + '"><div class="card__head">' +
                '<div class="card__title-row"><h2>' + escapeHtml(a.label) + '</h2>' + primeBadge +
                '<span class="' + tc + '">' + escapeHtml(badge) + '</span></div>' +
                '<div class="card__price-block"><span class="chg ' + chgClass + '">Δ ' + chg.toFixed(2) + ' %</span></div></div>' +
                maxE +
                '<div class="pos-metrics pos-metrics--port">' +
                '<div class="pos-metrics__row"><span class="pos-metrics__k">Unités</span><span class="pos-metrics__v">' + moneyDec(pm.units) + '</span></div>' +
                '<div class="pos-metrics__row"><span class="pos-metrics__k">Investi</span><span class="pos-metrics__v">$' + money(pm.cost) + '</span></div>' +
                '<div class="pos-metrics__row"><span class="pos-metrics__k">PRU</span><span class="pos-metrics__v">$' + moneyDec(pm.avg) + '</span></div>' +
                '<div class="pos-metrics__row"><span class="pos-metrics__k">Valo</span><span class="pos-metrics__v">$' + money(pm.mv) + '</span></div>' +
                '<div class="pos-metrics__row pos-metrics__row--pl"><span class="pos-metrics__k">P/L</span><span class="pos-metrics__v ' + plCls + '">' +
                plSign + '$' + money(pm.ur) + ' <span class="pos-metrics__pct">(' + pctSign + pm.plPct.toFixed(2) + ' %)</span></span></div>' +
                '</div>' +
                '<div class="trade-row-inputs">' +
                '<input type="number" min="1" class="amt-in" placeholder="Montant vente $" inputmode="numeric" data-asset="' + escapeHtml(a.id) + '" />' +
                '</div>' +
                '<div class="btn-row"><button type="button" class="action btn-sell" data-sell="' + escapeHtml(a.id) + '">Vendre</button></div></article>'
            );
        }).join('') + '</div>';

        m.querySelectorAll('[data-sell]').forEach(function (btn) {
            btn.addEventListener('click', function () {
                doOrder(btn.getAttribute('data-sell'), 'sell', btn);
            });
        });
    }

    async function doOrder(assetId, kind, buttonEl) {
        var card = buttonEl && buttonEl.closest('.card');
        var inp = card ? card.querySelector('input.amt-in') : null;
        var amt = inp ? Math.floor(Number(inp.value)) : 0;
        if (!Number.isFinite(amt) || amt <= 0) {
            toast('Montant invalide.', 'err');
            return;
        }
        var ev = kind === 'buy' ? 'asc_trade_buy' : 'asc_trade_sell';
        var res = await callResource(ev, { assetId: assetId, amount: amt });
        if (res && res.ok) {
            state.data = res.market;
            applyData();
            toast(kind === 'buy' ? 'Ordre exécuté (banque débitée).' : 'Vente créditée sur votre banque.', 'ok');
        } else {
            toast((res && res.error) || 'Opération refusée.', 'err');
        }
    }

    function applyData() {
        syncThemeFromBody();
        if (!state.data) return;
        var bal = document.getElementById('bankBal');
        if (bal) bal.textContent = '$' + money(state.data.bankBalance);
        var eco = document.getElementById('ecoHint');
        if (eco && state.data.economy) {
            eco.textContent = state.data.economy.hint + ' · Masse bancaire serveur ~ ' + String(state.data.economy.totalBankM) + ' M$';
        }
        var s = state.data.settings || {};
        var foot = document.getElementById('footNote');
        if (foot) {
            var fee = (s.feePercent != null ? s.feePercent : 0.0075) * 100;
            var pmax = s.primeMaxPositionValue != null ? s.primeMaxPositionValue : 65000;
            foot.textContent =
                'Frais ' + fee.toFixed(2) + ' % par ordre. Min. $' + money(s.minOrder) + ', max. $' + money(s.maxOrder) +
                '. Exposition max. $' + money(s.maxPositionValue || 200000) + ' (actifs courants), $' + money(pmax) +
                ' (segment institutionnel). Cotes ~' + (s.tickMinutes || 5) + ' min.';
        }
        renderFilterChips();
        renderMarket();
        renderPortfolio();
    }

    async function bootstrap() {
        var data = await callResource('asc_trade_bootstrap', {});
        if (!data || !data.assets) {
            toast('Connexion au marché impossible.', 'err');
            return;
        }
        state.data = data;
        applyData();
    }

    function refreshMarketFromServer() {
        return callResource('asc_trade_bootstrap', {}).then(function (data) {
            if (data && data.assets) {
                state.data = data;
                applyData();
            }
        });
    }

    function scheduleMarketRefresh() {
        if (refreshTimer) {
            clearTimeout(refreshTimer);
        }
        refreshTimer = setTimeout(function () {
            refreshTimer = null;
            refreshMarketFromServer();
        }, 120);
    }

    function setTab(which) {
        var mkt = document.getElementById('view-mkt');
        var port = document.getElementById('view-port');
        var guide = document.getElementById('view-guide');
        var t1 = document.getElementById('tab-mkt');
        var t2 = document.getElementById('tab-port');
        var t3 = document.getElementById('tab-guide');

        var showM = which === 'mkt';
        var showP = which === 'port';
        var showG = which === 'guide';

        if (mkt) {
            mkt.classList.toggle('hidden', !showM);
            mkt.hidden = !showM;
        }
        if (port) {
            port.classList.toggle('hidden', !showP);
            port.hidden = !showP;
        }
        if (guide) {
            guide.classList.toggle('hidden', !showG);
            guide.hidden = !showG;
        }
        if (t1) {
            t1.classList.toggle('active', showM);
            t1.setAttribute('aria-selected', showM ? 'true' : 'false');
        }
        if (t2) {
            t2.classList.toggle('active', showP);
            t2.setAttribute('aria-selected', showP ? 'true' : 'false');
        }
        if (t3) {
            t3.classList.toggle('active', showG);
            t3.setAttribute('aria-selected', showG ? 'true' : 'false');
        }
        if (showP) renderPortfolio();
        if (showM || showP) {
            scheduleMarketRefresh();
        }
    }

    document.addEventListener('DOMContentLoaded', function () {
        document.getElementById('tab-mkt').addEventListener('click', function () { setTab('mkt'); });
        document.getElementById('tab-port').addEventListener('click', function () { setTab('port'); });
        document.getElementById('tab-guide').addEventListener('click', function () { setTab('guide'); });
        new MutationObserver(syncThemeFromBody).observe(document.body, { attributes: true, attributeFilter: ['data-theme'] });
        document.addEventListener('visibilitychange', function () {
            if (!document.hidden) {
                scheduleMarketRefresh();
            }
        });
        window.addEventListener('pageshow', function (ev) {
            if (ev.persisted) {
                scheduleMarketRefresh();
            }
        });
        bootstrap();
    });
})();
