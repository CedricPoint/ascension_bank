--- Marché : cryptos + métaux, cotes liées à la masse monétaire bancaire globale (ESX users.accounts).
--- Achats / ventes uniquement depuis le solde banque.

local ESX = exports['es_extended']:getSharedObject()
local Utils = AscensionBankUtils

local State = {
    rateLimits = {},
    lastEconomyTotal = nil,
}

--- Fusion defaults + bank.settings.trading (adminconfig, fondateur).
local function getCfg()
    local cfg = Utils.deepCopy(AscensionBankDefaults.trading)
    if GetResourceState('ascension_adminconfig') == 'started' then
        local ok, bank = pcall(function()
            return exports.ascension_adminconfig:GetModuleConfig('bank')
        end)
        if ok and bank and bank.settings and type(bank.settings.trading) == 'table' then
            for k, v in pairs(bank.settings.trading) do
                if v ~= nil then cfg[k] = v end
            end
        end
    end
    return cfg
end

local function throttle(source, key, windowMs)
    local now = GetGameTimer()
    local bucket = ('mkt:%s:%s'):format(source, key)
    if State.rateLimits[bucket] and State.rateLimits[bucket] > now then return false end
    State.rateLimits[bucket] = now + windowMs
    return true
end

local function bankInternal()
    return AscensionBankServer
end

local function fetchTotalBankInEconomy()
    local queries = {
        [[SELECT COALESCE(SUM(CAST(JSON_UNQUOTE(JSON_EXTRACT(accounts, '$.bank')) AS UNSIGNED)), 0) AS total
        FROM users WHERE accounts IS NOT NULL AND accounts <> '' AND JSON_VALID(accounts)]],
        [[SELECT COALESCE(SUM(CAST(JSON_UNQUOTE(JSON_EXTRACT(accounts, '$.bank')) AS UNSIGNED)), 0) AS total
        FROM users WHERE accounts IS NOT NULL AND accounts <> '']],
    }
    for _, sql in ipairs(queries) do
        local ok, row = pcall(function()
            return MySQL.single.await(sql)
        end)
        if ok and row then
            local n = tonumber(row.total)
            if n and n >= 0 then
                State.lastEconomyTotal = math.floor(n)
                return State.lastEconomyTotal
            end
        end
    end
    State.lastEconomyTotal = State.lastEconomyTotal or 120000000
    return State.lastEconomyTotal
end

local function economyPressure()
    local total = fetchTotalBankInEconomy()
    local cfg = getCfg()
    local low = tonumber(cfg.economyBankLow) or 80000000
    local high = tonumber(cfg.economyBankHigh) or 600000000
    if high <= low then high = low + 1 end
    local p = (total - low) / (high - low)
    if p < 0 then p = 0 elseif p > 1 then p = 1 end
    return p, total
end

local function economyHintFromPressure(pressure)
    return pressure < 0.35 and 'Liquidité serveur basse : marché un peu plus calme, légère propension haussière.'
        or (pressure > 0.65 and 'Liquidité serveur élevée : marché plus nerveux, gains et pertes possibles.'
        or 'Liquidité serveur modérée : comportement de marché équilibré.')
end

local function clamp(x, a, b)
    if x < a then return a end
    if x > b then return b end
    return x
end

local function toNumber(v, fallback)
    local n = tonumber(v)
    if not n then return fallback or 0 end
    return n
end

local function roundMoney(n)
    return math.floor(toNumber(n, 0) + 0.5)
end

--- Profils : volMult / maxTickMult / driftBonus (ajouté au drift économie). « prime » = traité à part (serveur).
local RiskParams = {
    bluechip = { volMult = 0.52, maxTickMult = 0.62, driftBonus = 0.0 },
    standard = { volMult = 1.0, maxTickMult = 1.0, driftBonus = 0.0 },
    volatile = { volMult = 1.48, maxTickMult = 1.38, driftBonus = -0.00007 },
    meme = { volMult = 2.08, maxTickMult = 1.78, driftBonus = -0.00015 },
    extreme = { volMult = 2.52, maxTickMult = 2.12, driftBonus = -0.00024 },
    metal = { volMult = 0.82, maxTickMult = 0.92, driftBonus = 0.0 },
    oil = { volMult = 1.08, maxTickMult = 1.12, driftBonus = -0.00004 },
    index = { volMult = 0.4, maxTickMult = 0.48, driftBonus = 0.000018 },
    stable = { volMult = 0.26, maxTickMult = 0.34, driftBonus = 0.000012 },
}

local function rawRiskProfile(row)
    local p = row.risk_profile
    if type(p) == 'string' and p ~= '' then return p end
    if row.category == 'index' then return 'index' end
    if row.category == 'equity' then return 'bluechip' end
    if row.category == 'commodity' then return 'metal' end
    return 'standard'
end

local function clientRiskProfile(row)
    local r = rawRiskProfile(row)
    if r == 'prime' then return 'institutional' end
    return r
end

local function uiFilterGroup(row)
    local r = rawRiskProfile(row)
    if r == 'prime' then return 'institutional' end
    if row.category == 'equity' then return 'equity' end
    if r == 'stable' then return 'bluechip' end
    if r == 'oil' then return 'oil' end
    if r == 'metal' then return 'commodity' end
    if row.category == 'commodity' then return 'commodity' end
    if row.category == 'index' then return 'index' end
    if r == 'bluechip' then return 'bluechip' end
    if r == 'meme' or r == 'extreme' then return 'meme_risk' end
    if r == 'volatile' then return 'volatile' end
    return 'alt'
end

local function loadAssets()
    return MySQL.query.await([[
        SELECT asset_id, label, blurb, category, risk_profile, sort_order, base_price, current_price, previous_price
        FROM aab_market_assets
        ORDER BY sort_order ASC, asset_id ASC
    ]]) or {}
end

--- Positions ouvertes par actif : nombre de comptes détenteurs + unités totales (effet « foule » sur le drift).
local function loadCrowdStatsByAsset()
    local q = MySQL.query.await([[
        SELECT asset_id,
            COUNT(*) AS holders,
            COALESCE(SUM(units), 0) AS total_units
        FROM aab_market_positions
        WHERE units > 0.00000001
        GROUP BY asset_id
    ]]) or {}
    local map = {}
    for _, r in ipairs(q) do
        map[r.asset_id] = {
            holders = math.floor(tonumber(r.holders) or 0),
            total_units = tonumber(r.total_units) or 0,
        }
    end
    return map
end

--- Peu de détenteurs : léger biais haussier (illiquidité). Beaucoup de monde / grosse valo ouverte : pression négative.
--- Le bruit et la réversion vers la base restent dominants : pertes possibles même seul sur l’actif.
local function crowdDriftAdjustment(holders, openValue, basePrice, profile)
    if profile == 'prime' then
        return 0
    end
    holders = math.floor(tonumber(holders) or 0)
    openValue = tonumber(openValue) or 0
    basePrice = math.max(tonumber(basePrice) or 1, 0.01)
    local refOi = basePrice * 20000
    local oiNorm = refOi > 0 and (openValue / refOi) or 0

    if holders <= 0 or openValue < 40 then
        return 0
    end

    if holders == 1 and openValue >= 400 then
        return 0.000048 + (math.random() * 2 - 1) * 0.000022
    end
    if holders == 2 and oiNorm < 0.065 and openValue >= 250 then
        return 0.00002 + (math.random() * 2 - 1) * 0.00001
    end

    local pen = 0
    if holders >= 3 then
        pen = pen + math.min(holders - 2, 18) * 0.000016
    end
    if holders >= 8 then
        pen = pen + 0.000038
    end
    if holders >= 14 then
        pen = pen + 0.000032
    end
    if oiNorm > 0.095 then
        pen = pen + math.min(oiNorm - 0.095, 1.05) * 0.00005
    end
    return -pen
end

local function applyMarketTick()
    local cfg = getCfg()
    local pressure = economyPressure()
    local rows = loadAssets()
    if not rows[1] then return end

    local crowdMap = loadCrowdStatsByAsset()
    local volScale = 0.80 + pressure * 0.36
    local econDrift = (0.5 - pressure) * 0.0002

    for _, row in ipairs(rows) do
        local base = toNumber(row.base_price, 1)
        local price = toNumber(row.current_price, base)
        if base <= 0 then base = 1 end

        local profile = rawRiskProfile(row)
        local newPrice

        if profile == 'prime' then
            local upBias = 0.00072 + math.random() * 0.00105
            local dip = (math.random() < 0.065) and (-0.00025 - math.random() * 0.00045) or 0
            local change = upBias + dip
            if change < 0.0001 then change = 0.0001 + math.random() * 0.00015 end
            change = clamp(change, -0.0038, 0.012)
            newPrice = price * (1 + change)
            local floorP = math.max(base * 0.52, price * 0.9985)
            local capP = base * 3.6
            newPrice = clamp(newPrice, floorP, capP)
        else
            local isCryptoLike = row.category == 'crypto' or row.category == 'index'
            local isEquity = row.category == 'equity'
            local baseVol, maxTick
            if isEquity then
                baseVol = tonumber(cfg.equityBaseVol) or 0.00145
                maxTick = tonumber(cfg.equityMaxTickPct) or 0.0042
            elseif isCryptoLike then
                baseVol = tonumber(cfg.cryptoBaseVol) or 0.0029
                maxTick = tonumber(cfg.cryptoMaxTickPct) or 0.0072
            else
                baseVol = tonumber(cfg.commodityBaseVol) or 0.00155
                maxTick = tonumber(cfg.commodityMaxTickPct) or 0.0048
            end
            local rp = RiskParams[profile] or RiskParams.standard
            local noise = (math.random() * 2 - 1) * baseVol * volScale * rp.volMult
            local meanK = profile == 'meme' and 0.00006 or (profile == 'stable' and 0.00038 or 0.00012)
            local meanRevert = -((price - base) / base) * meanK
            local change = econDrift + rp.driftBonus + noise + meanRevert
            local c = crowdMap[row.asset_id]
            local openVal = (c and c.total_units or 0) * price
            change = change + crowdDriftAdjustment(c and c.holders or 0, openVal, base, profile)
            change = clamp(change, -maxTick * rp.maxTickMult, maxTick * rp.maxTickMult)
            newPrice = price * (1 + change)
            local floorP = base * (profile == 'extreme' and 0.22 or 0.32)
            local capP = base * (profile == 'meme' and 3.2 or 2.85)
            newPrice = clamp(newPrice, floorP, capP)
        end

        MySQL.update.await(
            'UPDATE aab_market_assets SET previous_price = current_price, current_price = ? WHERE asset_id = ?',
            { newPrice, row.asset_id }
        )
    end
end

local function getPosition(accountId, assetId)
    return MySQL.single.await(
        'SELECT * FROM aab_market_positions WHERE account_id = ? AND asset_id = ? LIMIT 1',
        { accountId, assetId }
    )
end

local function upsertPosition(accountId, identifier, assetId, units, avgBuy)
    MySQL.update.await([[
        INSERT INTO aab_market_positions (account_id, identifier, asset_id, units, avg_buy_price)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE units = VALUES(units), avg_buy_price = VALUES(avg_buy_price), updated_at = CURRENT_TIMESTAMP
    ]], { accountId, identifier, assetId, units, avgBuy })
end

local function deletePosition(accountId, assetId)
    MySQL.update.await('DELETE FROM aab_market_positions WHERE account_id = ? AND asset_id = ?', { accountId, assetId })
end

local function buildMarketPayload(source)
    local internal = bankInternal()
    if not internal then return nil end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end

    local account = internal.ensureBankAccount(source)
    if not account then return nil end

    internal.refreshConfig()
    local cfg = getCfg()
    local assets = loadAssets()
    local positions = MySQL.query.await(
        'SELECT asset_id, units, avg_buy_price FROM aab_market_positions WHERE account_id = ?',
        { account.id }
    ) or {}

    local posMap = {}
    for _, p in ipairs(positions) do
        posMap[p.asset_id] = p
    end

    local pressure, totalBank = economyPressure()
    local list = {}
    for _, a in ipairs(assets) do
        local price = toNumber(a.current_price, 0)
        local prev = toNumber(a.previous_price, price)
        local chg = prev > 0 and ((price - prev) / prev) * 100 or 0
        local pos = posMap[a.asset_id]
        local units = pos and toNumber(pos.units, 0) or 0
        local avg = pos and toNumber(pos.avg_buy_price, 0) or 0
        local mv = roundMoney(units * price)
        local raw = rawRiskProfile(a)
        local maxExpo = (raw == 'prime') and (cfg.primeMaxPositionValue or 65000) or (cfg.maxPositionValue or 200000)
        list[#list + 1] = {
            id = a.asset_id,
            label = a.label,
            blurb = a.blurb or '',
            category = a.category,
            riskProfile = clientRiskProfile(a),
            filterGroup = uiFilterGroup(a),
            price = price,
            changePct = Utils.round(chg, 2),
            units = units,
            avgBuy = avg,
            marketValue = mv,
            unrealized = roundMoney(mv - units * avg),
            maxExposure = maxExpo,
        }
    end

    return {
        bankBalance = internal.getBankMoney(xPlayer),
        assets = list,
        economy = {
            totalBankM = math.floor(totalBank / 1e6),
            pressure = Utils.round(pressure * 100, 1),
            hint = economyHintFromPressure(pressure),
        },
        settings = {
            feePercent = cfg.feePercent,
            minOrder = cfg.minOrder,
            maxOrder = cfg.maxOrder,
            maxPositionValue = cfg.maxPositionValue,
            primeMaxPositionValue = cfg.primeMaxPositionValue,
            tickMinutes = math.max(1, math.floor((cfg.tickIntervalMs or 300000) / 60000)),
        },
    }
end

local function marketBuy(source, assetId, amount)
    local internal = bankInternal()
    if not internal then return false, 'Service indisponible.' end

    assetId = tostring(assetId or '')
    amount = roundMoney(amount)
    local cfg = getCfg()
    if amount < (cfg.minOrder or 250) then return false, ('Montant minimum: $%s'):format(cfg.minOrder or 250) end
    if amount > (cfg.maxOrder or 25000) then return false, ('Montant maximum: $%s'):format(cfg.maxOrder or 25000) end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'Joueur introuvable.' end

    local row = MySQL.single.await('SELECT * FROM aab_market_assets WHERE asset_id = ? LIMIT 1', { assetId })
    if not row then return false, 'Actif inconnu.' end

    local price = toNumber(row.current_price, 0)
    if price <= 0 then return false, 'Cote invalide.' end

    local account = internal.ensureBankAccount(source)
    if not account then return false, 'Compte bancaire introuvable.' end

    local fee = roundMoney(amount * (cfg.feePercent or 0.0075))
    local invest = amount - fee
    if invest <= 0 then return false, 'Montant trop faible (frais).' end

    if internal.getBankMoney(xPlayer) < amount then
        return false, 'Solde bancaire insuffisant (cash interdit pour le trading).'
    end

    local pos = getPosition(account.id, assetId)
    local oldUnits = pos and toNumber(pos.units, 0) or 0
    local oldAvg = pos and toNumber(pos.avg_buy_price, 0) or 0
    local newUnits = oldUnits + (invest / price)
    local raw = rawRiskProfile(row)
    local maxPos = (raw == 'prime') and (cfg.primeMaxPositionValue or 65000) or (cfg.maxPositionValue or 200000)
    local newValue = newUnits * price
    if newValue > maxPos + 0.01 then
        return false, ('Plafond d\'exposition atteint ($%s max sur cet actif).'):format(maxPos)
    end

    local newAvg = newUnits > 0 and ((oldUnits * oldAvg) + invest) / newUnits or 0

    xPlayer.removeAccountMoney('bank', amount, 'ascension_bank_trade_buy')
    upsertPosition(account.id, internal.getIdentifier(source), assetId, newUnits, newAvg)

    internal.addTransaction(account.id, 'trade_buy', amount, internal.getBankMoney(xPlayer), ('Achat %s'):format(row.label), nil, nil, {
        asset = assetId,
        units = newUnits,
        price = price,
        fee = fee,
    })

    if AscensionBankDiscord and AscensionBankDiscord.sendTrading then
        local pname = xPlayer.getName and xPlayer.getName() or GetPlayerName(source) or '?'
        AscensionBankDiscord.sendTrading('Achat marché', {
            { name = 'Joueur', value = ('`%s` (ID %s)'):format(pname, source), inline = true },
            { name = 'IBAN', value = ('`%s`'):format(account.iban or '—'), inline = true },
            { name = 'Actif', value = ('`%s` — %s'):format(assetId, row.label), inline = false },
            { name = 'Montant ordre', value = ('$%s (frais $%s)'):format(amount, fee), inline = true },
            { name = 'Cote', value = ('$%s'):format(Utils.round(price, 4)), inline = true },
            { name = 'Unités après', value = tostring(Utils.round(newUnits, 6)), inline = true },
        })
    end

    return true
end

local function marketSell(source, assetId, sellAmount)
    local internal = bankInternal()
    if not internal then return false, 'Service indisponible.' end

    assetId = tostring(assetId or '')
    sellAmount = roundMoney(sellAmount)
    local cfg = getCfg()
    if sellAmount < (cfg.minOrder or 250) then return false, ('Montant minimum: $%s'):format(cfg.minOrder or 250) end

    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'Joueur introuvable.' end

    local row = MySQL.single.await('SELECT * FROM aab_market_assets WHERE asset_id = ? LIMIT 1', { assetId })
    if not row then return false, 'Actif inconnu.' end
    local price = toNumber(row.current_price, 0)
    if price <= 0 then return false, 'Cote invalide.' end

    local account = internal.ensureBankAccount(source)
    if not account then return false, 'Compte bancaire introuvable.' end
    local pos = getPosition(account.id, assetId)
    if not pos or toNumber(pos.units, 0) <= 0 then return false, 'Aucune position sur cet actif.' end

    local units = toNumber(pos.units, 0)
    local maxGross = units * price
    local minO = cfg.minOrder or 250
    local gross
    if maxGross < minO then
        gross = maxGross
    else
        gross = math.min(sellAmount, maxGross)
        if gross < minO then
            gross = maxGross
        end
    end

    local unitsSell = gross / price
    if unitsSell > units then unitsSell = units end
    gross = unitsSell * price

    local fee = roundMoney(gross * (cfg.feePercent or 0.0075))
    local net = roundMoney(gross - fee)
    if net <= 0 then return false, 'Montant de vente trop faible.' end

    local newUnits = units - unitsSell
    local avg = toNumber(pos.avg_buy_price, 0)

    if newUnits < 0.00000001 then
        deletePosition(account.id, assetId)
    else
        upsertPosition(account.id, internal.getIdentifier(source), assetId, newUnits, avg)
    end

    xPlayer.addAccountMoney('bank', net, 'ascension_bank_trade_sell')
    internal.addTransaction(account.id, 'trade_sell', net, internal.getBankMoney(xPlayer), ('Vente %s'):format(row.label), nil, nil, {
        asset = assetId,
        units_sold = unitsSell,
        price = price,
        fee = fee,
        gross = gross,
    })

    if AscensionBankDiscord and AscensionBankDiscord.sendTrading then
        local pname = xPlayer.getName and xPlayer.getName() or GetPlayerName(source) or '?'
        AscensionBankDiscord.sendTrading('Vente marché', {
            { name = 'Joueur', value = ('`%s` (ID %s)'):format(pname, source), inline = true },
            { name = 'IBAN', value = ('`%s`'):format(account.iban or '—'), inline = true },
            { name = 'Actif', value = ('`%s` — %s'):format(assetId, row.label), inline = false },
            { name = 'Brut / frais / net', value = ('$%s / $%s / $%s'):format(gross, fee, net), inline = false },
            { name = 'Unités vendues', value = tostring(Utils.round(unitsSell, 6)), inline = true },
            { name = 'Cote', value = ('$%s'):format(Utils.round(price, 4)), inline = true },
        })
    end

    return true
end

CreateThread(function()
    Wait(5000)
    while true do
        local interval = tonumber(getCfg().tickIntervalMs) or 300000
        local ok, err = pcall(applyMarketTick)
        if not ok then
            print(('[ascension_bank] market tick error: %s'):format(tostring(err)))
        end
        Wait(interval)
    end
end)

--- Rapport console + webhook trading (intervalle asc_bank_market_report_ms, défaut 10 min)
CreateThread(function()
    Wait(25000)
    while true do
        local w = tonumber(GetConvar('asc_bank_market_report_ms', '600000')) or 600000
        if w < 60000 then w = 600000 end
        Wait(w)
        if not AscensionBankDiscord or not AscensionBankDiscord.pushMarketSnapshot then goto continue end
        local rows = loadAssets()
        if not rows[1] then goto continue end
        local pressure, totalBank = economyPressure()
        local hint = economyHintFromPressure(pressure)
        local lines = {}
        for _, row in ipairs(rows) do
            local price = toNumber(row.current_price, 0)
            local prev = toNumber(row.previous_price, price)
            local chg = prev > 0 and ((price - prev) / prev) * 100 or 0
            lines[#lines + 1] = ('%s | %s | $%s | %+.2f%%'):format(
                row.asset_id,
                row.label,
                tostring(Utils.round(price, 4)),
                Utils.round(chg, 2)
            )
        end
        AscensionBankDiscord.pushMarketSnapshot(lines, hint, math.floor(totalBank / 1e6))
        ::continue::
    end
end)

lib.callback.register('ascension_bank:server:marketBootstrap', function(source)
    return buildMarketPayload(source)
end)

lib.callback.register('ascension_bank:server:marketBuy', function(source, assetId, amount)
    if not throttle(source, 'buy', 900) then return { ok = false, error = 'Action trop rapide.' } end
    local ok, err = marketBuy(source, assetId, amount)
    if not ok then return { ok = false, error = err } end
    return { ok = true, market = buildMarketPayload(source) }
end)

lib.callback.register('ascension_bank:server:marketSell', function(source, assetId, amount)
    if not throttle(source, 'sell', 900) then return { ok = false, error = 'Action trop rapide.' } end
    local ok, err = marketSell(source, assetId, amount)
    if not ok then return { ok = false, error = err } end
    return { ok = true, market = buildMarketPayload(source) }
end)
