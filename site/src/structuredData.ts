import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { defineRouteMiddleware } from '@astrojs/starlight/route-data';

// Structured data (schema.org as JSON-LD) so search engines and AI assistants can read the
// facts without guessing: the app on each landing page, the questions and answers on each
// FAQ page. Both come from the page itself; the version from Pullwatch/App.xcconfig.

const repository = 'https://github.com/alessandro823/pullwatch';

/** MARKETING_VERSION from the app's settings, or nothing when the file is not there. */
function appVersion(): string | undefined {
	try {
		const config = readFileSync(resolve(process.cwd(), '../Pullwatch/App.xcconfig'), 'utf8');
		return config.match(/^MARKETING_VERSION = (\S+)$/m)?.[1];
	} catch {
		return undefined;
	}
}

const version = appVersion();

/** Markdown of one answer as plain text: links keep their text, emphasis and code lose their marks. */
function plainText(markdown: string): string {
	return markdown
		.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
		.replace(/(\*\*|__|`)/g, '')
		.replace(/\s+/g, ' ')
		.trim();
}

/** Each `## Question` with the paragraphs under it. */
function questions(body: string) {
	return body
		.split(/^## /m)
		.slice(1)
		.map((section) => {
			const [question, ...answer] = section.split('\n');
			return {
				'@type': 'Question',
				name: question.trim(),
				acceptedAnswer: { '@type': 'Answer', text: plainText(answer.join('\n')) },
			};
		})
		.filter((q) => q.acceptedAnswer.text.length > 0);
}

function jsonLd(data: object) {
	// `<` escaped, so no text can close the script element.
	return {
		tag: 'script' as const,
		attrs: { type: 'application/ld+json' },
		content: JSON.stringify(data).replace(/</g, '\\u003c'),
	};
}

export const onRequest = defineRouteMiddleware((context) => {
	const route = context.locals.starlightRoute;
	const slug = route.id.replace(/^(nl|de|fr)\/?/, '');
	const page = new URL(context.url.pathname, context.site).href;

	if (slug === '' || slug === 'index') {
		route.head.push(
			jsonLd({
				'@context': 'https://schema.org',
				'@type': 'SoftwareApplication',
				name: 'Pullwatch',
				url: page,
				description: route.entry.data.description,
				inLanguage: route.lang,
				applicationCategory: 'DeveloperApplication',
				operatingSystem: 'macOS 26.6 or later',
				...(version ? { softwareVersion: version } : {}),
				downloadUrl: `${repository}/releases/latest`,
				installUrl: `${repository}/releases/latest`,
				license: 'https://www.apache.org/licenses/LICENSE-2.0',
				isAccessibleForFree: true,
				offers: { '@type': 'Offer', price: '0', priceCurrency: 'EUR' },
				author: { '@type': 'Person', name: 'Alessandro Torrisi' },
				sameAs: [repository],
				image: new URL('og.png', new URL(import.meta.env.BASE_URL, context.site)).href,
			}),
		);
	}

	if (slug === 'faq' && route.entry.body) {
		route.head.push(
			jsonLd({
				'@context': 'https://schema.org',
				'@type': 'FAQPage',
				url: page,
				inLanguage: route.lang,
				mainEntity: questions(route.entry.body),
			}),
		);
	}
});
