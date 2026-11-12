import { getCollection, type CollectionEntry } from 'astro:content';

// The English documentation as plain Markdown for AI assistants (llms.txt and
// llms-full.txt, https://llmstxt.org/), in the order of the sidebar.

const order = [
	'getting-started/install',
	'getting-started/accounts',
	'getting-started/permissions',
	'using/menu',
	'using/pull-requests-and-tags',
	'using/branches',
	'using/repositories',
	'using/dependencies',
	'using/packages',
	'using/security',
	'using/notifications',
	'using/statistics',
	'using/keyboard-shortcuts',
	'privacy',
	'acknowledgements',
	'agents',
	'faq',
	'troubleshooting',
	'maintainers',
];

export const summary =
	'Pullwatch is a free, open-source macOS menu bar app (Apache-2.0, macOS 26.6 or later, Apple silicon and Intel) that notifies you of new pull requests, tags, releases and branch pushes on GitHub (github.com, GitHub Enterprise Server, GHE.com), Azure DevOps, GitLab, Bitbucket Cloud, Codeberg, Forgejo and Gitea, keeps a searchable history, and checks your repositories once a day for outdated runtimes, packages and known vulnerabilities.';

/** The site's root URL, base included, ending in a slash. */
export function siteRoot(site: URL | undefined): URL {
	return new URL(import.meta.env.BASE_URL.replace(/\/?$/, '/'), site);
}

/** The English pages that are in the sidebar, in its order. */
export async function englishPages() {
	const pages = await getCollection('docs', (entry) => order.includes(entry.id));
	return pages.sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id));
}

export function pageURL(entry: CollectionEntry<'docs'>, root: URL): string {
	return new URL(`${entry.id}/`, root).href;
}

/** A page's Markdown without MDX imports and components, with links made absolute. */
export function pageMarkdown(entry: CollectionEntry<'docs'>, root: URL): string {
	return (entry.body ?? '')
		.replace(/^import .*$\n?/gm, '')
		.replace(/<Screenshot\b[\s\S]*?\/>\n?/g, '')
		.replace(/\]\(\/(?!\/)/g, `](${root.href}`)
		.replace(/\n{3,}/g, '\n\n')
		.trim();
}
