AscensionBankDefaults = {
    bank = {
        settings = {
            withdrawLimit = 25000,
            depositLimit = 20000,
            transferLimit = 100000,
            withdrawFee = 0,
            transferFee = 15,
        },
        entries = {
            {
                id = 'bank_legion',
                label = 'Banque Centrale',
                type = 'bank',
                icon = 'building-columns',
                coords = { x = 149.74, y = -1040.74, z = 29.37 },
                length = 2.4,
                width = 2.4,
                heading = 340.0,
                minZ = 28.37,
                maxZ = 31.37,
                distance = 2.0,
            },
        },
    },
    atm = {
        --- Tous les props listés deviennent utilisables via ox_target (sans coords manuelles).
        autoWorldAtms = true,
        worldAtmModels = {
            'prop_atm_01',
            'prop_atm_02',
            'prop_atm_03',
            'prop_fleeca_atm',
        },
        worldAtmLabel = 'Distributeur automatique',
        worldAtmDistance = 1.8,
        worldAtmIcon = 'credit-card',
        settings = {
            withdrawLimit = 5000,
            withdrawFee = 5,
        },
        --- Vide par défaut : ATM via addModel (worldAtmLabel). Remplir uniquement si autoWorldAtms = false.
        entries = {},
    },
    --- Marché boursier / matières premières (app téléphone, débit uniquement depuis le compte banque)
    trading = {
        tickIntervalMs = 300000, -- 5 min entre deux cotes
        feePercent = 0.0075, -- 0,75 % à l\'achat et à la vente
        minOrder = 250,
        maxOrder = 25000,
        maxPositionValue = 200000, -- valeur max par actif (hors prime institutionnel)
        primeMaxPositionValue = 65000, -- plafond exposition CedricPoint ($CP) — prime serveur
        economyBankLow = 80000000,
        economyBankHigh = 600000000,
        cryptoMaxTickPct = 0.0072,
        commodityMaxTickPct = 0.0048,
        cryptoBaseVol = 0.0029,
        commodityBaseVol = 0.00155,
        equityBaseVol = 0.00145,
        equityMaxTickPct = 0.0042,
    },
}
