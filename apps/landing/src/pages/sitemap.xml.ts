import type { APIRoute } from 'astro';

// Les liens de compte, de confirmation et la page 404 sont exclus.
export const GET: APIRoute = () => new Response(
  `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://iooeh.com/</loc></url>
  <url><loc>https://iooeh.com/privacy/</loc></url>
  <url><loc>https://iooeh.com/terms/</loc></url>
</urlset>`,
  { headers: { 'Content-Type': 'application/xml; charset=utf-8' } },
);
