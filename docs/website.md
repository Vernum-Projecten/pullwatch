# The website

The website (a landing page and the user documentation) lives in `site/`, an
Astro Starlight project; `site/README.md` says how to run it, build it and
add a page. `.github/workflows/site.yml` builds it on every pull request that
touches it, and deploys it to GitHub Pages on a push to `main` in
`alessandro823/pullwatch`. The fork builds it and never deploys.

Where the site lives is one setting, the repository variable `PAGES_DOMAIN`:

| `PAGES_DOMAIN` | Address | Base path |
|---|---|---|
| empty or missing | `https://alessandro823.github.io/pullwatch/` | `/pullwatch/` |
| `pullwatch.net` | `https://pullwatch.net/` | `/` |

The canonical links, the sitemap and the preview image for social media
follow it, so moving to the domain needs no code change. The steps below are
for the maintainer (Alessandro, `alessandro823`), once. The domain is
`pullwatch.net`; its DNS is at the registrar's name servers (`ns.zxcs.nl`,
`ns.zxcs.be`, `ns.zxcs.eu`).

## 1. Turn on GitHub Pages

The repository, **Settings**, **Pages**, **Build and deployment**, **Source**:
**GitHub Actions**. Nothing else on that page yet.

Then run the workflow once: **Actions**, **Website**, **Run workflow** on
`main` (or `gh workflow run site.yml --repo alessandro823/pullwatch --ref main`).

Check: the run's **deploy to GitHub Pages** job is green and links to
`https://alessandro823.github.io/pullwatch/`, which shows the landing page.
`gh api repos/alessandro823/pullwatch/pages --jq .build_type` prints
`workflow`.

## 2. Verify the domain for your account

Do this before the domain goes into the repository: a verified domain can
only be used by your account, so nobody else can point a GitHub Pages site at
`pullwatch.net` or a subdomain of it while the DNS already points at GitHub.

Your profile picture, **Settings**, **Pages** (under Code, planning, and
automation), **Verified domains**, **Add a domain**: `pullwatch.net`. GitHub
shows a TXT record. At the registrar, in the zone of `pullwatch.net`, add:

| Name | Type | Content | TTL |
|---|---|---|---|
| `_github-pages-challenge-alessandro823` | TXT | the code from GitHub, Settings, Pages, Verified domains | the registrar's default |

The full name is `_github-pages-challenge-alessandro823.pullwatch.net`. The
part after `challenge-` is the account that verifies the domain, here
`alessandro823`. An earlier draft of these steps named the record
`_github-pages-challenge-pullwatch`; that is wrong, GitHub would never find it.

Check, then click **Verify** on the same page:

```sh
dig +short TXT _github-pages-challenge-alessandro823.pullwatch.net
```

prints the code in quotes. A new record can take a while to show; GitHub
keeps the domain pending until it does. Keep the TXT record afterwards:
GitHub checks it again from time to time.

## 3. Point the domain at GitHub Pages

At the registrar, add these records to the zone of `pullwatch.net`, one
row per record. With them, the zone holds this full set (the TXT record is
the one from step 2):

| Name | Type | Content | TTL |
|---|---|---|---|
| `@` | A | `185.199.108.153` | the registrar's default |
| `@` | A | `185.199.109.153` | the registrar's default |
| `@` | A | `185.199.110.153` | the registrar's default |
| `@` | A | `185.199.111.153` | the registrar's default |
| `@` | AAAA | `2606:50c0:8000::153` | the registrar's default |
| `@` | AAAA | `2606:50c0:8001::153` | the registrar's default |
| `@` | AAAA | `2606:50c0:8002::153` | the registrar's default |
| `@` | AAAA | `2606:50c0:8003::153` | the registrar's default |
| `www` | CNAME | `alessandro823.github.io.` | the registrar's default |
| `_github-pages-challenge-alessandro823` | TXT | the code from GitHub, Settings, Pages, Verified domains | the registrar's default |

`@` is the domain itself, `pullwatch.net`; `www` is `www.pullwatch.net`.
The registrar's default TTL is fine (10 minutes works well: a mistake is
corrected quickly). Leave the existing NS records (`ns.zxcs.nl`,
`ns.zxcs.be`, `ns.zxcs.eu`) as they are.

Remove any other A, AAAA or CNAME record for `@` and `www` (a parking page
of the registrar, for example). The apex cannot be a CNAME, which is why it
gets the eight addresses. If the zone has CAA records, add one that lets
GitHub's certificate authority issue: `@ CAA 0 issue "letsencrypt.org"`.

Check:

```sh
dig +short A pullwatch.net
dig +short AAAA pullwatch.net
dig +short CNAME www.pullwatch.net
```

print, in any order:

```text
185.199.108.153
185.199.109.153
185.199.110.153
185.199.111.153
```

```text
2606:50c0:8000::153
2606:50c0:8001::153
2606:50c0:8002::153
2606:50c0:8003::153
```

```text
alessandro823.github.io.
```

## 4. Switch the site to the domain

Do these three right after each other: until the workflow has run again, the
site is built for the other address and its links point to the wrong place.

1. The repository, **Settings**, **Secrets and variables**, **Actions**,
   **Variables**, **New repository variable**: name `PAGES_DOMAIN`, value
   `pullwatch.net` (no `https://`, no slash). Or
   `gh variable set PAGES_DOMAIN --body pullwatch.net --repo alessandro823/pullwatch`.
2. **Settings**, **Pages**, **Custom domain**: `pullwatch.net`, **Save**.
   GitHub runs a DNS check; it must say the DNS check succeeded. With the
   source on GitHub Actions no `CNAME` file is needed: this setting is the
   domain.
3. Run the workflow again (**Actions**, **Website**, **Run workflow**, or
   `gh workflow run site.yml --repo alessandro823/pullwatch --ref main`).

With `pullwatch.net` as the custom domain and the `www` record above, GitHub
redirects `www.pullwatch.net` to `pullwatch.net`, and the old address
`alessandro823.github.io/pullwatch/` to the new one.

Check:

```sh
gh variable list --repo alessandro823/pullwatch                 # PAGES_DOMAIN  pullwatch.net
gh api repos/alessandro823/pullwatch/pages --jq .cname          # pullwatch.net
curl -sI http://pullwatch.net | head -1                         # a response from GitHub
curl -s https://pullwatch.net/ | grep -o '<link rel="canonical"[^>]*>'
```

The last line prints `https://pullwatch.net/` as the canonical address once
the certificate is there (step 5); before that, use `http://`.

## 5. Enforce HTTPS

GitHub requests a certificate for `pullwatch.net` and `www.pullwatch.net` on
its own once the DNS check succeeds; that takes from minutes up to a day.
While it is not ready, **Enforce HTTPS** on the Pages settings page is grey
and says the certificate is not yet available. When it can be ticked, tick
**Enforce HTTPS**.

Check:

```sh
gh api repos/alessandro823/pullwatch/pages --jq .https_enforced   # true
curl -sI http://pullwatch.net | grep -i '^location'               # https://pullwatch.net/
curl -sI https://www.pullwatch.net | grep -i '^location'          # https://pullwatch.net/
```

and `https://pullwatch.net/` opens in a browser with a valid certificate.

## 6. Link to it

Once the site answers at `https://pullwatch.net/`:

- the repository's website field:
  `gh repo edit alessandro823/pullwatch --homepage https://pullwatch.net`;
- the links to `https://pullwatch.net` at the top of `README.md` (already
  there; they work once the domain answers);
- the link in the app's About window, a separate change.

## Back to the project page

Delete the `PAGES_DOMAIN` variable, remove the custom domain under
**Settings**, **Pages**, and run the workflow again. The site is then at
`https://alessandro823.github.io/pullwatch/` again.

## Preview on a fork

A fork can publish the site at its own project page, to look at a change before it goes upstream:

1. In the fork, **Settings, Pages, Source: GitHub Actions**.
2. Set the fork's repository variable `PAGES_DEPLOY` to `true`:
   `gh variable set PAGES_DEPLOY --body true --repo <owner>/pullwatch`
3. Run the **Website** workflow on `main` (Actions, Website, Run workflow), or push a change under `site/`.

The site then lives at `https://<owner>.github.io/pullwatch/`: the build takes its address from the repository it runs in, so every link and image points at the fork's page. Leave `PAGES_DOMAIN` empty in a fork. Without `PAGES_DEPLOY`, a fork only builds and checks the site, as before. `alessandro823/pullwatch` deploys without the variable.

## When something is off

- **The page loads without styles, or links lead to a 404**: the site was
  built for the other address. Check `PAGES_DOMAIN` and run the workflow
  again.
- **"Domain's DNS record could not be retrieved" or "improperly configured"**:
  check step 3 with `dig`; `gh api repos/alessandro823/pullwatch/pages/health`
  shows what GitHub sees.
- **The fork's Website workflow has no deploy job**: on purpose. Only
  `alessandro823/pullwatch` deploys.
