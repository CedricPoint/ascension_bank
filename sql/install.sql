-- =============================================================================
-- Ascension Bank — schéma SQL complet (CedricPoint Edition)
-- =============================================================================
-- Auteur / projet : CedricPoint (Ascension Bank)
-- Version schéma : 2.1.0 — inclut banque, historique, marché (crypto, matières
--   premières, actions LS), positions joueurs, actif institutionnel CedricPoint ($CP).
--
-- Usage :
--   • Nouvelle base : importer ce fichier une fois (phpMyAdmin, HeidiSQL, CLI).
--   • Ancienne base (v1 sans colonnes marché) : ce script crée les tables
--     manquantes puis applique les colonnes legacy si besoin, puis upsert les actifs.
--
-- Remplace les anciens fragments : market_v2_migration.sql, market_v3_expansion.sql
-- (conservés uniquement comme archive ; l’état final est ici).
-- =============================================================================

CREATE TABLE IF NOT EXISTS `aab_bank_accounts` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `identifier` VARCHAR(64) NOT NULL,
  `owner_name` VARCHAR(128) NOT NULL,
  `iban` VARCHAR(34) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_aab_bank_accounts_identifier` (`identifier`),
  UNIQUE KEY `uniq_aab_bank_accounts_iban` (`iban`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `aab_bank_transactions` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `account_id` INT NOT NULL,
  `transaction_type` VARCHAR(32) NOT NULL,
  `amount` INT NOT NULL DEFAULT 0,
  `balance_after` INT NOT NULL DEFAULT 0,
  `reason` VARCHAR(128) DEFAULT NULL,
  `counterparty_iban` VARCHAR(34) DEFAULT NULL,
  `counterparty_name` VARCHAR(128) DEFAULT NULL,
  `metadata` LONGTEXT DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_aab_bank_transactions_account_id` (`account_id`),
  CONSTRAINT `fk_aab_bank_transactions_account_id`
    FOREIGN KEY (`account_id`) REFERENCES `aab_bank_accounts` (`id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `aab_market_assets` (
  `asset_id` VARCHAR(32) NOT NULL,
  `label` VARCHAR(64) NOT NULL,
  `blurb` VARCHAR(240) NULL DEFAULT NULL,
  `category` VARCHAR(24) NOT NULL,
  `risk_profile` VARCHAR(24) NOT NULL DEFAULT 'standard',
  `sort_order` INT NOT NULL DEFAULT 100,
  `base_price` DECIMAL(16,4) NOT NULL,
  `current_price` DECIMAL(16,4) NOT NULL,
  `previous_price` DECIMAL(16,4) NOT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`asset_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `aab_market_positions` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `account_id` INT NOT NULL,
  `identifier` VARCHAR(64) NOT NULL,
  `asset_id` VARCHAR(32) NOT NULL,
  `units` DECIMAL(22,8) NOT NULL DEFAULT 0.00000000,
  `avg_buy_price` DECIMAL(16,4) NOT NULL DEFAULT 0.0000,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_aab_market_positions_account_asset` (`account_id`, `asset_id`),
  KEY `idx_aab_market_positions_identifier` (`identifier`),
  CONSTRAINT `fk_aab_market_positions_account`
    FOREIGN KEY (`account_id`) REFERENCES `aab_bank_accounts` (`id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$

DROP PROCEDURE IF EXISTS `asc_bank_legacy_market_assets`$$

CREATE PROCEDURE `asc_bank_legacy_market_assets`()
BEGIN
    DECLARE t_exists INT DEFAULT 0;
    DECLARE c_exists INT DEFAULT 0;

    SELECT COUNT(*) INTO t_exists
    FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'aab_market_assets';

    IF t_exists > 0 THEN
        SELECT COUNT(*) INTO c_exists
        FROM information_schema.columns
        WHERE table_schema = DATABASE() AND table_name = 'aab_market_assets' AND column_name = 'blurb';
        IF c_exists = 0 THEN
            ALTER TABLE `aab_market_assets` ADD COLUMN `blurb` VARCHAR(240) NULL DEFAULT NULL AFTER `label`;
        END IF;

        SELECT COUNT(*) INTO c_exists
        FROM information_schema.columns
        WHERE table_schema = DATABASE() AND table_name = 'aab_market_assets' AND column_name = 'risk_profile';
        IF c_exists = 0 THEN
            ALTER TABLE `aab_market_assets` ADD COLUMN `risk_profile` VARCHAR(24) NOT NULL DEFAULT 'standard' AFTER `category`;
        END IF;

        SELECT COUNT(*) INTO c_exists
        FROM information_schema.columns
        WHERE table_schema = DATABASE() AND table_name = 'aab_market_assets' AND column_name = 'sort_order';
        IF c_exists = 0 THEN
            ALTER TABLE `aab_market_assets` ADD COLUMN `sort_order` INT NOT NULL DEFAULT 100 AFTER `risk_profile`;
        END IF;

        SELECT COUNT(*) INTO c_exists
        FROM information_schema.columns
        WHERE table_schema = DATABASE() AND table_name = 'aab_market_assets' AND column_name = 'updated_at';
        IF c_exists = 0 THEN
            ALTER TABLE `aab_market_assets` ADD COLUMN `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP;
        END IF;

        ALTER TABLE `aab_market_assets` MODIFY COLUMN `category` VARCHAR(24) NOT NULL;
    END IF;
END$$

DELIMITER ;

CALL `asc_bank_legacy_market_assets`();

DROP PROCEDURE IF EXISTS `asc_bank_legacy_market_assets`;

INSERT INTO `aab_market_assets` (`asset_id`, `label`, `blurb`, `category`, `risk_profile`, `sort_order`, `base_price`, `current_price`, `previous_price`) VALUES
('BLC_LS', 'Blancoin', 'Référence « grande cap » — mouvements liés au sentiment macro LS.', 'crypto', 'bluechip', 5, 98250.0000, 98250.0000, 98250.0000),
('ETHER_LS', 'LosEther', 'Couche programmable — DEFI, NFT et gas fees imprévisibles.', 'crypto', 'bluechip', 8, 3450.0000, 3450.0000, 3450.0000),
('LSX', 'Los Santos X', 'Écosystème smart contracts Los Santos — liquidité élevée.', 'crypto', 'bluechip', 14, 42.5000, 42.5000, 42.5000),
('IDX_LS50', 'LS BlueChip 50', 'Indice synthétique top 50 — beta ~0,85 vs cryptos seules.', 'index', 'index', 18, 4200.0000, 4200.0000, 4200.0000),
('CARDAN_LS', 'Cardania', 'Proof-of-stake académique — upgrades lents mais communauté solide.', 'crypto', 'standard', 22, 0.5200, 0.5200, 0.5200),
('CEDRIC_PT', 'CedricPoint ($CP)', 'Réseau de règlement discret — carnet restreint, volumes OTC.', 'crypto', 'prime', 24, 88.0000, 88.0000, 88.0000),
('SOLARPAY', 'SolPay', 'Layer-1 rapide — pannes réseau et forks « sunsetting » fréquents.', 'crypto', 'volatile', 26, 145.0000, 145.0000, 145.0000),
('RIPPLEDOG', 'RippDog', 'Visa crypto institutionnelle — stress tests régulateurs.', 'crypto', 'volatile', 28, 0.6200, 0.6200, 0.6200),
('ASC_COIN', 'Ascension Coin', 'Jeton régional Ascension — forte corrélation à l’activité du serveur.', 'crypto', 'volatile', 30, 118.0000, 118.0000, 118.0000),
('MEME_DSTRT', 'DogeStreet', 'Mème historique — aucun fondamental, pur marché des sentiments.', 'crypto', 'meme', 40, 0.0850, 0.0850, 0.0850),
('PEPE_SANDY', 'Pepe Sandy Shores', 'Mème « dégénéré » — pumps violentes et dumps overnight.', 'crypto', 'meme', 42, 0.0120, 0.0120, 0.0120),
('APE_LS', 'ApeCoin LS', 'Culture NFT metaverse — corrélation événements & célébrités.', 'crypto', 'meme', 44, 1.8500, 1.8500, 1.8500),
('SHIB_RUN', 'Shiba Run', 'Ultra volatile, offre massive — penny stock crypto.', 'crypto', 'meme', 46, 0.0028, 0.0028, 0.0028),
('RUGMETER', 'RugMeter Perp', 'Produit synthétique inverse — biais vendeur, liquidations en cascade.', 'crypto', 'extreme', 50, 112.0000, 112.0000, 112.0000),
('AURUM', 'Or (once)', 'Couverture classique contre l’inflation.', 'commodity', 'metal', 60, 2150.0000, 2150.0000, 2150.0000),
('ARGENTUM', 'Argent métal', 'Industriel, photovoltaïque et bijouterie.', 'commodity', 'metal', 62, 26.8000, 26.8000, 26.8000),
('PLATINA', 'Platine (once)', 'Catalyseur auto & joaillerie — spread plus large que l’or.', 'commodity', 'metal', 64, 980.0000, 980.0000, 980.0000),
('CUPRUM', 'Cuivre LS', 'Cycle industriel & infrastructures — sensible à la construction.', 'commodity', 'metal', 66, 4.1200, 4.1200, 4.1200),
('PALLADIUM_LS', 'Palladium', 'Automobile & contraintes d’offre — pics brutaux possibles.', 'commodity', 'metal', 68, 1850.0000, 1850.0000, 1850.0000),
('WTI_LS', 'Pétrole Brent LS', 'Énergie & géopolitique — corrélation événements mondiaux fictifs.', 'commodity', 'oil', 70, 78.5000, 78.5000, 78.5000),
('NATGAZ_LS', 'Gaz naturel (Henry Hub LS)', 'Stockage, météo et pipelines — corrélation partielle à l’énergie.', 'commodity', 'oil', 72, 3.8500, 3.8500, 3.8500),
('WHEAT_LS', 'Blé Plains', 'Agro & export — sensible aux aléas climatiques du comté.', 'commodity', 'standard', 74, 6.2000, 6.2000, 6.2000),
('LITHIUM_LS', 'Carbonate de lithium', 'Batteries & EV — offre concentrée, cycles d’investissement.', 'commodity', 'volatile', 76, 42.0000, 42.0000, 42.0000),
('RARE_EARTH', 'Terres rares LS', 'Magnets & high-tech — quotas et tensions commerciales fictives.', 'commodity', 'volatile', 78, 188.0000, 188.0000, 188.0000),
('STABLELS', 'AngeloUSD', 'Stable adossée — faible dérive autour du peg, peu de « moon ».', 'crypto', 'stable', 80, 1.0000, 1.0000, 1.0000),
('MONERO_LS', 'MonoRing', 'Confidentialité — listings et pression réglementaire.', 'crypto', 'volatile', 82, 165.0000, 165.0000, 165.0000),
('ORACLE_LS', 'ChainLester', 'Oracles & données — risque de feeds compromis.', 'crypto', 'standard', 84, 18.5000, 18.5000, 18.5000),
('EQ_FLEECA', 'Fleeca Bancorp', 'Réseau de succursales — bêta modérée, sensible aux taux.', 'equity', 'bluechip', 120, 420.0000, 420.0000, 420.0000),
('EQ_MAZE', 'Maze Bank Group', 'Financement corporate LS — image premium, cycles économiques.', 'equity', 'bluechip', 122, 680.0000, 680.0000, 680.0000),
('EQ_GO_POSTAL', 'GoPostal Logistics', 'E-commerce & dernier kilomètre — marges cycliques.', 'equity', 'standard', 124, 38.5000, 38.5000, 38.5000),
('EQ_LIFEIV', 'Lifeinvader Inc.', 'Social & pub — scandales et engagement utilisateurs volatils.', 'equity', 'volatile', 126, 52.0000, 52.0000, 52.0000),
('EQ_WEAZEL', 'Weazel News Group', 'Médias & audiences — corrélation événements / politique LS.', 'equity', 'standard', 128, 24.8000, 24.8000, 24.8000),
('EQ_BURGERSHOT', 'BurgerShot Franchising', 'Restauration rapide — hype et normes sanitaires.', 'equity', 'volatile', 130, 14.2000, 14.2000, 14.2000),
('EQ_PEGASUS', 'Pegasus Concierge', 'Aviation privée & luxe — commandes cycliques.', 'equity', 'standard', 132, 96.0000, 96.0000, 96.0000),
('EQ_ATOMIC', 'Atomic Motor Co.', 'Constructeur automobile LS — lancements & rappels.', 'equity', 'standard', 134, 58.0000, 58.0000, 58.0000),
('EQ_HVY_TOOL', 'HVY Industrial', 'Engins & BTP — carnet sensible aux grands chantiers.', 'equity', 'standard', 136, 31.0000, 31.0000, 31.0000),
('EQ_VANKHOV', 'Vankhov Mining', 'Extraction & métaux — bêta matières premières.', 'equity', 'volatile', 138, 22.5000, 22.5000, 22.5000),
('EQ_DYNASTY', 'Dynasty 8 Realty', 'Immobilier résidentiel — cycles de taux & crédit.', 'equity', 'bluechip', 140, 45.0000, 45.0000, 45.0000)
ON DUPLICATE KEY UPDATE
  `label` = VALUES(`label`),
  `blurb` = VALUES(`blurb`),
  `category` = VALUES(`category`),
  `risk_profile` = VALUES(`risk_profile`),
  `sort_order` = VALUES(`sort_order`);

-- =============================================================================
-- Fin — Ascension Bank 2.1.0 (CedricPoint Edition)
-- =============================================================================
