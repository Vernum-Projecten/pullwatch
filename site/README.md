# The Pullwatch website

The landing page and the user documentation, built with
[Astro Starlight](https://starlight.astro.build) and deployed to GitHub Pages
by `.github/workflows/site.yml`. The address and the custom domain are in
[docs/website.md](../docs/website.md).

## Run it

You need the Node version in `.nvmrc` (with nvm: `nvm use`).

```sh
cd site
npm ci                 # the exact versions of package-lock.json
npm run dev            # http://localhost:4321/pullwatch/, reloads on every change
```

Astro's telemetry is off in CI; turn it off on your Mac too with
`npx astro telemetry disable` or `ASTRO_TELEMETRY_DISABLED=1`.

## Build and check it

```sh
npm run build          # dist/, with the Pagefind search index; fails on a broken Markdown link
npm run check-links    # follows every internal href, src and srcset in dist/
npm run preview        # serves dist/ as GitHub Pages would, search included
```

`npm run build` builds for the project page,
`https://alessandro823.github.io/pullwatch/` (base `/pullwatch/`). With
`PAGES_DOMAIN=pullwatch.net npm run build` it builds for
`https://pullwatch.net/` (base `/`); run `check-links` with the same variable.
CI builds and checks both.

## Add a page

1. Add a Markdown file under `src/content/docs/`, such as
   `src/content/docs/using/history.md`; its path is its address
   (`/using/history/`). Use `.mdx` when the page shows a screenshot.
2. Give it a `title` and a one-sentence `description` in the front matter.
3. Add it to the `sidebar` in `astro.config.mjs`, by its `slug`
   (`using/history`).
4. Link to other pages from the site root: `[Notifications](/using/notifications/)`.
   `src/plugins/base-links.mjs` adds `/pullwatch` on the project page, and the
   links validator fails the build when the page does not exist.
   In a component, build a link with `import.meta.env.BASE_URL`.

Write as the other pages do: English, short sentences, the names the app
shows (**Settings**, **Sources**), and only what the code does. No em dashes,
no middle dots.

## Screenshots

`src/assets/screenshots/light/` and `dark/` hold the same file names. Show
one with the `Screenshot` component, which picks the one for the reader's
theme and lets Astro make AVIF and WebP in a few sizes:

```mdx
import Screenshot from '../../../components/Screenshot.astro';

<Screenshot name="repo-check" alt="What the screenshot shows, in words." />
```

Every screenshot comes from the app's own camera tour with fake data, never
from a real account. Build a debug app and run it from the build folder
(not `/Applications`), with a data folder that holds a `config.json` with one
GitHub account:

```sh
Pullwatch.app/Contents/MacOS/Pullwatch -PullwatchDataDirectory <data> \
  -PullwatchFakeGitHub YES -PullwatchFakeData YES -PullwatchFakeGitHubInstalled YES \
  -PullwatchSnapshotTour YES -PullwatchSnapshotDirectory <shots> \
  -PullwatchSnapshotLight YES -AppleLanguages '(en)'
```

Run it again with `-PullwatchSnapshotDark YES -AppleInterfaceStyle Dark` for
the dark set, and with `-PullwatchMenuPreview YES` and
`-PullwatchNotificationPreview YES -PullwatchSkipNotificationRequest YES` (on
the same data folder, so the menu has content) for the menu panel and the
notifications. The main window draws its sidebar empty, so crop the shots
to the content to the right of it, at 2x.

## Languages

English is the root locale (no `/en/` in the address). A language is added
in `astro.config.mjs` under `locales` with its pages in
`src/content/docs/<lang>/`, without moving the English ones.
