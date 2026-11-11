# In-game te controleren

Alles hieronder is gebouwd en getest tegen een nagebootste client (`tests/`), niet in WoW Forever zelf. De API-namen en signaturen zijn gecontroleerd tegen de geëxporteerde interfacecode van **1.60.1 build 70888** (Gethe/wow-ui-source, branch `forever`). Wat een functie in de echte wereld teruggeeft, kan alleen in het spel blijken.

Zet vooraf aan: BugSack en BugGrabber, `/console scriptErrors 1`, `/console taintLog 1`. Na de sessie: `Logs/taint.log` bekijken (in de `_forever_`-map).

## 1. Basis (fase 0 en 1)
- [ ] `/run print(select(4, GetBuildInfo()))` geeft 16001. Zo niet: TOC aanpassen.
- [ ] Addon staat in de addonlijst zonder "verouderd"; BugSack leeg na inloggen op een schoon profiel.
- [ ] `/qk version` toont versie, TOC 16001, client 16001 en de geladen bruggen.
- [ ] `/qk dump` klopt met het questlog voor minstens 10 quests in 2 zones (titel, level, doelen, XP).
- [ ] Een questmob doden: de regel in de tracker flitst één keer en de teller loopt op.
- [ ] Inloggen met een vol log: geen fouten, titels die eerst ontbreken komen vanzelf.

## 2. Tracker (fase 2)
- [ ] Venster slepen, `/qk lock`, schaal 0,7 tot 1,5 in de instellingen; alles blijft na `/reload`.
- [ ] Groepen: "Klaar om in te leveren" bovenaan, dan de huidige zone, dan andere zones (ingeklapt).
- [ ] Klik, Shift-klik (met open chatregel), rechtsklikmenu: alle items werken.
- [ ] Tooltip toont beschrijving, beloning en de bron van de locatie.
- [ ] `/qk debug` aan, `/qk dump`: "Tracker herbouw" onder 5 ms met 25 quests.
- [ ] In gevecht vervaagt het venster en laat het de muis door; geen herbouw tot na het gevecht.
- [ ] Optie "standaard tracker verbergen": geen taint in `taint.log` na 10 gevechten. **TODO(verify)**

## 3. Auto-quest en pijl (fase 3)
- [ ] NPC met 3 beschikbare en 2 inleverbare quests: alles zonder klik, behalve een beloningskeuze.
- [ ] Shift ingedrukt bij aanspreken: niets gebeurt automatisch.
- [ ] Quest die geld of gewone items kost: wacht op de speler.
- [ ] Quest meer dan 4 levels boven je: niet automatisch.
- [ ] Vol log: melding midden in beeld, geen foutgeluid.
- [ ] Quest met timer: niet automatisch geaccepteerd. **TODO(verify)**: `C_QuestLog.GetTimeAllowed` geeft mogelijk pas data als de quest in het log staat.
- [ ] Optie gossip overslaan: kiest alleen gewone praatopties. **TODO(verify)**: fileID 132053 voor het praaticoon.
- [ ] Klik op een quest: pijl verschijnt binnen 0,5 s en wijst goed; lopen verkleint de afstand tot onder 10 yd, dan vinkje en geluid.
- [ ] Geen fouten in een dungeon, op een boot, op een vlucht, als geest.
- [ ] Meten met `/qk dump` (sectie Locaties): hoeveel quests krijgen een locatie van `client` of `poi`? **TODO(verify)**: `GetNextWaypoint` en `GetQuestsOnMap` (C_QuestLog en C_TaskQuest) kunnen op Forever leeg zijn. Weinig dekking: Leren en Questie vangen dat op.
- [ ] Instelling "Ingebouwde navigatie": supertrack en kaartpunt werken.

## 4. Leren (fase 4)
- [ ] Na 5 quests: oppak- en inleverpunt binnen 5 yards van de NPC (`/qk find titel` toont de plek).
- [ ] Een alt ziet op de kaart de questgevers van die 5 quests (uitroepteken, grijs als het level te laag is).
- [ ] `/qk export alles`, op een tweede account of na het wissen van `QuestKompasDB` `/qk import`: samenvatting klopt, data identiek.
- [ ] In een dungeon wordt niets geleerd.

## 5. Kaart en plan (fase 5)
- [ ] Pins op zonekaart en continentkaart op de juiste plek; weg na inleveren.
- [ ] Kaart openen en sluiten in gevecht: geen "action blocked".
- [ ] Coördinaten van speler en cursor onder de wereldkaart.
- [ ] `/qk way 45.2 67.8` en `/qk way 45 67 Westfall`.
- [ ] 6 quests in één zone: `/qk plan debug` toont een kortere route dan de logvolgorde.

## 6. Comfort (fase 6)
- [ ] Quest met 3 beloningen: muntje op het duurste item (controleer bij een vendor); groene pijl alleen op betere itemlevels; niets automatisch gekozen.
- [ ] Questitem: knop binnen 1 s na accepteren, werkt in en buiten gevecht; geen taint na 10 gevechten.
- [ ] Toets voor questitem 1 via Toetsenbinding (CLICK-binding).
- [ ] `/qk grey`: lijst klopt; "Alles opgeven" vraagt twee keer.
- [ ] Bij 23 van 25 quests één hint met 3 kandidaten.
- [ ] `/qk stats`: XP per uur en quests tot level kloppen ruwweg.

## 7. Samen (fase 7)
- [ ] Met Questie geladen: tooltip toont "Locatie: Questie" voor quests zonder clientdata. Structuur nagekeken tegen Questie v12.6.5 (`Questie_Forever.toc`).
- [ ] Met en zonder Questie en TomTom: geen enkele Lua-fout.
- [ ] TomTom-optie aan: waypoint komt in TomTom.
- [ ] Groep van 2 (module Groep aan): delen, groepsquest-markering, voortgang van de ander in de tooltip. **TODO(verify)**: addonberichten buiten instances.
- [ ] Leatrix Plus of ForeverPlus geladen: één waarschuwing. **TODO(verify)**: exacte mapnamen.
- [ ] Forever Quest Pins geladen: eigen questgever-pins gaan uit. **TODO(verify)**: mapnaam.

## Overige open punten uit de code
- `Compat.GetQuestDescription`: `GetQuestLogQuestText(logIndex)` op Mainline, de Vanilla-UI roept hem zonder argument aan.
- `Compat.GreetingAvailable`: `GetAvailableLevel` staat niet in de export; bij NPC's met alleen een begroetingsvenster ontbreekt dan het questlevel voor de levelgrens.
- `Geo.Bearing`-terugval zonder HereBeDragons gaat uit van (noord, west) uit `GetWorldPosFromMapPos`. Normaal wordt HereBeDragons gebruikt.
- Antwoorden voor spec 14: Alliance of Horde en klasse, gebruik van Questie, TomTom of Leatrix, en of de standaard tracker weg moet.
