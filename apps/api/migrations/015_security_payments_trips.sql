DO $$
DECLARE enum_name TEXT;
BEGIN
  SELECT typname INTO enum_name FROM pg_type
  WHERE typname IN ('alerts_type_enum', 'alert_type')
  ORDER BY CASE WHEN typname = 'alerts_type_enum' THEN 0 ELSE 1 END LIMIT 1;
  IF enum_name IS NOT NULL THEN
    EXECUTE format('ALTER TYPE %I ADD VALUE IF NOT EXISTS %L', enum_name, 'theft');
  END IF;
END $$;

-- Initialiser le catalogue à la première création des tables.
-- Les valeurs existantes sont gérées dans le back-office.
DO $$
DECLARE
  initialize_catalogue BOOLEAN := to_regclass('payments') IS NULL;
BEGIN
  CREATE TABLE IF NOT EXISTS security_incidents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id INTEGER NOT NULL, alert_id UUID REFERENCES alerts(id) ON DELETE SET NULL, source_event_id BIGINT UNIQUE,
    type VARCHAR(40) NOT NULL, status VARCHAR(40) NOT NULL DEFAULT 'open', severity VARCHAR(20) NOT NULL DEFAULT 'critical',
    title TEXT, description TEXT, lat DOUBLE PRECISION, lon DOUBLE PRECISION, assigned_to INTEGER REFERENCES users(id) ON DELETE SET NULL,
    cancel_until TIMESTAMPTZ, escalate_at TIMESTAMPTZ, acknowledged_at TIMESTAMPTZ, escalated_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ, resolution_note TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_incidents_owner_created ON security_incidents(owner_id, created_at DESC);
  CREATE INDEX IF NOT EXISTS idx_incidents_pending_escalation ON security_incidents(status, escalate_at);

  CREATE TABLE IF NOT EXISTS incident_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), incident_id UUID NOT NULL REFERENCES security_incidents(id) ON DELETE CASCADE,
    actor_id INTEGER REFERENCES users(id) ON DELETE SET NULL, action VARCHAR(50) NOT NULL, note TEXT, metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_incident_events_incident ON incident_events(incident_id, created_at);

  CREATE TABLE IF NOT EXISTS public_tracking_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), owner_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id INTEGER NOT NULL, token_hash VARCHAR(64) NOT NULL UNIQUE, expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ, view_count INTEGER NOT NULL DEFAULT 0, last_viewed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_tracking_links_owner_device ON public_tracking_links(owner_id, device_id);

  CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan_id UUID NOT NULL REFERENCES plans(id), reference VARCHAR(80) NOT NULL UNIQUE, amount INTEGER NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'MGA', status VARCHAR(30) NOT NULL DEFAULT 'created', provider VARCHAR(30),
    payment_method VARCHAR(30), payment_link TEXT, papi_notification_token TEXT, papi_merchant_reference VARCHAR(100),
    failure_message TEXT, paid_at TIMESTAMPTZ, expires_at TIMESTAMPTZ, raw_notification JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_payments_user_created ON payments(user_id, created_at DESC);

  CREATE TABLE IF NOT EXISTS trips (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(), device_id INTEGER NOT NULL, owner_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    start_ts TIMESTAMPTZ NOT NULL, end_ts TIMESTAMPTZ NOT NULL, distance_km DOUBLE PRECISION NOT NULL DEFAULT 0,
    duration_s INTEGER NOT NULL DEFAULT 0, max_speed_kmh DOUBLE PRECISION NOT NULL DEFAULT 0,
    start_lat DOUBLE PRECISION NOT NULL, start_lon DOUBLE PRECISION NOT NULL, end_lat DOUBLE PRECISION NOT NULL, end_lon DOUBLE PRECISION NOT NULL,
    point_count INTEGER NOT NULL DEFAULT 0, path JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT "UQ_trips_device_start" UNIQUE(device_id, start_ts)
  );
  CREATE INDEX IF NOT EXISTS idx_trips_device_period ON trips(device_id, start_ts DESC);

  IF initialize_catalogue THEN
    INSERT INTO features (code, name, description, category, value_type, unit, display_order) VALUES
     ('sos_alerts','Alertes SOS','Déclenchement d’un incident SOS critique.','Sécurité','boolean',NULL,200),
     ('theft_mode','Mode vol','Dossier de récupération avec annulation sécurisée.','Sécurité','boolean',NULL,210),
     ('support_incidents','Incidents support','Suivi opérationnel des incidents critiques.','Sécurité','boolean',NULL,220),
     ('automatic_escalation','Escalade automatique','Escalade des incidents sans réponse.','Sécurité','boolean',NULL,230),
     ('public_tracking_links','Liens de suivi publics','Partage temporaire et révocable de la position.','Partage','boolean',NULL,240),
     ('max_active_tracking_links','Liens actifs maximum','Nombre maximal de liens de suivi actifs.','Partage','number','liens',250),
     ('incident_history_days','Historique des incidents','Durée de conservation consultable.','Sécurité','number','jours',260),
     ('trip_playback','Playback des trajets','Lecture animée d’un trajet persisté.','Rapports','boolean',NULL,270),
     ('report_exports','Exports PDF et CSV','Téléchargement des rapports de trajets.','Rapports','boolean',NULL,280),
     ('online_payments','Paiement en ligne','Souscription autonome via PAPI.mg.','Abonnement','boolean',NULL,290)
    ON CONFLICT (code) DO NOTHING;

    WITH grants(plan_code, feature_code, feature_value) AS (VALUES
     ('free','sos_alerts','true'::jsonb),('free','incident_history_days','7'::jsonb),('free','online_payments','true'::jsonb),
     ('basic','sos_alerts','true'::jsonb),('basic','theft_mode','true'::jsonb),('basic','support_incidents','true'::jsonb),
     ('basic','public_tracking_links','true'::jsonb),('basic','max_active_tracking_links','2'::jsonb),('basic','incident_history_days','90'::jsonb),
     ('basic','trip_playback','true'::jsonb),('basic','report_exports','true'::jsonb),('basic','online_payments','true'::jsonb),
     ('premium','sos_alerts','true'::jsonb),('premium','theft_mode','true'::jsonb),('premium','support_incidents','true'::jsonb),
     ('premium','automatic_escalation','true'::jsonb),('premium','public_tracking_links','true'::jsonb),('premium','max_active_tracking_links','20'::jsonb),
     ('premium','incident_history_days','365'::jsonb),('premium','trip_playback','true'::jsonb),('premium','report_exports','true'::jsonb),('premium','online_payments','true'::jsonb)
    )
    INSERT INTO plan_features(plan_id,feature_id,enabled,value)
    SELECT p.id,f.id,TRUE,g.feature_value FROM grants g JOIN plans p ON p.code=g.plan_code JOIN features f ON f.code=g.feature_code
    ON CONFLICT (plan_id,feature_id) DO NOTHING;
  END IF;
END;
$$;
