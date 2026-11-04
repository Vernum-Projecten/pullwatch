#!/usr/bin/env python3
"""check-terms.py: for each locale, every **bold** and `code` name on the site's pages,
checked against that language's values in the String Catalogs. A name the catalogs do not hold
must be on the allowlist below (a macOS name, a service, a web UI of GitHub/GitLab/Azure, the
fake data) or look like code (a path, command, file, key); anything else is reported."""
import glob, json, re, sys, collections
from pathlib import Path

repo = str(Path(__file__).resolve().parents[2])
cats = [f'{repo}/Pullwatch/Pullwatch/Localizable.xcstrings'] + sorted(glob.glob(f'{repo}/PullwatchKit/Sources/*/Localizable.xcstrings'))

def values(v, lang):
    loc = v.get('localizations', {}).get(lang, {})
    out = []
    if 'stringUnit' in loc: out.append(loc['stringUnit']['value'])
    for kind in loc.get('variations', {}).values():
        for x in kind.values():
            if 'stringUnit' in x: out.append(x['stringUnit']['value'])
    return out

def norm(s):
    s = s.replace('’', "'").replace(' ', ' ').strip()
    s = re.sub(r'(…|\.\.\.|[.:])$', '', s).strip()
    return s.casefold()

catalog = collections.defaultdict(set)
for f in cats:
    for key, v in json.load(open(f))['strings'].items():
        for lang in ('en', 'de', 'fr'):
            for x in values(v, lang): catalog[lang].add(norm(x))
        for x in values(v, 'nl') or [key]: catalog['nl'].add(norm(x))
        catalog['nl'].add(norm(key))

# Names outside the app: services and their web UIs, macOS, the fake data, keys on a keyboard.
common = {'pullwatch', 'github', 'gitlab', 'azure devops', 'github enterprise', 'osv.dev', 'endoflife.date',
          'github advisory database', 'azure devops advanced security', 'swift.org', 'fine-grained token',
          'classic token', '+', 'eol', 'read_api', 'developer id', 'install pullwatch', 'finder', 'terminal',
          'spotlight', 'launchpad', 'dock',
          # Bitbucket: de dienst, de keuze in het menu +, de knop op Atlassians tokenpagina, het voorbeeld.
          'bitbucket', 'bitbucket cloud', 'create api token with scopes', 'acme, acme-labs'}
# macOS's own names in each language (Finder, the Keychain prompt, the Help menu), not Pullwatch's.
macos = {
    'en': {'applications', 'always allow', 'help'},
    'nl': {'apps', 'sta altijd toe', 'help'},
    'de': {'programme', 'immer erlauben', 'hilfe'},
    'fr': {'applications', 'toujours autoriser', 'aide'},
}
# Bold used as the lead-in of a list item or a step: emphasis in the prose, not a name on screen.
emphasis = {
    'en': {'runtimes', 'tokens', 'click a row', 'right-click a row', 'the menu bar icon', 'where pullwatch lives',
           'settings, history and check results', 'a self-managed server', 'signed in with gh, az or glab',
           'github cli'},
    'nl': {'runtimes', 'klik op een rij', 'klik met de rechtermuisknop op een rij', 'het icoon in de menubalk',
           'waar pullwatch staat', 'instellingen, geschiedenis en uitkomsten van checks', 'een eigen server',
           'ingelogd met gh, az of glab', 'github cli'},
    'de': {'runtimes', 'klicke auf eine zeile', 'klicke mit der rechten maustaste auf eine zeile',
           'das symbol in der menüleiste', 'wo pullwatch zu finden ist', 'einstellungen, verlauf und prüfergebnisse',
           'ein selbst verwalteter server', 'angemeldet mit gh, az oder glab', 'github cli'},
    'fr': {'les runtimes', 'les jetons', 'les paquets', 'cliquez sur une ligne', 'cliquez avec le bouton droit sur une ligne',
           "l'icône de la barre des menus", "les réglages, l'historique et les résultats des vérifications",
           'un serveur autogéré', 'connecté avec gh, az ou glab', 'github cli'},
}
looks_like_code = re.compile(r'[/_$=<>{}\[\]~:]|^-|\.(json|md|swift|sh|dmg|zip|yml|lock|toml|xml|plist|txt|log|app)\b|^[a-z0-9.@-]+( |$)|^\S+$|^⌘|^⇧|^⌥')

pages = {'en': [p for p in glob.glob(f'{repo}/site/src/content/docs/**/*.md*', recursive=True)
                if not re.search(r'/docs/(nl|de|fr)/', p)]}
for lang in ('nl', 'de', 'fr'):
    pages[lang] = glob.glob(f'{repo}/site/src/content/docs/{lang}/**/*.md*', recursive=True)

bold = re.compile(r'\*\*([^*]+?)\*\*')
code = re.compile(r'(?<!`)`([^`\n]+)`(?!`)')
total_bad = 0
for lang, files in pages.items():
    found, outside, system, emph, codeish, bad = set(), set(), set(), set(), set(), collections.defaultdict(set)
    def in_catalog(n):
        # "Checks: Needs permission" is two texts side by side in the app: check each part.
        return n in catalog[lang] or (re.search(r' ?: ', n) and all(norm(x) in catalog[lang] for x in re.split(r' ?: ', n)))
    for p in files:
        text = re.sub(r'```.*?```', '', open(p).read(), flags=re.S)
        rel = p.split('/docs/')[1]
        terms = [(t, 'bold') for t in bold.findall(text)] + [(t, 'code') for t in code.findall(text)]
        for t, kind in terms:
            n = norm(re.sub(r'`', '', t))
            if kind == 'code' and n not in catalog[lang] and looks_like_code.search(t): codeish.add(t)
            elif in_catalog(n): found.add(t)
            elif n in common: outside.add(t)
            elif n in macos[lang]: system.add(t)
            elif n in emphasis[lang]: emph.add(t)
            else: bad[t].add(rel)
    print(f'## {lang}: {len(files)} pages. Bold or code names: {len(found)} found in the catalogs, '
          f'{len(outside)} services and outside names, {len(system)} macOS names, {len(emph)} emphasis lead-ins, '
          f'{len(codeish)} code (commands, paths, keys), {len(bad)} NOT FOUND')
    print('   in the catalogs: ' + ' | '.join(sorted(found)))
    print('   services and outside names: ' + ' | '.join(sorted(outside)))
    print('   macOS names: ' + ' | '.join(sorted(system)))
    print('   emphasis, not a UI name: ' + ' | '.join(sorted(emph)))
    for t, where in sorted(bad.items()):
        print(f'   NOT FOUND: {t!r} in {", ".join(sorted(where))}')
    total_bad += len(bad)
sys.exit(1 if total_bad else 0)
