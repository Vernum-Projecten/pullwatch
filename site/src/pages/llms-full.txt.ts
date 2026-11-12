import type { APIRoute } from 'astro';
import { englishPages, pageMarkdown, pageURL, siteRoot, summary } from '../llms';

// The whole English documentation in one Markdown file, for AI assistants.
export const GET: APIRoute = async ({ site }) => {
	const root = siteRoot(site);
	const pages = await englishPages();
	const sections = pages.map(
		(entry) => `# ${entry.data.title}\n\nSource: ${pageURL(entry, root)}\n\n${pageMarkdown(entry, root)}`,
	);
	const text = `# Pullwatch\n\n> ${summary}\n\n${sections.join('\n\n')}\n`;
	return new Response(text, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};
