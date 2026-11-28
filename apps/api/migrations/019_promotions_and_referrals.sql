-- Migration 019: Système de Parrainage et Coupons avec Dynamic Redeem

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Initialiser le catalogue à la première création des tables.
-- Les valeurs existantes sont gérées dans le back-office.
DO $$
DECLARE
  initialize_catalogue BOOLEAN := to_regclass('coupon_redemptions') IS NULL;
BEGIN
  -- 1. Ajout de la colonne referral_code à la table users
  ALTER TABLE users ADD COLUMN IF NOT EXISTS referral_code VARCHAR(30);

  -- Unicité sur referral_code (quand non null). Un index nommé peut déjà
  -- exister sur les installations ayant exécuté une version antérieure :
  -- IF NOT EXISTS rend le rejeu de cette migration réellement idempotent.
  CREATE UNIQUE INDEX IF NOT EXISTS uq_users_referral_code
    ON users (referral_code)
    WHERE referral_code IS NOT NULL;

  -- Enregistrer des codes parrainage par défaut pour tous les utilisateurs existants sans code
  UPDATE users
  SET referral_code = 'REF-' || UPPER(SUBSTRING(MD5(id::text || RANDOM()::text) FROM 1 FOR 6))
  WHERE referral_code IS NULL;

  -- 2. Table des Coupons / Codes Promo
  CREATE TABLE IF NOT EXISTS coupons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) NOT NULL UNIQUE,
    reward_type VARCHAR(50) NOT NULL, -- 'FREE_PLAN_GIFT', 'FREE_SUBSCRIPTION_DAYS', 'PERCENTAGE_DISCOUNT', 'FIXED_DISCOUNT', 'VEHICLE_QUOTA_BONUS'
    reward_value NUMERIC(12, 2) NOT NULL DEFAULT 0,
    granted_plan_id UUID REFERENCES plans(id) ON DELETE SET NULL, -- Plan offert (si FREE_PLAN_GIFT)
    target_plan_id UUID REFERENCES plans(id) ON DELETE SET NULL,  -- Plan spécifique requis (si réduction)
    min_plan_price NUMERIC(12, 2) NOT NULL DEFAULT 0,
    max_redemptions INT, -- Illimité si NULL
    redemptions_count INT NOT NULL DEFAULT 0,
    max_redemptions_per_user INT NOT NULL DEFAULT 1,
    expires_at TIMESTAMPTZ,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );

  -- 3. Table des Références Parrainage (Parrain <-> Filleul)
  CREATE TABLE IF NOT EXISTS referrals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    referrer_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    referee_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    code_used VARCHAR(30) NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'pending', -- 'pending', 'qualified', 'rewarded'
    referrer_reward_type VARCHAR(50) NOT NULL DEFAULT 'FREE_SUBSCRIPTION_DAYS',
    referrer_reward_value NUMERIC(12, 2) NOT NULL DEFAULT 30,
    referee_reward_type VARCHAR(50) NOT NULL DEFAULT 'PERCENTAGE_DISCOUNT',
    referee_reward_value NUMERIC(12, 2) NOT NULL DEFAULT 20,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_referrals_referee UNIQUE (referee_id)
  );

  CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON referrals(referrer_id);
  CREATE INDEX IF NOT EXISTS idx_referrals_referee ON referrals(referee_id);

  -- 4. Table d'historique des Réductions et Redemptions
  CREATE TABLE IF NOT EXISTS coupon_redemptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    coupon_id UUID REFERENCES coupons(id) ON DELETE SET NULL,
    referral_id UUID REFERENCES referrals(id) ON DELETE SET NULL,
    reward_type VARCHAR(50) NOT NULL,
    reward_value NUMERIC(12, 2) NOT NULL DEFAULT 0,
    applied_to_payment_id UUID REFERENCES payments(id) ON DELETE SET NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );

  CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_user ON coupon_redemptions(user_id);

  -- 5. Enregistrement des fonctionnalités commerciales dans `features` & raccordement aux plans `plan_features`

  IF initialize_catalogue THEN
    INSERT INTO features (code, name, description, category, value_type, unit, display_order) VALUES
      ('coupon_redemption', 'Codes promo & Coupons', 'Possibilité d’utiliser des codes promo et coupons de réduction ou d’avantages.', 'Promotions', 'boolean', NULL, 200),
      ('referral_program', 'Programme de parrainage', 'Accès au code parrainage unique pour inviter des amis et gagner des récompenses.', 'Promotions', 'boolean', NULL, 210)
    ON CONFLICT (code) DO NOTHING;

    -- Raccordement par défaut aux plans
    INSERT INTO plan_features (plan_id, feature_id, enabled, value)
    SELECT p.id, f.id, TRUE, 'true'::jsonb
    FROM plans p
    CROSS JOIN features f
    WHERE f.code IN ('coupon_redemption', 'referral_program')
    ON CONFLICT (plan_id, feature_id) DO NOTHING;
  END IF;
END;
$$;
