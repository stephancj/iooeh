-- Abonnements de test réinitialisés une seule fois : un essai de sept jours par véhicule.
DO $$
BEGIN
  IF to_regclass('public.vehicle_subscriptions') IS NULL THEN
    IF NOT EXISTS (SELECT 1 FROM plans WHERE code = 'free' AND is_active = TRUE) THEN
      RAISE EXCEPTION 'Le plan Free actif est requis pour initialiser les essais.';
    END IF;
    CREATE TABLE vehicle_subscriptions (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      assignment_id INTEGER NOT NULL UNIQUE REFERENCES device_assignments(id) ON DELETE CASCADE,
      plan_id UUID REFERENCES plans(id),
      plan VARCHAR(50) NOT NULL DEFAULT 'free',
      status VARCHAR(50) NOT NULL DEFAULT 'trial',
      trial_ends_at TIMESTAMPTZ,
      next_billing_date TIMESTAMPTZ,
      notes TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    INSERT INTO vehicle_subscriptions (assignment_id, plan_id, plan, status, trial_ends_at)
    SELECT a.id, p.id, p.code, 'trial', NOW() + INTERVAL '7 days'
    FROM device_assignments a CROSS JOIN plans p WHERE p.code = 'free' AND p.is_active = TRUE;
    DELETE FROM subscriptions;
  END IF;
END $$;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS assignment_id INTEGER;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS coupon_id UUID;
ALTER TABLE payments ADD COLUMN IF NOT EXISTS referral_id UUID;
