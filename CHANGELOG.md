# Changelog

Alle fasen uit spec 11 zijn gebouwd en getest tegen de nagebootste client. In-game controle staat nog open (zie `docs/INGAME-TESTPLAN.md`); pas daarna gaat de versie naar 1.0.0.

## 0.9.0 (2026-11-13): UI-ronde
Alleen uiterlijk en bediening; het gedrag van de modules is niet veranderd. Getest tegen de nagebootste client, in het spel nog te beoordelen (testplan sectie 8).
- Gedeelde stijl (`UI/Style.lua`): donker paneel, titelbalk met accentlijn, icoonknoppen, vlakke knoppen in dialogen; zeven nieuwe iconen.
- Tracker: titelbalk met knoppen voor volgende doel, instellingen, slot en inklappen; groepskoppen met chevron en aantal; voortgangsbalkje per quest; vinkjes en bolletjes bij doelen; flits fadet uit; richtingspijltjes draaien tien keer per seconde mee; scrollen met het muiswiel in plaats van afkappen.
- Navigatiepijl: kleur van groen naar rood naar gelang je kijkrichting, draait per frame, tekst op een paneeltje met de doelnaam in de questkleur, schaal instelbaar.
- Instellingen: hoofdpagina plus subpagina's Tracker, Navigatie, Auto-quest, Kaart en leren; tooltip bij elke optie en per module.
- Minimapknop (klik: tracker, rechtsklik: instellingen, slepen: verplaatsen; uit te zetten).
- Questitembalk: paneel, bijgesneden iconen met kader, sneltoets op knop 1.
- Afwijking van het plan: de questitembalk heeft geen eigen subpagina (één optie); die staat onder Tracker.
- Mac: `tools/mac/Automatisch bijwerken.command` zet een achtergrondtaak (launchd) klaar die de repo bij het inloggen en elke vier uur bijwerkt, met een melding na een update. De updatelogica is getest met proefrepo's; het installeren van de taak zelf is niet op een Mac getest.
- API-export bijgewerkt naar build 70938; alle nieuwe aanroepen daarin nagekeken.

## 0.8.0 (2026-11-11): afwerking
- Instellingenpaneel via de Settings-API met alle opties, per module terugzetten en "Alles terugzetten"; instellingen per character mogelijk.
- Volledige Nederlandse en Engelse teksten (taal instelbaar, standaard Nederlands).
- Keybindings: tracker, volgende doel, doel wissen, questitem 1.
- README, CLAUDE.md, in-game testplan; installatiescript voor macOS, zip-script, check-script.

## 0.7.0: samen
- Questie-brug (nagekeken tegen Questie v12.6.5 voor Forever) met zelftest en stille terugval; TomTom-waypoints.
- Groep: alle quests delen, LFM-regel in het invoerveld, voortgang van groepsleden via addonberichten (standaard uit).

## 0.6.0: comfort
- Beloningshulp: muntje op de duurste keuze, pijl op itemlevel-upgrades, tooltipregels; nooit automatisch tenzij ingesteld.
- Questitembalk met secure knoppen, alleen buiten gevecht opgebouwd.
- Logtools: grijze quests opruimen, hint bij een bijna vol log, notities, zoeken.
- Statistieken: XP per uur, quests tot level, historie van 2000 inleveringen.

## 0.5.0: kaart en plan
- Kaartpins via HereBeDragons-Pins: inleverpunten, hotspots, geleerde questgevers, navigatiedoel; coördinaten onder de wereldkaart.
- Planner: clustering binnen 150 yards, nearest-neighbour-route, weging; nummers in de tracker en knop Volgende.
- `/qk way x y [zone]`.

## 0.4.0: leren
- Zelflerende database: questgever, inleverpunt, voortgangshotspots (samenvoegen binnen 40 yards, maximaal 12), questketens, minimumlevel en factie.
- Export en import (LibSerialize plus LibDeflate) met validatie en samenvatting.
- Navigator-bronlaag 4 (geleerd).

## 0.3.0: auto en pijl
- Auto-accept en auto-inleveren met Shift om over te slaan, bewaker per quest, uitzonderingen voor geld, items, herhaalbaar, level, zwarte lijst en vol log.
- Navigator: eigen pijl met afstand en aankomsttijd, ingebouwde navigatie als optie, bronlagen client-waypoint en kaart-POI.

## 0.2.0: tracker
- Eigen questvenster met sortering, groepering, markeringen, klikgedrag, contextmenu en voettekst.

## 0.1.0: skelet en data
- Core: events met foutisolatie, combat-wachtrij, DB met migraties, debugvenster en profiler.
- QuestData: genormaliseerde snapshot met interne callbacks en `/qk dump`.
