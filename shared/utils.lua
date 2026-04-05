AscensionBankUtils = AscensionBankUtils or {}

local Utils = AscensionBankUtils

function Utils.deepCopy(value)
    if type(value) ~= 'table' then return value end
    local clone = {}
    for key, entry in pairs(value) do clone[key] = Utils.deepCopy(entry) end
    return clone
end

function Utils.ensureNumber(value, fallback)
    local numeric = tonumber(value)
    return numeric or fallback
end

function Utils.toVector3(coords)
    return vec3(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
end

function Utils.round(value, decimals)
    local power = 10 ^ (decimals or 0)
    return math.floor((value * power) + 0.5) / power
end
