import { defineCollection } from 'astro:content';
import { z } from 'astro/zod';
import { docsLoader, i18nLoader } from '@astrojs/starlight/loaders';
import { docsSchema, i18nSchema } from '@astrojs/starlight/schema';

export const collections = {
	docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
	// src/content/i18n/<lang>.json: the landing page's own text per language (the pw.* keys,
	// read with Astro.locals.t) and the few Starlight strings its Dutch lacks.
	i18n: defineCollection({
		loader: i18nLoader(),
		schema: i18nSchema({
			extend: z.object({
				'pw.privacy.kicker': z.string(),
				'pw.privacy.title': z.string(),
				'pw.privacy.keychain.title': z.string(),
				'pw.privacy.keychain.text': z.string(),
				'pw.privacy.server.title': z.string(),
				'pw.privacy.server.text': z.string(),
				'pw.privacy.sources.title': z.string(),
				'pw.privacy.sources.text': z.string(),
				'pw.privacy.more': z.string(),
				'pw.get.title': z.string(),
				'pw.get.text': z.string(),
				'pw.get.download': z.string(),
				'pw.get.guide': z.string(),
			}).partial(),
		}),
	}),
};
