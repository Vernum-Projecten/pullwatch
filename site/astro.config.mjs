// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { satteri } from '@astrojs/markdown-satteri';
import starlightLinksValidator from 'starlight-links-validator';
import { baseLinks } from './src/plugins/base-links.mjs';

// The address is one setting: the repository variable PAGES_DOMAIN (docs/website.md).
// Set (for example pullwatch.net), the site lives at https://<domain>/; empty, at the
// project page https://alessandro823.github.io/pullwatch/.
const domain = process.env.PAGES_DOMAIN?.trim();
const site = domain ? `https://${domain}` : 'https://alessandro823.github.io';
const base = domain ? '/' : '/pullwatch';
const baseSlash = base.endsWith('/') ? base : `${base}/`;

export const repository = 'https://github.com/alessandro823/pullwatch';

export default defineConfig({
	site,
	base,
	trailingSlash: 'always',
	markdown: {
		// Links in the Markdown pages are written from the site root (/using/menu/) and get
		// the base here, so they work at both addresses.
		processor: satteri({ hastPlugins: [baseLinks(base)] }),
	},
	integrations: [
		starlight({
			title: 'Pullwatch',
			description:
				'A macOS menu bar app that tells you about new pull requests, tags and releases on GitHub, Azure DevOps and GitLab, and checks your repositories for outdated runtimes, packages and known vulnerabilities.',
			logo: { src: './src/assets/pullwatch-logo.png', alt: '' },
			favicon: '/favicon.png',
			head: [
				{ tag: 'link', attrs: { rel: 'apple-touch-icon', href: `${baseSlash}apple-touch-icon.png` } },
				{ tag: 'meta', attrs: { property: 'og:image', content: `${site}${baseSlash}og.png` } },
				{ tag: 'meta', attrs: { property: 'og:image:width', content: '1200' } },
				{ tag: 'meta', attrs: { property: 'og:image:height', content: '630' } },
				{ tag: 'meta', attrs: { property: 'og:image:alt', content: 'The Pullwatch app icon' } },
			],
			// English is the root locale (no /en/ in the address) and the fallback. Dutch, German
			// and French live in src/content/docs/<locale>/ under the same slugs, so the language
			// picker and the hreflang links map every page to its translation.
			defaultLocale: 'root',
			locales: {
				root: { label: 'English', lang: 'en' },
				nl: { label: 'Nederlands', lang: 'nl' },
				de: { label: 'Deutsch', lang: 'de' },
				fr: { label: 'Français', lang: 'fr' },
			},
			social: [{ icon: 'github', label: 'Pullwatch on GitHub', href: repository }],
			editLink: { baseUrl: `${repository}/edit/main/site/` },
			customCss: ['./src/styles/custom.css'],
			credits: false,
			sidebar: [
				{
					label: 'Getting started',
					translations: { nl: 'Aan de slag', de: 'Erste Schritte', fr: 'Prise en main' },
					items: [
						{ slug: 'getting-started/install' },
						{ slug: 'getting-started/accounts' },
						{ slug: 'getting-started/permissions' },
					],
				},
				{
					label: 'Using Pullwatch',
					translations: { nl: 'Pullwatch gebruiken', de: 'Pullwatch verwenden', fr: 'Utiliser Pullwatch' },
					items: [
						{ slug: 'using/menu' },
						{ slug: 'using/pull-requests-and-tags' },
						{ slug: 'using/repositories' },
						{ slug: 'using/dependencies' },
						{ slug: 'using/security' },
						{ slug: 'using/notifications' },
						{ slug: 'using/statistics' },
						{ slug: 'using/keyboard-shortcuts' },
					],
				},
				{
					label: 'Reference',
					translations: { nl: 'Naslag', de: 'Referenz', fr: 'Référence' },
					items: [
						{ slug: 'privacy' },
						{ slug: 'agents' },
						{ slug: 'faq' },
						{ slug: 'troubleshooting' },
						{ slug: 'maintainers' },
					],
				},
			],
			// Every page is translated: a link to a fallback page or to a page in another
			// language fails the build.
			plugins: [starlightLinksValidator({ errorOnInconsistentLocale: true })],
		}),
	],
});
