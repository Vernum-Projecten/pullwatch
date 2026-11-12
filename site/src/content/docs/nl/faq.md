---
title: Veelgestelde vragen
description: Korte antwoorden op veelgestelde vragen over Pullwatch.
---

## Is Pullwatch gratis?

Ja. Pullwatch is open source onder de [Apache-licentie 2.0](https://github.com/alessandro823/pullwatch/blob/main/LICENSE), en elke release staat op [GitHub](https://github.com/alessandro823/pullwatch/releases).

## Op welke Macs werkt het?

macOS 26.6 of nieuwer, op Apple silicon en op Intel. Het is één universele app.

## Welke diensten ondersteunt het?

GitHub (github.com, GitHub Enterprise Server en GHE.com), Azure DevOps, GitLab (gitlab.com en je eigen server), Bitbucket Cloud (bitbucket.org), en Codeberg, Forgejo en Gitea (codeberg.org, gitea.com en je eigen server). Zie [Je accounts toevoegen](/nl/getting-started/accounts/).

## Kan Pullwatch iets veranderen in mijn repositories?

Nee. Het leest alleen: pull requests, tags, releases, bestanden van de repository voor de check van afhankelijkheden, en beveiligingsmeldingen. Het plaatst nooit een reactie, keurt niets goed, merget niet en pusht niet.

## Stuurt het mijn code ergens naartoe?

Nee. Er gaat geen broncode van je Mac weg, behalve naar je eigen servers, waar hij vandaan kwam. Voor de check van afhankelijkheden gaan namen en versies van packages naar OSV.dev en de package-registers. Elk daarvan kun je uitzetten. Zie [Privacy en bronnen](/nl/privacy/).

## Hoe vaak kijkt het?

Pull requests met de tussentijd die je instelt onder Instellingen, Algemeen. Tags elke 15 minuten. De geschiedenis van bestaande pull requests elke 15 minuten. Afhankelijkheden en kwetsbaarheden eens per dag, wat je kunt uitzetten, en daarnaast als je op **Alles checken** of **Check** klikt.

## Waarom heeft een melding geen geluid?

Tags zonder release, gemergede pull requests en nieuwe versies komen bewust stil binnen, alleen in het Berichtencentrum. Tijdens **Stille uren** maakt niets geluid. Focus en Niet storen van macOS gelden ook.

## Kan ik een repository volgen die niet van mij is?

Ja. Voeg hem toe onder **Andere repositories** in zijn account, of met **Volg een repository…** (⇧⌘N). Een openbare repository op github.com, gitlab.com of bitbucket.org werkt ook als je token hem niet mag lezen.

## Welke talen spreekt Pullwatch?

Engels, Nederlands, Duits en Frans. Het volgt macOS, of je kiest onder Instellingen, Algemeen, **Taal**.

## Hoe werk ik bij?

Pullwatch zoekt eens per dag naar updates en installeert ze voor je. Zie [Updates](/nl/getting-started/install/#updates).

## Hoort Pullwatch bij GitHub, GitLab, Atlassian of Microsoft?

Nee. GitHub is een handelsmerk van GitHub, Inc., GITLAB is een handelsmerk van GitLab Inc., Bitbucket is een handelsmerk van Atlassian, en Azure DevOps is een handelsmerk van de Microsoft-groep.
