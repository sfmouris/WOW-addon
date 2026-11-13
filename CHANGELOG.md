# Changelog

Alle fasen uit spec 11 zijn gebouwd en getest tegen de nagebootste client. In-game controle staat nog open (zie `docs/INGAME-TESTPLAN.md`); pas daarna gaat de versie naar 1.0.0.

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
