--- Application lb-phone « Ascension Trade » — investissements (solde banque uniquement)

local APP_ID = 'ascension_trade'

local function registerNui()
    RegisterNUICallback('asc_trade_bootstrap', function(_, cb)
        local data = lib.callback.await('ascension_bank:server:marketBootstrap', false)
        cb(data or {})
    end)

    RegisterNUICallback('asc_trade_buy', function(data, cb)
        local assetId = data and data.assetId
        local amount = math.floor(tonumber(data and data.amount) or 0)
        local res = lib.callback.await('ascension_bank:server:marketBuy', false, assetId, amount)
        cb(res or { ok = false, error = 'Erreur serveur.' })
    end)

    RegisterNUICallback('asc_trade_sell', function(data, cb)
        local assetId = data and data.assetId
        local amount = math.floor(tonumber(data and data.amount) or 0)
        local res = lib.callback.await('ascension_bank:server:marketSell', false, assetId, amount)
        cb(res or { ok = false, error = 'Erreur serveur.' })
    end)
end

local function tryAddApp()
    if GetResourceState('lb-phone') ~= 'started' then return false end
    if not exports['lb-phone'] or not exports['lb-phone'].AddCustomApp then return false end

    local ok, res, err = pcall(function()
        return exports['lb-phone']:AddCustomApp({
            identifier = APP_ID,
            name = 'Trade',
            description = 'Marché Ascension — ordres débités sur le compte bancaire uniquement.',
            developer = 'CedricPoint',
            defaultApp = true,
            size = 128,
            ui = 'ascension_bank/web/lbphone/index.html',
            icon = 'https://cdn-icons-png.flaticon.com/512/2331/2331949.png',
            fixBlur = true,
        })
    end)

    if not ok then
        print(('[ascension_bank] lb-phone AddCustomApp erreur: %s'):format(tostring(res)))
        return false
    end

    if res == true then
        return true
    end

    if res == false and type(err) == 'string' and err:find('already exists') then
        return true
    end

    return false
end

local function scheduleRegisterApp()
    CreateThread(function()
        Wait(1500)
        for _ = 1, 12 do
            if tryAddApp() then
                return
            end
            Wait(750)
        end
        print('[ascension_bank] Impossible d\'enregistrer l\'app lb-phone (lb-phone démarré ?).')
    end)
end

CreateThread(function()
    registerNui()
end)

RegisterNetEvent('esx:playerLoaded', function()
    scheduleRegisterApp()
end)

AddEventHandler('onClientResourceStart', function(resName)
    if resName ~= GetCurrentResourceName() then return end
    scheduleRegisterApp()
end)
