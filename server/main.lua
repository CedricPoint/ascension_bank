local ESX = exports['es_extended']:getSharedObject()
local Utils = AscensionBankUtils
local ResourceName = GetCurrentResourceName()

local State = {
    bankConfig = Utils.deepCopy(AscensionBankDefaults.bank),
    atmConfig = Utils.deepCopy(AscensionBankDefaults.atm),
    rateLimits = {},
    cardHookId = nil,
}

local function getIdentifier(source)
    local identifiers = GetPlayerIdentifiers(source)
    for _, identifier in ipairs(identifiers) do
        if identifier:find('license:', 1, true) == 1 then return identifier end
    end
    return identifiers[1]
end

local function tableDecode(value, fallback)
    if not value or value == '' then return fallback or {} end
    local ok, decoded = pcall(json.decode, value)
    if not ok or type(decoded) ~= 'table' then return fallback or {} end
    return decoded
end

local function tableEncode(value)
    return json.encode(value or {})
end

local function notify(source, payload)
    TriggerClientEvent('ox_lib:notify', source, payload)
end

local function getBankMoney(xPlayer)
    local account = xPlayer.getAccount and xPlayer.getAccount('bank')
    return account and account.money or 0
end

local function getOxCash(source)
    if GetResourceState('ox_inventory') ~= 'started' then
        return nil
    end
    local cashItem = exports.ox_inventory:GetItem(source, 'money')
    if not cashItem then
        return 0
    end
    return math.floor(tonumber(cashItem.count) or 0)
end

local function getCashMoney(xPlayer)
    local source = xPlayer and xPlayer.source
    if source then
        local oxCash = getOxCash(source)
        if oxCash ~= nil then
            return oxCash
        end
    end
    if xPlayer.getMoney then return xPlayer.getMoney() end
    local account = xPlayer.getAccount and xPlayer.getAccount('money')
    return account and account.money or 0
end

local function removeCashMoney(xPlayer, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return true
    end

    local source = xPlayer and xPlayer.source
    if source and getOxCash(source) ~= nil then
        return exports.ox_inventory:RemoveItem(source, 'money', amount)
    end

    if xPlayer.removeMoney then
        xPlayer.removeMoney(amount, reason or 'ascension_bank_cash_remove')
        return true
    end

    if xPlayer.removeAccountMoney then
        xPlayer.removeAccountMoney('money', amount, reason or 'ascension_bank_cash_remove')
        return true
    end

    return false
end

local function addCashMoney(xPlayer, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then
        return true
    end

    local source = xPlayer and xPlayer.source
    if source and getOxCash(source) ~= nil then
        if not exports.ox_inventory:CanCarryItem(source, 'money', amount) then
            return false, 'Inventaire plein.'
        end
        local ok = exports.ox_inventory:AddItem(source, 'money', amount)
        if not ok then
            return false, 'Impossible de crediter le cash.'
        end
        return true
    end

    if xPlayer.addMoney then
        xPlayer.addMoney(amount, reason or 'ascension_bank_cash_add')
        return true
    end

    if xPlayer.addAccountMoney then
        xPlayer.addAccountMoney('money', amount, reason or 'ascension_bank_cash_add')
        return true
    end

    return false, 'Compte cash indisponible.'
end

local function getPlayerNameSafe(xPlayer, source)
    if xPlayer and xPlayer.getName then
        local name = xPlayer.getName()
        if name and name ~= '' then return name end
    end
    return GetPlayerName(source) or 'Inconnu'
end

local function throttle(source, key, windowMs)
    local now = GetGameTimer()
    local bucket = ('%s:%s'):format(source, key)
    if State.rateLimits[bucket] and State.rateLimits[bucket] > now then return false end
    State.rateLimits[bucket] = now + windowMs
    return true
end

local function getAdminModule(moduleName)
    if GetResourceState('ascension_adminconfig') == 'started' then
        local module = exports.ascension_adminconfig:GetModuleConfig(moduleName)
        if module then return module end
    end

    return Utils.deepCopy(AscensionBankDefaults[moduleName])
end

local function refreshConfig()
    State.bankConfig = getAdminModule('bank')
    State.atmConfig = getAdminModule('atm')
    State.bankConfig.settings.cardPrice = tonumber(State.bankConfig.settings.cardPrice) or 1200
    State.bankConfig.settings.cardReplacementPrice = tonumber(State.bankConfig.settings.cardReplacementPrice) or 2500
end

local function generateIban()
    while true do
        local iban = ('FR%02d%04d%04d%04d%04d'):format(
            math.random(10, 99),
            math.random(1000, 9999),
            math.random(1000, 9999),
            math.random(1000, 9999),
            math.random(1000, 9999)
        )

        local exists = MySQL.scalar.await('SELECT id FROM aab_bank_accounts WHERE iban = ? LIMIT 1', { iban })
        if not exists then return iban end
    end
end

local function generateCardSerial()
    return ('ASC-%04d-%04d'):format(math.random(1000, 9999), math.random(1000, 9999))
end

local function getStoredAccounts(identifier)
    local raw = MySQL.scalar.await('SELECT accounts FROM users WHERE identifier = ? LIMIT 1', { identifier })
    return tableDecode(raw, {})
end

local function setStoredBankMoney(identifier, amount)
    local accounts = getStoredAccounts(identifier)
    accounts.bank = math.floor(amount)
    MySQL.update.await('UPDATE users SET accounts = ? WHERE identifier = ?', { tableEncode(accounts), identifier })
end

local function getStoredBankMoney(identifier)
    local accounts = getStoredAccounts(identifier)
    return math.floor(tonumber(accounts.bank) or 0)
end

local function discordGeneralLog(title, source, account, extraFields)
    if not AscensionBankDiscord or not AscensionBankDiscord.sendGeneral then return end
    local xPlayer = ESX.GetPlayerFromId(source)
    local pname = xPlayer and xPlayer.getName and xPlayer.getName() or GetPlayerName(source) or '?'
    local fields = {
        { name = 'Joueur', value = ('`%s` (ID %s)'):format(pname, source), inline = true },
        { name = 'IBAN', value = ('`%s`'):format(account and account.iban or '—'), inline = true },
    }
    if extraFields then
        for _, f in ipairs(extraFields) do
            fields[#fields + 1] = f
        end
    end
    AscensionBankDiscord.sendGeneral(title, fields)
end

local function addTransaction(accountId, txType, amount, balanceAfter, reason, counterpartyIban, counterpartyName, metadata)
    MySQL.insert.await([[
        INSERT INTO aab_bank_transactions (account_id, transaction_type, amount, balance_after, reason, counterparty_iban, counterparty_name, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        accountId,
        txType,
        math.floor(amount),
        math.floor(balanceAfter),
        reason,
        counterpartyIban,
        counterpartyName,
        json.encode(metadata or {}),
    })
end

local function getCardSlots(source, identifier)
    local inventory = exports.ox_inventory:Search(source, 'slots', 'creditcard') or {}
    local cards = {}

    for _, item in ipairs(inventory) do
        if item.metadata and item.metadata.ownerIdentifier == identifier then
            cards[#cards + 1] = item
        end
    end

    return cards
end

local function removeOwnedCards(source, identifier)
    local cards = getCardSlots(source, identifier)
    for _, item in ipairs(cards) do
        exports.ox_inventory:RemoveItem(source, 'creditcard', item.count or 1, item.metadata, item.slot, false, true)
    end
    return #cards
end

local function createCardMetadata(source, account, identifier)
    return {
        iban = account.iban,
        owner = account.owner_name,
        ownerIdentifier = identifier,
        locked = true,
        serial = generateCardSerial(),
        issuedAt = os.time(),
    }
end

local function ensureBankAccount(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end

    local identifier = getIdentifier(source)
    local account = MySQL.single.await('SELECT * FROM aab_bank_accounts WHERE identifier = ? LIMIT 1', { identifier })
    if account then return account end

    local ownerName = getPlayerNameSafe(xPlayer, source)
    local iban = generateIban()
    local accountId = MySQL.insert.await('INSERT INTO aab_bank_accounts (identifier, owner_name, iban) VALUES (?, ?, ?)', { identifier, ownerName, iban })
    print(('[%s][INFO] Compte bancaire cree %s'):format(ResourceName, json.encode({ source = source, identifier = identifier, iban = iban })))

    return {
        id = accountId,
        identifier = identifier,
        owner_name = ownerName,
        iban = iban,
    }
end

local function getAccountByIban(iban)
    return MySQL.single.await('SELECT * FROM aab_bank_accounts WHERE iban = ? LIMIT 1', { iban })
end

local function getTransactions(accountId)
    return MySQL.query.await([[
        SELECT id, transaction_type, amount, balance_after, reason, counterparty_iban, counterparty_name, created_at
        FROM aab_bank_transactions WHERE account_id = ? ORDER BY id DESC LIMIT 50
    ]], { accountId }) or {}
end

local function getCardState(source, account)
    local identifier = getIdentifier(source)
    local cards = getCardSlots(source, identifier)
    local current = cards[1]

    refreshConfig()

    return {
        hasCard = #cards > 0,
        count = #cards,
        price = State.bankConfig.settings.cardPrice,
        replacementPrice = State.bankConfig.settings.cardReplacementPrice,
        locked = true,
        owner = account.owner_name,
        iban = account.iban,
        serial = current and current.metadata and current.metadata.serial or nil,
    }
end

local function issueCard(source, mode)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'Joueur introuvable.' end

    local account = ensureBankAccount(source)
    local identifier = getIdentifier(source)
    local cards = getCardSlots(source, identifier)
    local hasCard = #cards > 0

    refreshConfig()

    if mode == 'buy' and hasCard then
        return false, 'Vous possedez deja une carte bancaire.'
    end

    if mode == 'replace' and not hasCard then
        return false, 'Aucune carte a remplacer.'
    end

    local price = mode == 'replace' and State.bankConfig.settings.cardReplacementPrice or State.bankConfig.settings.cardPrice
    price = math.floor(tonumber(price) or 0)

    if getBankMoney(xPlayer) < price then
        return false, 'Solde bancaire insuffisant.'
    end

    removeOwnedCards(source, identifier)

    if not exports.ox_inventory:CanCarryItem(source, 'creditcard', 1, createCardMetadata(source, account, identifier)) then
        return false, 'Inventaire plein.'
    end

    xPlayer.removeAccountMoney('bank', price, mode == 'replace' and 'ascension_bank_card_replace' or 'ascension_bank_card_buy')

    local metadata = createCardMetadata(source, account, identifier)
    local success = exports.ox_inventory:AddItem(source, 'creditcard', 1, metadata)

    if not success then
        xPlayer.addAccountMoney('bank', price, 'ascension_bank_card_refund')
        return false, 'Impossible de creer la carte.'
    end

    addTransaction(account.id, mode == 'replace' and 'card_replace' or 'card_purchase', price, getBankMoney(xPlayer), mode == 'replace' and 'Remplacement carte bancaire' or 'Achat carte bancaire', nil, nil, { serial = metadata.serial })
    discordGeneralLog(mode == 'replace' and 'Carte — remplacement' or 'Carte — achat', source, account, {
        { name = 'Montant', value = ('$%s'):format(price), inline = true },
        { name = 'Série', value = ('`%s`'):format(metadata.serial or '—'), inline = true },
        { name = 'Solde après', value = ('$%s'):format(getBankMoney(xPlayer)), inline = true },
    })
    return true
end

local function getBankPayload(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end
    local account = ensureBankAccount(source)
    if not account then return nil end

    refreshConfig()

    return {
        account = {
            iban = account.iban,
            owner = account.owner_name,
        },
        balances = {
            bank = getBankMoney(xPlayer),
            cash = getCashMoney(xPlayer),
        },
        settings = Utils.deepCopy(State.bankConfig.settings),
        atmSettings = Utils.deepCopy(State.atmConfig.settings),
        transactions = getTransactions(account.id),
        card = getCardState(source, account),
    }
end

local function deposit(source, amount)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'Joueur introuvable.' end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'Montant invalide.' end
    refreshConfig()

    if amount > (State.bankConfig.settings.depositLimit or 20000) then
        return false, 'Limite de depot depassee.'
    end

    if getCashMoney(xPlayer) < amount then
        return false, 'Pas assez de cash.'
    end

    local account = ensureBankAccount(source)
    local removed = removeCashMoney(xPlayer, amount, 'ascension_bank_deposit')
    if not removed then
        return false, 'Impossible de retirer le cash.'
    end
    xPlayer.addAccountMoney('bank', amount, 'ascension_bank_deposit')
    addTransaction(account.id, 'deposit', amount, getBankMoney(xPlayer), 'Depot en banque', nil, nil, {})
    discordGeneralLog('Dépôt banque', source, account, {
        { name = 'Montant', value = ('$%s'):format(amount), inline = true },
        { name = 'Solde après', value = ('$%s'):format(getBankMoney(xPlayer)), inline = true },
    })
    return true
end

local function withdraw(source, amount, context)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'Joueur introuvable.' end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'Montant invalide.' end
    refreshConfig()

    local settings = context == 'atm' and State.atmConfig.settings or State.bankConfig.settings
    local limit = settings.withdrawLimit or 25000
    local fee = settings.withdrawFee or 0

    if amount > limit then return false, 'Limite de retrait depassee.' end
    if getBankMoney(xPlayer) < amount + fee then return false, 'Solde bancaire insuffisant.' end

    local account = ensureBankAccount(source)
    xPlayer.removeAccountMoney('bank', amount + fee, 'ascension_bank_withdraw')
    local cashAdded, cashError = addCashMoney(xPlayer, amount, 'ascension_bank_withdraw')
    if not cashAdded then
        xPlayer.addAccountMoney('bank', amount + fee, 'ascension_bank_withdraw_refund')
        return false, cashError or 'Impossible de remettre le cash.'
    end
    addTransaction(account.id, 'withdraw', amount, getBankMoney(xPlayer), context == 'atm' and 'Retrait ATM' or 'Retrait agence', nil, nil, { fee = fee })
    if fee > 0 then
        addTransaction(account.id, 'fee', fee, getBankMoney(xPlayer), 'Frais de retrait', nil, nil, { context = context })
    end
    discordGeneralLog(context == 'atm' and 'Retrait ATM' or 'Retrait banque', source, account, {
        { name = 'Montant', value = ('$%s'):format(amount), inline = true },
        { name = 'Frais', value = ('$%s'):format(fee), inline = true },
        { name = 'Solde après', value = ('$%s'):format(getBankMoney(xPlayer)), inline = true },
    })
    return true
end

local function transfer(source, targetIban, amount, reason)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false, 'Joueur introuvable.' end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'Montant invalide.' end
    refreshConfig()

    local sender = ensureBankAccount(source)
    local recipient = getAccountByIban(targetIban)
    if not sender or not recipient then return false, 'IBAN introuvable.' end
    if sender.iban == recipient.iban then return false, 'Impossible de vous virer a vous-meme.' end

    local fee = State.bankConfig.settings.transferFee or 0
    local total = amount + fee
    if total > (State.bankConfig.settings.transferLimit or 100000) then return false, 'Limite de virement depassee.' end
    if getBankMoney(xPlayer) < total then return false, 'Solde bancaire insuffisant.' end

    xPlayer.removeAccountMoney('bank', total, 'ascension_bank_transfer')
    addTransaction(sender.id, 'transfer_out', amount, getBankMoney(xPlayer), reason or 'Virement sortant', recipient.iban, recipient.owner_name, { fee = fee })
    if fee > 0 then
        addTransaction(sender.id, 'fee', fee, getBankMoney(xPlayer), 'Frais de virement', recipient.iban, recipient.owner_name, {})
    end

    local targetPlayer = ESX.GetPlayerFromIdentifier(recipient.identifier)
    if targetPlayer then
        targetPlayer.addAccountMoney('bank', amount, 'ascension_bank_transfer_in')
        addTransaction(recipient.id, 'transfer_in', amount, getBankMoney(targetPlayer), reason or 'Virement entrant', sender.iban, sender.owner_name, {})
        notify(targetPlayer.source, { title = 'Banque', description = ('Virement recu: $%s'):format(amount), type = 'success' })
    else
        local newBalance = getStoredBankMoney(recipient.identifier) + amount
        setStoredBankMoney(recipient.identifier, newBalance)
        addTransaction(recipient.id, 'transfer_in', amount, newBalance, reason or 'Virement entrant', sender.iban, sender.owner_name, {})
    end

    discordGeneralLog('Virement sortant', source, sender, {
        { name = 'Vers', value = ('`%s` · %s'):format(recipient.iban, recipient.owner_name or '—'), inline = false },
        { name = 'Montant', value = ('$%s'):format(amount), inline = true },
        { name = 'Frais', value = ('$%s'):format(fee), inline = true },
        { name = 'Motif', value = reason and tostring(reason):sub(1, 200) or '—', inline = false },
        { name = 'Solde expéditeur après', value = ('$%s'):format(getBankMoney(xPlayer)), inline = true },
    })
    return true
end

local function registerInventoryHooks()
    if GetResourceState('ox_inventory') ~= 'started' then return end
    if State.cardHookId then return end

    State.cardHookId = exports.ox_inventory:registerHook('swapItems', function(payload)
        local fromIsCard = payload.fromSlot and payload.fromSlot.name == 'creditcard'
        local toIsCard = type(payload.toSlot) == 'table' and payload.toSlot.name == 'creditcard'

        if not fromIsCard and not toIsCard then
            return true
        end

        if payload.fromInventory == payload.toInventory then
            return true
        end

        local source = payload.source
        if source then
            notify(source, {
                title = 'Carte bancaire',
                description = 'Cette carte bancaire est nominative et ne peut pas etre transferee.',
                type = 'error',
            })
        end

        return false
    end, {
        itemFilter = {
            creditcard = true,
        }
    })
end

AscensionBankServer = {
    getIdentifier = getIdentifier,
    getBankMoney = getBankMoney,
    ensureBankAccount = ensureBankAccount,
    addTransaction = addTransaction,
    getBankPayload = getBankPayload,
    refreshConfig = refreshConfig,
    ResourceName = ResourceName,
    Utils = Utils,
}

lib.callback.register('ascension_bank:server:getConfig', function()
    refreshConfig()
    return {
        bank = Utils.deepCopy(State.bankConfig),
        atm = Utils.deepCopy(State.atmConfig),
    }
end)

lib.callback.register('ascension_bank:server:getBankData', function(source)
    return getBankPayload(source)
end)

lib.callback.register('ascension_bank:server:deposit', function(source, amount)
    if not throttle(source, 'deposit', 800) then return { ok = false, error = 'Action trop rapide.' } end
    local ok, err = deposit(source, amount)
    return { ok = ok, error = err, bank = ok and getBankPayload(source) or nil }
end)

lib.callback.register('ascension_bank:server:withdraw', function(source, amount, context)
    if not throttle(source, 'withdraw', 800) then return { ok = false, error = 'Action trop rapide.' } end
    local ok, err = withdraw(source, amount, context or 'bank')
    return { ok = ok, error = err, bank = ok and getBankPayload(source) or nil }
end)

lib.callback.register('ascension_bank:server:transfer', function(source, iban, amount, reason)
    if not throttle(source, 'transfer', 1000) then return { ok = false, error = 'Action trop rapide.' } end
    local ok, err = transfer(source, tostring(iban or ''), amount, reason)
    return { ok = ok, error = err, bank = ok and getBankPayload(source) or nil }
end)

lib.callback.register('ascension_bank:server:buyCard', function(source)
    if not throttle(source, 'buyCard', 1000) then return { ok = false, error = 'Action trop rapide.' } end
    local ok, err = issueCard(source, 'buy')
    return { ok = ok, error = err, bank = ok and getBankPayload(source) or nil }
end)

lib.callback.register('ascension_bank:server:replaceCard', function(source)
    if not throttle(source, 'replaceCard', 1000) then return { ok = false, error = 'Action trop rapide.' } end
    local ok, err = issueCard(source, 'replace')
    return { ok = ok, error = err, bank = ok and getBankPayload(source) or nil }
end)

AddEventHandler('esx:playerLoaded', function(playerId)
    ensureBankAccount(playerId)
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= ResourceName then return end
    print(('^2[%s]^7 Cree par CedricPoint | https://github.com/CedricPoint'):format(ResourceName))
    if GetConvar('asc_bank_webhook_general', '') ~= '' then
        print(('^2[%s]^7 Logs Discord (banque / cartes / virements) actifs.'):format(ResourceName))
    end
    if GetConvar('asc_bank_webhook_trading', '') ~= '' then
        print(('^2[%s]^7 Logs Discord (trading + snapshot marché) actifs.'):format(ResourceName))
    end
    math.randomseed(os.time())
    refreshConfig()
    registerInventoryHooks()
    for _, playerId in ipairs(GetPlayers()) do
        ensureBankAccount(tonumber(playerId))
    end
end)

exports('CanPayFromBank', function(source, amount)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end
    return getBankMoney(xPlayer) >= math.floor(tonumber(amount) or 0)
end)

exports('ChargeBank', function(source, amount, reason, counterpartyName)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 or getBankMoney(xPlayer) < amount then return false end

    local account = ensureBankAccount(source)
    xPlayer.removeAccountMoney('bank', amount, 'ascension_bank_shop_payment')
    addTransaction(account.id, 'card_payment', amount, getBankMoney(xPlayer), reason or 'Paiement carte', nil, counterpartyName, {})
    discordGeneralLog('Paiement carte (commerce)', source, account, {
        { name = 'Montant', value = ('$%s'):format(amount), inline = true },
        { name = 'Solde après', value = ('$%s'):format(getBankMoney(xPlayer)), inline = true },
        { name = 'Motif', value = tostring(reason or '—'):sub(1, 200), inline = false },
        { name = 'Commerçant', value = tostring(counterpartyName or '—'):sub(1, 120), inline = true },
    })
    return true
end)

local function isAscensionFounder(source)
    if GetResourceState('ascension_adminconfig') ~= 'started' then return false end
    local ok, res = pcall(function()
        return exports.ascension_adminconfig:IsFounder(source)
    end)
    return ok and res == true
end

ESX.RegisterServerCallback('ascension_bank:server:founderMarketList', function(source, cb)
    if not isAscensionFounder(source) then
        cb({ ok = false, error = 'Fondateur uniquement.' })
        return
    end
    local rows = MySQL.query.await([[
        SELECT asset_id, label, current_price, base_price, risk_profile
        FROM aab_market_assets ORDER BY sort_order ASC, asset_id ASC
    ]]) or {}
    cb({ ok = true, assets = rows })
end)

ESX.RegisterServerCallback('ascension_bank:server:founderMarketSetPrices', function(source, cb, assetId, currentPrice, basePrice)
    if not isAscensionFounder(source) then
        cb({ ok = false, error = 'Fondateur uniquement.' })
        return
    end
    assetId = tostring(assetId or '')
    currentPrice = tonumber(currentPrice)
    basePrice = tonumber(basePrice)
    if assetId == '' or not currentPrice or currentPrice <= 0 then
        cb({ ok = false, error = 'Donnees invalides.' })
        return
    end
    if not basePrice or basePrice <= 0 then
        basePrice = currentPrice
    end
    local exists = MySQL.scalar.await('SELECT 1 FROM aab_market_assets WHERE asset_id = ? LIMIT 1', { assetId })
    if not exists then
        cb({ ok = false, error = 'Actif inconnu.' })
        return
    end
    MySQL.update.await(
        'UPDATE aab_market_assets SET previous_price = current_price, current_price = ?, base_price = ? WHERE asset_id = ?',
        { currentPrice, basePrice, assetId }
    )
    cb({ ok = true })
end)
