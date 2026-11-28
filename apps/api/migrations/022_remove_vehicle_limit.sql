-- Les quotas de véhicules ne font plus partie des plans.
-- Conserver la colonne historique pour éviter toute perte de données.
-- La table créée par la migration 023 indique que le nettoyage historique a déjà eu lieu.
WITH removed_quota AS (
  DELETE FROM features
  WHERE code = 'max_vehicles' AND to_regclass('public.vehicle_subscriptions') IS NULL
  RETURNING id
)
UPDATE plans SET description = 'Pour découvrir iooeh.'
WHERE code = 'free'
  AND description = 'Pour découvrir iooeh avec un seul véhicule.'
  AND EXISTS (SELECT 1 FROM removed_quota);
