# Astro Starter Kit: Minimal

## Google Analytics et Search Console (iooeh.com)

Copier `.env.example` vers `.env`, puis renseigner :

```dotenv
PUBLIC_GOOGLE_ANALYTICS_ID=G-XXXXXXXXXX
PUBLIC_GOOGLE_SITE_VERIFICATION=
```

- **Analytics** : dans Google Analytics, créer une propriété et un flux Web pour
  `https://iooeh.com`, puis copier l’ID de mesure `G-…`.
- **Search Console** : ajouter la propriété « Préfixe d’URL » `https://iooeh.com/`,
  choisir « Balise HTML » et copier uniquement la valeur de `content` dans
  `PUBLIC_GOOGLE_SITE_VERIFICATION`. Après déploiement, cliquer sur « Valider ».
  Pour une propriété « Domaine », utiliser la validation TXT DNS et laisser cette
  variable vide.

Pour le déploiement GitHub Actions, ajouter ces mêmes noms dans **Settings →
Secrets and variables → Actions → Variables** du dépôt. Les valeurs sont publiques
et intégrées au HTML au moment du build : toute modification exige un nouveau
build et un déploiement de la landing.

Analytics est désactivé en développement et sur les pages `noindex` (compte et
confirmation d’email). Si l’ID est vide, aucun script Analytics n’est injecté.
Après activation en production, vérifier une visite dans le rapport Temps réel
de Google Analytics.

Le formulaire envoie l’événement GA4 `generate_lead` avec `form_name=launch_waitlist`
uniquement après acceptation de la demande par l’API. Il mesure la demande de
confirmation, pas le clic de confirmation dans l’email. Aucune adresse email n’est
transmise dans cet événement. Dans GA4, marquer `generate_lead` comme événement clé
pour suivre les conversions de la landing.

Le sitemap public est `https://iooeh.com/sitemap.xml` : le soumettre dans Search
Console → Sitemaps. Il liste l’accueil, les conditions et la confidentialité,
et exclut les pages de compte, de confirmation et 404. `robots.txt` indique son URL.
Nginx retourne un statut 404 avec la page dédiée pour les URL inexistantes.

Documentation : [Google tag](https://developers.google.com/tag-platform/gtagjs),
[vérification Search Console](https://support.google.com/webmasters/answer/9008080?hl=fr).

```sh
npm create astro@latest -- --template minimal
```

> 🧑‍🚀 **Seasoned astronaut?** Delete this file. Have fun!

## 🚀 Project Structure

Inside of your Astro project, you'll see the following folders and files:

```text
/
├── public/
├── src/
│   └── pages/
│       └── index.astro
└── package.json
```

Astro looks for `.astro` or `.md` files in the `src/pages/` directory. Each page is exposed as a route based on its file name.

There's nothing special about `src/components/`, but that's where we like to put any Astro/React/Vue/Svelte/Preact components.

Any static assets, like images, can be placed in the `public/` directory.

## 🧞 Commands

All commands are run from the root of the project, from a terminal:

| Command                   | Action                                           |
| :------------------------ | :----------------------------------------------- |
| `npm install`             | Installs dependencies                            |
| `npm run dev`             | Starts local dev server at `localhost:4321`      |
| `npm run build`           | Build your production site to `./dist/`          |
| `npm run preview`         | Preview your build locally, before deploying     |
| `npm run astro ...`       | Run CLI commands like `astro add`, `astro check` |
| `npm run astro -- --help` | Get help using the Astro CLI                     |

## 👀 Want to learn more?

Feel free to check [our documentation](https://docs.astro.build) or jump into our [Discord server](https://astro.build/chat).
