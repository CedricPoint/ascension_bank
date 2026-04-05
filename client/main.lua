local ResourceName = GetCurrentResourceName()
local Utils = AscensionBankUtils

local State = {
    config = {
        bank = Utils.deepCopy(AscensionBankDefaults.bank),
        atm = Utils.deepCopy(AscensionBankDefaults.atm),
    },
    zones = {},
    blips = {},
}

local function closeUi()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

local function openUi(payload)
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'open', payload = payload })
end

local function buildZone(entry)
    return {
        coords = Utils.toVector3(entry.coords),
        size = vec3(entry.length or 1.4, entry.width or 1.4, math.max((entry.maxZ or entry.coords.z + 1.0) - (entry.minZ or entry.coords.z - 1.0), 1.4)),
        rotation = entry.heading or 0.0,
    }
end

local function clearBlips()
    for _, blip in ipairs(State.blips) do
        RemoveBlip(blip)
    end
    State.blips = {}
end

local function createBlip(entry, sprite, colour, label)
    if not entry.coords then return end

    local blip = AddBlipForCoord(entry.coords.x + 0.0, entry.coords.y + 0.0, entry.coords.z + 0.0)
    SetBlipSprite(blip, sprite)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.8)
    SetBlipColour(blip, colour)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or entry.label)
    EndTextCommandSetBlipName(blip)
    State.blips[#State.blips + 1] = blip
end

local function clearZones()
    for _, zoneId in ipairs(State.zones) do
        exports.ox_target:removeZone(zoneId)
    end
    State.zones = {}
end

local function registerBankZones()
    clearZones()
    clearBlips()

    for _, entry in ipairs(State.config.bank.entries or {}) do
        local zone = buildZone(entry)
        local id = exports.ox_target:addBoxZone({
            coords = zone.coords,
            size = zone.size,
            rotation = zone.rotation,
            debug = false,
            options = {
                {
                    name = entry.id,
                    icon = ('fa-solid fa-%s'):format(entry.icon or 'building-columns'),
                    label = entry.label,
                    distance = entry.distance or 2.0,
                    onSelect = function()
                        local bank = lib.callback.await('ascension_bank:server:getBankData', false)
                        if bank then openUi({ mode = 'bank', bank = bank }) end
                    end,
                },
            },
        })
        State.zones[#State.zones + 1] = id
        createBlip(entry, 108, 2, entry.label)
    end

    for _, entry in ipairs(State.config.atm.entries or {}) do
        local zone = buildZone(entry)
        local id = exports.ox_target:addBoxZone({
            coords = zone.coords,
            size = zone.size,
            rotation = zone.rotation,
            debug = false,
            options = {
                {
                    name = entry.id,
                    icon = ('fa-solid fa-%s'):format(entry.icon or 'credit-card'),
                    label = entry.label,
                    distance = entry.distance or 2.0,
                    onSelect = function()
                        local bank = lib.callback.await('ascension_bank:server:getBankData', false)
                        if bank then openUi({ mode = 'atm', bank = bank }) end
                    end,
                },
            },
        })
        State.zones[#State.zones + 1] = id
        createBlip(entry, 277, 2, entry.label)
    end
end

RegisterNetEvent('ascension_bank:client:syncConfig', function(config)
    State.config.bank = config.bank or State.config.bank
    State.config.atm = config.atm or State.config.atm
    registerBankZones()
end)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
    cb({ ok = true, bank = lib.callback.await('ascension_bank:server:getBankData', false) })
end)

RegisterNUICallback('deposit', function(data, cb)
    cb(lib.callback.await('ascension_bank:server:deposit', false, data.amount))
end)

RegisterNUICallback('withdraw', function(data, cb)
    cb(lib.callback.await('ascension_bank:server:withdraw', false, data.amount, data.context))
end)

RegisterNUICallback('transfer', function(data, cb)
    cb(lib.callback.await('ascension_bank:server:transfer', false, data.iban, data.amount, data.reason))
end)
RegisterNUICallback('buyCard', function(_, cb)
    cb(lib.callback.await('ascension_bank:server:buyCard', false))
end)

RegisterNUICallback('replaceCard', function(_, cb)
    cb(lib.callback.await('ascension_bank:server:replaceCard', false))
end)

RegisterNUICallback('marketBootstrap', function(_, cb)
    local m = lib.callback.await('ascension_bank:server:marketBootstrap', false)
    cb({ ok = m ~= nil, market = m })
end)

RegisterNUICallback('marketBuy', function(data, cb)
    cb(lib.callback.await('ascension_bank:server:marketBuy', false, data.assetId, data.amount))
end)

RegisterNUICallback('marketSell', function(data, cb)
    cb(lib.callback.await('ascension_bank:server:marketSell', false, data.assetId, data.amount))
end)

RegisterCommand('bankui', function()
    local bank = lib.callback.await('ascension_bank:server:getBankData', false)
    if bank then openUi({ mode = 'bank', bank = bank }) end
end, false)

RegisterCommand('bankclose', function()
    closeUi()
end, false)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= ResourceName then return end
    closeUi()
    clearZones()
    clearBlips()
end)

CreateThread(function()
    closeUi()
    Wait(1000)
    local config = lib.callback.await('ascension_bank:server:getConfig', false)
    if config then
        State.config = config
        registerBankZones()
    end
end)

