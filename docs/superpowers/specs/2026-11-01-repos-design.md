# Onderdeel Repo's — ontwerp

Datum: 2026-11-01

## Waarom

Informatie over één repo staat verspreid over PR's, Tags, Repo-controle en Versies. Alessandro wil
het vanuit de repo benaderen: één plek per repo met PR's, controle en packages, en volgen/meldingen
regelen waar je naar de repo kijkt. Statistieken (grafieken) volgen later als apart project; daarvoor
begint Pullwatch nu al momentopnames van elke versiecheck te bewaren.

## Wat

- **Repo-controle wordt Repo's** in de zijbalk, uitklapbaar per project (Azure DevOps) of eigenaar
  (GitHub), zoals PR's en Tags.
- **Lijst** (mockup `repos.html`, links): per repo een gezondheidsstip, korte labels (aantal CVE's,
  EOL/achter-runtime, aantal packages met nieuwe versie) en rechts open PR's en laatste tag. Slechtste
  eerst, daarna op naam. Zoekveld, "Alles checken".
- **Eén repo** (mockup rechts): kop met naam, account, laatste tag, checktijd; knoppen "Open in
  browser", "↻ Check", en volgen/melden (PR's, Tags, Completed, 🔔 per soort). Daaronder blokken
  **Pull requests** (open eerst, dan recent), **Controle** (runtimes + CVE's met "ook in release",
  zoals nu in Repo-controle) en **Packages met nieuwe versie**. Terug naar de lijst met "‹ project".
- Gezondheid: rood = CVE's of EOL; oranje = runtime achter of packages met nieuwe versie; groen =
  actueel; grijs = nog niet gecheckt of fout.
- Badge bij Repo's: aantal rode repo's.
- Welke repo's: die uit de laatste versiecheck plus de repo's die in een account expliciet gevolgd
  worden (ook als ze nog niet gecheckt zijn).
- Sprongen die nu naar Repo-controle met zoekfilter gaan (vanuit PR's/Tags, vanuit Versies) openen
  voortaan de repo-pagina.
- Volgen/melden op de repo-pagina slaat direct op (geen opslaan-knop), via `Account.setWatch`.

## Momentopnames

Na elke volledige versiecheck een compacte momentopname in `version-history.json`: tijdstip en per
repo de runtimeversies met status, het aantal CVE's per ernst en het aantal packages met nieuwe
versie. Hooguit 730 opnames (≈ 2 jaar dagelijks); de oudste vallen eraf. Nog geen UI.

## Niet

- Geen statistieken/grafieken (volgend project).
- Versies (per package) blijft zoals het is.
- Geen favorieten.
