# mobile

iooeh GPS Tracking Mobile App

## Fonds de carte

Sans configuration, les cartes utilisent OpenStreetMap, sans clé API. Le bouton
calques permet aussi de sélectionner le satellite Esri.

Les styles CARTO (Voyager, Positron, Dark Matter) exigent désormais une clé.
Pour les utiliser, demander une clé sur [CARTO Basemaps](https://www.carto.com/basemaps/apikey/)
et la transmettre à Flutter :

```bash
flutter run -d chrome --dart-define=CARTO_BASEMAP_API_KEY=VOTRE_CLE
flutter build web --release --dart-define=CARTO_BASEMAP_API_KEY=VOTRE_CLE
```

Pour conserver la clé localement, ajouter `CARTO_BASEMAP_API_KEY=VOTRE_CLE`
dans `apps/mobile/.env.local` (ignoré par Git), puis depuis `apps/mobile` :

```bash
flutter run -d chrome --dart-define-from-file=.env.local
flutter build web --release --dart-define-from-file=.env.local
```

Les workflows GitHub Actions utilisent le secret de dépôt
`CARTO_BASEMAP_API_KEY` pour les builds web CI et production.

Si le chargement d'une tuile CARTO échoue (quota atteint, clé refusée ou service
indisponible), toutes les cartes basculent automatiquement vers OpenStreetMap.
Le basculement dure jusqu'au prochain lancement de l'application pour éviter
de répéter les requêtes refusées. Les calques satellite restent disponibles.

Cette clé de navigateur est visible dans l'application compilée : restreindre
ses domaines dans le tableau de bord CARTO et ne pas la committer. Sans clé
configurée, les builds locaux et CI utilisent automatiquement OpenStreetMap.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
