fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'ascension_bank'
author 'CedricPoint'
description 'Ascension Bank (CedricPoint Edition) — banque ESX + OX, marché (dont CedricPoint $CP), LB Phone Trade'
version '2.1.0'

dependencies {
    'oxmysql',
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'es_extended'
}

shared_scripts {
    '@ox_lib/init.lua',
    'shared/utils.lua',
    'shared/defaults.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/discord_webhooks.lua',
    'server/main.lua',
    'server/market.lua'
}

client_scripts {
    '@es_extended/imports.lua',
    'client/main.lua',
    'client/lbphone_app.lua'
}

ui_page 'ui/index.html'

files {
    'ui/index.html',
    'ui/style.css',
    'ui/app.js',
    'web/lbphone/index.html',
    'web/lbphone/style.css',
    'web/lbphone/app.js'
}
