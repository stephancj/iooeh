-- Les quotas de véhicules ne font plus partie des plans.
-- Conserver la colonne historique pour éviter toute perte de données.
DELETE FROM features WHERE code = 'max_vehicles';
UPDATE plans SET description = 'Pour découvrir iooeh.' WHERE code = 'free' AND description = 'Pour découvrir iooeh avec un seul véhicule.';
