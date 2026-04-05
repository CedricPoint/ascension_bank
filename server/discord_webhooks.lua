--- Logs Discord (webhooks) — URLs via convars serveur uniquement (ne jamais exposer au client).
--- Convars : asc_bank_webhook_general, asc_bank_webhook_trading, asc_bank_market_report_ms (défaut 600000)

local ResourceName = GetCurrentResourceName()

AscensionBankDiscord = AscensionBankDiscord or {}

local function urlGeneral()
    return GetConvar('asc_bank_webhook_general', '')
end

local function urlTrading()
    return GetConvar('asc_bank_webhook_trading', '')
end

local function sendWebhook(url, embeds)
    if not url or url == '' or type(embeds) ~= 'table' or not embeds[1] then return end
    local payload = json.encode({ embeds = embeds })
    PerformHttpRequest(url, function() end, 'POST', payload, { ['Content-Type'] = 'application/json' })
end

local function makeEmbed(title, color, fields)
    return {
        title = title,
        color = color or 5793266,
        fields = fields or {},
        footer = { text = ('%s · %s'):format(ResourceName, os.date('!%Y-%m-%d %H:%M:%S UTC')) },
    }
end

--- @param title string
--- @param fields { name: string, value: string, inline?: boolean }[]
function AscensionBankDiscord.sendGeneral(title, fields)
    sendWebhook(urlGeneral(), { makeEmbed(title, 3447003, fields) })
end

function AscensionBankDiscord.sendTrading(title, fields)
    sendWebhook(urlTrading(), { makeEmbed(title, 10181046, fields) })
end

--- Snapshot marché : console serveur + webhook trading
--- @param lines string[] chaque entrée : "id | label | prix | Δ%"
--- @param economyHint string
--- @param totalBankM number millions $ masse bancaire
function AscensionBankDiscord.pushMarketSnapshot(lines, economyHint, totalBankM)
    local url = urlTrading()
    local ts = os.date('!%Y-%m-%d %H:%M:%S UTC')
    local header = ('[%s] Snapshot marché Ascension — masse bancaire ~ %s M$'):format(ts, tostring(totalBankM or 0))
    local hintLine = economyHint or '—'

    print(('^5[ascension_bank]^7 %s'):format(header))
    print(('^5[ascension_bank]^7 Contexte : %s'):format(hintLine))

    local buf = {}
    for _, line in ipairs(lines or {}) do
        buf[#buf + 1] = line
        print(('^5[ascension_bank]^7   %s'):format(line))
    end

    local body = table.concat(buf, '\n')
    if #body > 3800 then
        body = body:sub(1, 3797) .. '...'
    end

    local desc = ('**Contexte**\n%s\n\n**Cotes**\n```\n%s\n```'):format(hintLine, body ~= '' and body or '—')
    if #desc > 4090 then
        desc = desc:sub(1, 4087) .. '...'
    end

    if url == '' then return end
    sendWebhook(url, {
        {
            title = 'Marché — rapport périodique',
            description = desc,
            color = 5793266,
            footer = { text = ('%s · %s'):format(ResourceName, ts) },
        },
    })
end
