import type { APIRoute } from 'astro';
import { englishPages, pageURL, siteRoot, summary } from '../llms';

// https://llmstxt.org/: what Pullwatch is and where each part of the documentation is.
export const GET: APIRoute = async ({ site }) => {
	const root = siteRoot(site);
	const pages = await englishPages();
	const list = pages
		.map((entry) => `- [${entry.data.title}](${pageURL(entry, root)}): ${entry.data.description ?? ''}`.trimEnd())
		.join('\n');
	const text = `# Pullwatch

> ${summary}

Pullwatch only reads: it never comments, approves, merges or pushes. Tokens stay in the macOS Keychain, and the app has no server, account or analytics of its own. Coding agents can read what Pullwatch knows through its local, read-only MCP server.

- Download: https://github.com/alessandro823/pullwatch/releases/latest
- Source: https://github.com/alessandro823/pullwatch
- Every page below in one file: ${new URL('llms-full.txt', root).href}
- The documentation is also in Dutch (${new URL('nl/', root).href}), German (${new URL('de/', root).href}) and French (${new URL('fr/', root).href}).

## Documentation

${list}
`;
	return new Response(text, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
};
