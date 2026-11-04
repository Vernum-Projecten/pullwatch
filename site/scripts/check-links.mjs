// check-links.mjs: after `npm run build`, follows every internal href, src and srcset in
// dist/ and fails when one points outside the site's base or at a file that is not there.
// starlight-links-validator checks the Markdown pages; this also covers the components,
// Starlight's own chrome and the assets, for whichever base the build used.
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const dist = fileURLToPath(new URL('../dist/', import.meta.url));
const domain = process.env.PAGES_DOMAIN?.trim();
const base = domain ? '/' : '/pullwatch/';
const origin = 'https://site.invalid';

const htmlFiles = [];
const walk = (dir) => {
	for (const name of readdirSync(dir)) {
		const path = join(dir, name);
		if (statSync(path).isDirectory()) walk(path);
		else if (name.endsWith('.html')) htmlFiles.push(path);
	}
};
walk(dist);

const attr = /\s(?:href|src|srcset|content)="([^"]*)"/g;
const problems = [];
let checked = 0;

for (const file of htmlFiles) {
	const html = readFileSync(file, 'utf8');
	const rel = relative(dist, file).replaceAll('\\', '/');
	const pagePath = base + rel.replace(/index\.html$/, '').replace(/\.html$/, '/');
	const pageUrl = new URL(pagePath, origin);
	for (const match of html.matchAll(attr)) {
		const raw = match[1].replaceAll('&amp;', '&');
		const isContent = match[0].trimStart().startsWith('content=');
		// srcset holds several "url width" pairs.
		const values = match[0].includes('srcset=') ? raw.split(',').map((part) => part.trim().split(/\s+/)[0]) : [raw];
		for (const value of values) {
			if (!value || value.startsWith('#') || value.startsWith('data:') || value.startsWith('mailto:')) continue;
			if (isContent && !value.startsWith('/')) continue;
			if (/^[a-z][a-z0-9+.-]*:/i.test(value) || value.startsWith('//')) continue;
			const url = new URL(value, pageUrl);
			checked++;
			if (!url.pathname.startsWith(base)) {
				problems.push(`${rel}: ${value} is outside the base ${base}`);
				continue;
			}
			let target = join(dist, decodeURIComponent(url.pathname.slice(base.length)));
			if (url.pathname.endsWith('/')) target = join(target, 'index.html');
			if (!existsSync(target)) problems.push(`${rel}: ${value} does not exist`);
		}
	}
}

if (problems.length > 0) {
	console.error(problems.join('\n'));
	console.error(`\n${problems.length} broken internal link(s) in ${htmlFiles.length} pages (base ${base}).`);
	process.exit(1);
}
console.log(`${checked} internal links in ${htmlFiles.length} pages resolve (base ${base}).`);
