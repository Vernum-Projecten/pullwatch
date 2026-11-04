// A Sätteri hast plugin: puts Astro's `base` in front of every root-relative link in the
// Markdown pages, so `/using/menu/` becomes `/pullwatch/using/menu/` on the project page and
// stays `/using/menu/` on a custom domain. It runs before the links validator, which then
// checks the address a reader actually gets.

/** @param {string} base */
export function baseLinks(base) {
	const prefix = base.replace(/\/+$/, '');
	return {
		name: 'pullwatch-base-links',
		element: {
			filter: ['a'],
			/**
			 * @param {import('hast').Element} node
			 * @param {{ setProperty(node: unknown, key: string, value: unknown): void }} ctx
			 */
			visit(node, ctx) {
				const href = node.properties?.href;
				if (!prefix || typeof href !== 'string') return;
				if (!href.startsWith('/') || href.startsWith('//')) return;
				if (href === prefix || href.startsWith(`${prefix}/`)) return;
				ctx.setProperty(node, 'href', `${prefix}${href}`);
			},
		},
	};
}
