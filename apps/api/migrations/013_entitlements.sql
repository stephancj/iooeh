-- Catalogue commercial : fonctionnalités, plans et droits par plan.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Initialiser le catalogue à la première création des tables.
-- Les valeurs existantes sont gérées dans le back-office.
DO $$
DECLARE
  initialize_catalogue BOOLEAN := to_regclass('plans') IS NULL;
BEGIN
  CREATE TABLE IF NOT EXISTS features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(100) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    category VARCHAR(100) NOT NULL DEFAULT 'general',
    value_type VARCHAR(20) NOT NULL DEFAULT 'boolean'
      CHECK (value_type IN ('boolean', 'number', 'string')),
    unit VARCHAR(50),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );

  CREATE TABLE IF NOT EXISTS plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price_monthly NUMERIC(12,2) NOT NULL DEFAULT 0,
    currency VARCHAR(3) NOT NULL DEFAULT 'MGA',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    display_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );

  CREATE TABLE IF NOT EXISTS plan_features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
    feature_id UUID NOT NULL REFERENCES features(id) ON DELETE CASCADE,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    value JSONB,
    CONSTRAINT uq_plan_features UNIQUE (plan_id, feature_id)
  );

  CREATE INDEX IF NOT EXISTS idx_plan_features_plan ON plan_features(plan_id);
  CREATE INDEX IF NOT EXISTS idx_plan_features_feature ON plan_features(feature_id);

  CREATE TABLE IF NOT EXISTS subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    plan VARCHAR(50) NOT NULL DEFAULT 'free',
    status VARCHAR(50) NOT NULL DEFAULT 'trial',
    vehicle_limit INTEGER NOT NULL DEFAULT 1,
    next_billing_date TIMESTAMPTZ,
    trial_ends_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );

  ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS plan_id UUID;
  BEGIN
    ALTER TABLE subscriptions
      ADD CONSTRAINT fk_subscriptions_plan FOREIGN KEY (plan_id) REFERENCES plans(id);
  EXCEPTION WHEN duplicate_object THEN NULL;
  END;

  IF initialize_catalogue THEN
    INSERT INTO features (code, name, description, category, value_type, unit, display_order) VALUES
      ('live_tracking', 'Suivi en direct', 'Position et statut actualisés toutes les 10 secondes.', 'Tracking', 'boolean', NULL, 10),
      ('max_vehicles', 'Véhicules maximum', 'Nombre maximal de véhicules rattachés au compte.', 'Flotte', 'number', 'véhicules', 20),
      ('fleet_overview', 'Vue d’ensemble flotte', 'Compteurs et synthèse de l’état de la flotte.', 'Flotte', 'boolean', NULL, 30),
      ('vehicle_telemetry', 'Télémétrie véhicule', 'Vitesse, batterie, contact et force du signal.', 'Tracking', 'boolean', NULL, 40),
      ('history', 'Historique cartographique', 'Consultation des positions et trajets passés.', 'Historique', 'boolean', NULL, 50),
      ('history_retention_days', 'Rétention historique', 'Ancienneté maximale consultable.', 'Historique', 'number', 'jours', 60),
      ('trip_analysis', 'Analyse journalière des trajets', 'Découpage des trajets, arrêts et statistiques.', 'Historique', 'boolean', NULL, 70),
      ('max_geofences', 'Zones maximum', 'Nombre maximal de geofences actives ou inactives.', 'Zones', 'number', 'zones', 80),
      ('geofence_alerts', 'Alertes de zones', 'Alertes d’entrée et de sortie des zones.', 'Alertes', 'boolean', NULL, 90),
      ('low_battery_alerts', 'Alertes batterie faible', 'Alerte lorsque la batterie passe sous 20 %.', 'Alertes', 'boolean', NULL, 100),
      ('speed_alerts', 'Alertes de vitesse', 'Détection des dépassements de vitesse.', 'Alertes', 'boolean', NULL, 110),
      ('sleep_mode', 'Veille antivol', 'Détection de mouvement autour du point d’armement.', 'Sécurité', 'boolean', NULL, 120),
      ('push_notifications', 'Notifications push', 'Réception des alertes sur le navigateur ou le téléphone.', 'Notifications', 'boolean', NULL, 130),
      ('whatsapp_notifications', 'Notifications WhatsApp', 'Réception des alertes via WhatsApp Business.', 'Notifications', 'boolean', NULL, 140),
      ('activity_reports', 'Résumé d’activité', 'Distance, conduite, arrêts et vitesse maximale.', 'Rapports', 'boolean', NULL, 150),
      ('trip_reports', 'Journal des trajets', 'Liste des trajets reconstitués par période.', 'Rapports', 'boolean', NULL, 160),
      ('speed_reports', 'Rapport des excès de vitesse', 'Épisodes et pics de vitesse sur une période.', 'Rapports', 'boolean', NULL, 170),
      ('idle_reports', 'Rapport d’inactivité', 'Épisodes d’immobilisation prolongée.', 'Rapports', 'boolean', NULL, 180),
      ('geofence_reports', 'Rapport des zones', 'Entrées et sorties agrégées par zone.', 'Rapports', 'boolean', NULL, 190)
    ON CONFLICT (code) DO NOTHING;

    INSERT INTO plans (code, name, description, price_monthly, currency, display_order) VALUES
      ('free', 'Free', 'Pour découvrir iooeh avec un seul véhicule.', 0, 'MGA', 10),
      ('basic', 'Basic', 'Le suivi essentiel pour particuliers et petites flottes.', 29000, 'MGA', 20),
      ('premium', 'Premium', 'Toutes les capacités opérationnelles pour une flotte.', 69000, 'MGA', 30)
    ON CONFLICT (code) DO NOTHING;

    WITH grants(plan_code, feature_code, feature_value) AS (
      VALUES
        ('free','live_tracking','true'::jsonb), ('free','max_vehicles','1'::jsonb),
        ('free','fleet_overview','true'::jsonb), ('free','vehicle_telemetry','true'::jsonb),
        ('free','history','true'::jsonb), ('free','history_retention_days','1'::jsonb),
        ('free','max_geofences','1'::jsonb), ('free','geofence_alerts','true'::jsonb),
        ('free','low_battery_alerts','true'::jsonb), ('free','push_notifications','true'::jsonb),

        ('basic','live_tracking','true'::jsonb), ('basic','max_vehicles','5'::jsonb),
        ('basic','fleet_overview','true'::jsonb), ('basic','vehicle_telemetry','true'::jsonb),
        ('basic','history','true'::jsonb), ('basic','history_retention_days','30'::jsonb),
        ('basic','trip_analysis','true'::jsonb), ('basic','max_geofences','10'::jsonb),
        ('basic','geofence_alerts','true'::jsonb), ('basic','low_battery_alerts','true'::jsonb),
        ('basic','speed_alerts','true'::jsonb), ('basic','sleep_mode','true'::jsonb),
        ('basic','push_notifications','true'::jsonb), ('basic','whatsapp_notifications','true'::jsonb),
        ('basic','activity_reports','true'::jsonb), ('basic','trip_reports','true'::jsonb),
        ('basic','speed_reports','true'::jsonb), ('basic','idle_reports','true'::jsonb),
        ('basic','geofence_reports','true'::jsonb),

        ('premium','live_tracking','true'::jsonb), ('premium','max_vehicles','999'::jsonb),
        ('premium','fleet_overview','true'::jsonb), ('premium','vehicle_telemetry','true'::jsonb),
        ('premium','history','true'::jsonb), ('premium','history_retention_days','365'::jsonb),
        ('premium','trip_analysis','true'::jsonb), ('premium','max_geofences','999'::jsonb),
        ('premium','geofence_alerts','true'::jsonb), ('premium','low_battery_alerts','true'::jsonb),
        ('premium','speed_alerts','true'::jsonb), ('premium','sleep_mode','true'::jsonb),
        ('premium','push_notifications','true'::jsonb), ('premium','whatsapp_notifications','true'::jsonb),
        ('premium','activity_reports','true'::jsonb), ('premium','trip_reports','true'::jsonb),
        ('premium','speed_reports','true'::jsonb), ('premium','idle_reports','true'::jsonb),
        ('premium','geofence_reports','true'::jsonb)
    )
    INSERT INTO plan_features (plan_id, feature_id, enabled, value)
    SELECT p.id, f.id, TRUE, g.feature_value
    FROM grants g
    JOIN plans p ON p.code = g.plan_code
    JOIN features f ON f.code = g.feature_code
    ON CONFLICT (plan_id, feature_id) DO NOTHING;
  END IF;
END;
$$;

UPDATE subscriptions s SET plan_id = p.id FROM plans p
WHERE p.code = s.plan AND s.plan_id IS NULL;

INSERT INTO subscriptions (user_id, plan_id, plan, status, vehicle_limit, trial_ends_at)
SELECT u.id, p.id, 'free', 'trial', 1, NOW() + INTERVAL '30 days'
FROM users u CROSS JOIN plans p
WHERE p.code = 'free'
ON CONFLICT (user_id) DO NOTHING;
