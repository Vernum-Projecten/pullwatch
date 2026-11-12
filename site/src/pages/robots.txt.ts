import type { APIRoute } from 'astro';
import { siteRoot } from '../llms';

// Every crawler is welcome, search engines and AI assistants alike; the sitemap lists
// every page in every language.
export const GET: APIRoute = ({ site }) => {
	const root = siteRoot(site);
	const text = `User-agent: *
Allow: /

Sitemap: ${new URL('sitemap-index.xml', root).href}
`;
	return new Response(text, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};
