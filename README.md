# Ascension Bank — **CedricPoint Edition**

[![FiveM](https://img.shields.io/badge/FiveM-ESX%20Legacy-9146FF?logo=fivem)](https://fivem.net/)
[![ox_lib](https://img.shields.io/badge/ox__lib-required-3B82F6)](https://github.com/overextended/ox_lib)
[![LB Phone](https://img.shields.io/badge/LB%20Phone-plug%20%26%20play-22C55E)](https://docs.lbscripts.com/)

Système bancaire complet pour **ESX Legacy**, pensé pour **Ascension RP** et la gamme **CedricPoint** : comptes avec IBAN, historique SQL, banques / ATM **ox_target**, carte bancaire **ox_inventory**, et **marché investissable** (cryptos, matières premières, actions lore Los Santos) avec actif institutionnel **CedricPoint ($CP)**.

| | |
|---|---|
| **Ressource** | `ascension_bank` |
| **Version** | **2.1.0** (alignée sur `fxmanifest.lua` — *CedricPoint Edition*) |
| **Auteur** | **CedricPoint** |
| **Schéma SQL** | **2.1.0** — fichier unique documenté ci-dessous |

---

## Sommaire

- [Pourquoi « CedricPoint Edition » ?](#pourquoi--cedricpoint-edition-)
- [Fonctionnalités](#fonctionnalités)
- [Dépendances](#dépendances)
- [Installation rapide](#installation-rapide)
- [Base de données (un seul fichier SQL)](#base-de-données-un-seul-fichier-sql)
- [LB Phone — plug & play](#lb-phone--plug--play)
- [Configuration](#configuration)
- [Marché & CedricPoint ($CP)](#marché--cedricpoint-cp)
- [Structure du projet](#structure-du-projet)
- [Modifier / personnaliser](#modifier--personnaliser)
- [Discord (webhooks optionnels)](#discord-webhooks-optionnels)
- [Dépannage](#dépannage)
- [Crédits & licence](#crédits--licence)

---

## Pourquoi « CedricPoint Edition » ?

- La ressource intègre **CedricPoint ($CP)** comme actif **prime** du marché (`CEDRIC_PT`) : profil institutionnel, règles de tick et plafond d’exposition dédiés (`primeMaxPositionValue`), cohérents avec l’identité **CedricPoint**.
- La **version** du manifest (`2.1.0`) et la **version de schéma SQL** (`2.1.0`) sont documentées ensemble pour les releases GitHub et le suivi de migrations.
- L’application téléphone **Trade** annonce le développeur **CedricPoint** (voir `client/lbphone_app.lua`).

---

## Fonctionnalités

| Domaine | Détail |
|--------|--------|
| **Compte** | Création auto, **IBAN** unique, nom titulaire |
| **Solde** | Le solde réel reste dans `users.accounts.bank` (ESX) ; les tables custom servent IBAN + historique + marché |
| **Opérations** | Dépôt, retrait, virement (limites & frais configurables) |
| **Carte** | Item `creditcard` (ox_inventory) avec métadonnées |
| **Points d’accès** | Banques & ATM via **ox_target** (coords dans `shared/defaults.lua`) |
| **Marché** | Achat / vente **uniquement depuis le solde banque** ; ticks serveur ; filtres (blue chips, indices, entreprises, mèmes, etc.) |
| **CedricPoint ($CP)** | Actif **prime** ; exposition plafonnée ; logique de prix distincte des autres actifs |
| **Effet « foule »** | Plusieurs détenteurs / forte valo ouverte → pression négative modérée ; marché peu détenu → léger biais favorable (sans garantie de gain) |
| **Discord** | Webhooks optionnels (opérations générales, trading, snapshot marché) |

---

## Dépendances

Obligatoires (voir `fxmanifest.lua`) :

- [oxmysql](https://github.com/overextended/oxmysql)
- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_target](https://github.com/overextended/ox_target)
- [ox_inventory](https://github.com/overextended/ox_inventory)
- [es_extended](https://github.com/esx-framework/esx_core) (ESX Legacy)

**Recommandé pour le marché mobile :**

- **[lb-phone](https://docs.lbscripts.com/)** — l’app **Trade** s’enregistre automatiquement si la ressource est **démarrée** (aucun patch manuel du cœur de LB Phone).

---

## Installation rapide

1. **Copier** le dossier `ascension_bank` dans `resources/[local]/` (ou votre arborescence habituelle).
2. **Importer la base** : un seul fichier, voir [section SQL](#base-de-données-un-seul-fichier-sql).
3. **Item carte** : dans `ox_inventory`, vérifier l’item `creditcard` (ex. `data/items.lua`) et l’image `web/images/creditcard.png`.
4. **server.cfg** — ordre typique :

```cfg
ensure oxmysql
ensure ox_lib
ensure ox_target
ensure ox_inventory
ensure es_extended
ensure lb-phone
ensure ascension_bank
```

> Si vous n’utilisez pas LB Phone, la ressource fonctionne quand même (banque NUI + ATM) ; seule l’app **Trade** sur téléphone ne sera pas disponible.

5. Redémarrage ou `ensure ascension_bank`.

---

## Base de données (un seul fichier SQL)

Le fichier canonique est :

| Fichier | Rôle |
|---------|------|
| **`sql/ascension_bank_full.sql`** | **Schéma complet** + procédure de compatibilité legacy + **tous** les actifs marché (dont **CedricPoint**). |
| **`sql/install.sql`** | **Copie identique** de `ascension_bank_full.sql` pour les workflows qui importent déjà `install.sql`. |

**Contenu :**

- Tables : `aab_bank_accounts`, `aab_bank_transactions`, `aab_market_assets`, `aab_market_positions`
- Procédure temporaire `asc_bank_legacy_market_assets` : si une ancienne table `aab_market_assets` existe sans colonnes `blurb` / `risk_profile` / `sort_order` / `updated_at`, elles sont ajoutées avant l’upsert des lignes.
- **`INSERT … ON DUPLICATE KEY UPDATE`** sur les actifs : met à jour libellés, blurbs, catégories, profils de risque et ordre d’affichage **sans écraser** les prix en cours si vous les avez déjà modifiés en base (seules les colonnes listées dans le `UPDATE` sont rafraîchies).

Les fichiers `sql/market_v2_migration.sql` et `sql/market_v3_expansion.sql` sont **dépréciés** ; tout est fusionné dans le fichier unique ci-dessus.

---

## LB Phone — plug & play

Aucune modification des fichiers internes de **lb-phone** n’est requise.

- Tant que la ressource **`lb-phone`** est **started**, le client `ascension_bank` tente d’enregistrer l’app custom **`ascension_trade`** (`client/lbphone_app.lua`).
- L’UI embarquée pointe vers : `ascension_bank/web/lbphone/index.html` (déclarée dans le `fxmanifest` `files {}`).
- Les callbacks NUI appellent les mêmes callbacks serveur que la banque (marché cohérent).

**Condition unique :** `lb-phone` doit être démarré **avant** ou en même temps que les joueurs chargent ; en cas d’échec, le script retente plusieurs fois au démarrage ressource / `esx:playerLoaded`. Vérifiez la console client si le message d’échec d’enregistrement apparaît.

---

## Configuration

### Fichier `shared/defaults.lua`

- **`bank.settings`** / **`atm.settings`** : limites, frais.
- **`bank.entries`** / **`atm.entries`** : positions **ox_target** (coords, zones).
- **`trading`** : intervalle de tick, frais d’ordre, min/max ordre, plafonds d’exposition (`maxPositionValue`, **`primeMaxPositionValue`** pour **CedricPoint**), volatilités par classe (`cryptoBaseVol`, `commodityBaseVol`, `equityBaseVol`, etc.), bornes d’« économie serveur » (`economyBankLow` / `economyBankHigh`).

### Module `ascension_adminconfig` (optionnel)

Si la ressource **`ascension_adminconfig`** est démarrée et expose `GetModuleConfig('bank')`, les clés de `bank.settings` et `bank.settings.trading` peuvent **écraser** les valeurs de `defaults.lua` sans éditer les fichiers (utile en prod).

---

## Marché & CedricPoint ($CP)

- **Actif** : `CEDRIC_PT` — *CedricPoint ($CP)*, profil SQL **`prime`**.
- Côté client, le profil est présenté comme **institutionnel** ; filtre dédié **Instit.** dans les UIs marché.
- **Plafond** : `primeMaxPositionValue` dans `defaults.lua` (défaut adapté à un actif « premium serveur »).
- **Ticks** : logique serveur séparée (biais / plancher / plafond) dans `server/market.lua` — ne pas confondre avec les cryptos « bluechip » standard.

Autres familles d’actifs : **crypto** (dont stable **AngeloUSD**), **index**, **commodity** (métaux, pétrole, agro, etc.), **equity** (actions lore LS : Fleeca, Maze, GoPostal, …).

---

## Structure du projet

```
ascension_bank/
├── fxmanifest.lua
├── README.md
├── shared/
│   ├── defaults.lua      # Banques, ATM, trading (dont CedricPoint / prime)
│   └── utils.lua
├── server/
│   ├── main.lua          # Comptes, transactions, carte, NUI banque
│   ├── market.lua        # Ticks marché, positions, effet foule
│   └── discord_webhooks.lua
├── client/
│   ├── main.lua
│   └── lbphone_app.lua   # Enregistrement LB Phone « Trade »
├── ui/                   # NUI banque (dont onglet marché)
└── web/lbphone/          # UI de l’app Trade (LB Phone)
└── sql/
    ├── ascension_bank_full.sql   # ← import unique recommandé (canonique)
    └── install.sql               # copie identique
```

---

## Modifier / personnaliser

| Objectif | Où agir |
|----------|---------|
| Nouvelle banque / ATM | `shared/defaults.lua` → `entries` (id, coords, zone) |
| Limites virement / frais | `defaults.lua` ou adminconfig |
| **Nouvel actif boursier** | Table `aab_market_assets` : nouvelle ligne (id unique, `category`, `risk_profile`, prix de base). Puis redémarrage ou prochain tick. Vous pouvez étendre le même `INSERT` du fichier SQL pour les futurs dumps. |
| Calmer / aggraver le marché | `trading` dans `defaults.lua` : `*BaseVol`, `*MaxTickPct`, `tickIntervalMs` |
| **CedricPoint** : plafond joueur | `primeMaxPositionValue` |
| Webhooks Discord | `server.cfg` → convars `asc_bank_*` (voir ci-dessous) |
| Texte / branding app téléphone | `web/lbphone/*` + `client/lbphone_app.lua` (`name`, `description`, `icon`) |

> Après modification Lua, `refresh` ou restart de `ascension_bank`. Après ajout d’actifs SQL, un `INSERT` ou import partiel suffit ; pas besoin de réimporter tout le fichier si vous savez ce que vous faites.

---

## Discord (webhooks optionnels)

Définir dans **`server.cfg`** (exemple) :

```cfg
set asc_bank_webhook_general "https://discord.com/api/webhooks/..."
set asc_bank_webhook_trading "https://discord.com/api/webhooks/..."
# Intervalle minimum 60 s ; défaut 10 min
set asc_bank_market_report_ms "600000"
```

Si les convars sont vides, aucun envoi n’est effectué.

---

## Dépannage

| Problème | Piste |
|----------|--------|
| Erreur SQL à l’import | Utiliser **MariaDB / MySQL** récent ; exécuter le fichier **entier** ; vérifier les droits `CREATE`, `ALTER`, `DROP` (procédure temporaire). |
| Pas d’app Trade sur le téléphone | `ensure lb-phone` avant le joueur ; vérifier les logs client `ascension_bank`. |
| Carte introuvable | Item + image `creditcard` côté **ox_inventory**. |
| Solde incohérent | Rappel : le **bank** ESX reste la source de vérité ; en cas de désync extrême, vérifier les events ESX et les erreurs `oxmysql`. |
| Marché vide | Tables `aab_market_assets` non importées → réimporter `ascension_bank_full.sql`. |

---

## Crédits & licence

- **Auteur / édition** : **CedricPoint** — *Ascension Bank — CedricPoint Edition* **v2.1.0**.
- Actif fictif **CedricPoint ($CP)** et marque **Ascension** : cohérence roleplay avec le serveur Ascension RP.
- **LB Phone** est un produit tiers (Lb Scripts) ; cette ressource ne l’inclut pas, elle s’y **branche** uniquement.

Licence : celle indiquée sur le dépôt GitHub (si aucune licence n’est fournie, considérez le contenu comme **tous droits réservés** par l’auteur jusqu’à clarification).

---

*README généré pour une documentation GitHub complète — schéma SQL **2.1.0** — **CedricPoint**.*
