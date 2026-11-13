# QuestKompas: questhulp-addon voor World of Warcraft: Forever

Specificatie en bouwplan voor ontwikkeling in Claude Code.
Versie van dit document: 1.0 (10 november 2026). Eigenaar: Scott.

> **Leeswijzer voor Claude Code.** Dit document is de enige bron van waarheid voor scope en ontwerp. Lees eerst hoofdstuk 2 (harde randvoorwaarden) en hoofdstuk 13 (werkregels). Bouw daarna strikt per fase uit hoofdstuk 11. Alles waar **[VERIFIEER]** bij staat is niet in de live client getest en moet je eerst controleren tegen de geëxporteerde Blizzard-interfacecode (zie 12.2) voordat je erop bouwt. Verzin geen API's: bestaat een functie niet in de export, zoek dan het alternatief op of meld het.

---

## 1. Doel en scope

### 1.1 Wat de addon doet
QuestKompas helpt bij questen in WoW Forever: weten wat je moet doen, waar je heen moet, in welke volgorde, en zo min mogelijk klikken bij NPC's. Het is een persoonlijke addon (niet bedoeld voor CurseForge in versie 1), dus eenvoud en betrouwbaarheid gaan boven configureerbaarheid.

### 1.2 Kernbelofte
1. Eén compact questvenster dat beter is dan de standaard tracker: gesorteerd op afstand, met level, XP en status.
2. Een pijl en afstand naar het eerstvolgende logische doel.
3. Automatisch accepteren en inleveren van quests (instelbaar, met veiligheidsregels).
4. Een zelflerende database: de addon onthoudt waar jij quests hebt opgepakt, ingeleverd en waar je voortgang boekte, zodat alts en vrienden daar later van profiteren.
5. Slimme hulp bij beloningen, grijze quests, groepsquests en quest-items.

### 1.3 Wat de addon bewust niet doet
- Geen eigen complete questdatabase van heel Azeroth. Die bestaat al (Questie) en is met de hand niet te bouwen. QuestKompas gebruikt wat de client zelf weet, wat de speler zelf leert, en optioneel wat Questie weet.
- Geen gevechtshulp: geen rotaties, geen berekeningen op gezondheid, dreiging of vijandelijke spreuken. Dat is technisch geblokkeerd en valt buiten het doel.
- Geen automatisering van beweging, targeting of spreuken. Dat is botgedrag en verboden.
- Geen vervanging van de wereldkaart. We voegen alleen pins toe.

### 1.4 Verhouding tot bestaande addons
| Addon | Wat het doet | Hoe QuestKompas ermee omgaat |
|---|---|---|
| Questie | Quests en doelen op de kaart uit een database | Optionele integratie: als Questie geladen is, lezen we locaties uit; anders vallen we terug op client-data en eigen geleerde data |
| TomTom | Navigatiepijl | Optioneel: als TomTom geladen is, kunnen waypoints daarheen; anders eigen pijl |
| ForeverPlus, Leatrix Plus | Onder andere auto-accept en auto-turn-in | Overlap. Bij detectie een eenmalige waarschuwing tonen om dubbele automatisering te voorkomen |
| Forever Quest Pins | Uitroeptekens voor beschikbare quests | Overlap met module MapPins; eigen pins dan standaard uit voor "beschikbaar" |

---

## 2. Harde randvoorwaarden (niet onderhandelbaar)

### 2.1 Client en API
- Doelclient: **WoW Forever 1.60.1**. TOC-regel: `## Interface: 16001`.
- Het interfacenummer komt uit de live client. Controle in-game: `/run print(select(4, GetBuildInfo()))`. Wijkt het af, pas de TOC aan.
- Forever draait op de moderne (Mainline/Retail) client-architectuur met het overgrote deel van de API van retail 12.1.5. **Schrijf dus tegen de moderne API** (`C_QuestLog`, `C_Map`, `C_Item`, `C_Spell`, `C_GossipInfo`, `C_TooltipInfo`, `Settings`), niet tegen Classic Era of 1.12. Functies als `GetQuestLogTitle`, `GetNumQuestLogEntries` (globaal), `GetContainerItemInfo` bestaan niet of werken anders.
- Lua-versie: 5.1 (geen `goto`, geen integer division, geen bitwise operators; gebruik `bit.band` enzovoort).
- Classic-addons laden niet op Forever. Kopieer geen code uit Classic Era-addons zonder de API-aanroepen te vertalen.

### 2.2 Installatiemap
Addonmap staat in de Forever-installatie onder `Interface/AddOns`. Tijdens de beta was dat `World of Warcraft/_classic_beta_/Interface/AddOns`; voor de live client wordt `World of Warcraft/_forever_/Interface/AddOns` gemeld. **[VERIFIEER]** door lokaal in de installatiemap te kijken welke flavor-map bestaat en gebruik die in het installatiescript.

Mapnaam en TOC-naam moeten identiek zijn: `QuestKompas/QuestKompas.toc`.

### 2.3 Addonbeperkingen ("secret values")
Blizzard past op Forever exact dezelfde addonbeperkingen toe als op retail Midnight. Gevolgen voor dit project:
- De combat log is gesloten voor addons. Gebruik `COMBAT_LOG_EVENT_UNFILTERED` nergens.
- Tijdens gevecht zijn bepaalde waarden "geheim": onder meer gezondheid, dreiging, aura's, vijandelijke spreuken, en mogelijk namen en creature-ID's van units. Een geheime waarde kun je doorgeven aan een widget, maar niet vergelijken, optellen, als tabelsleutel gebruiken of opslaan.
- Regel voor dit project: **alle logica die beslissingen neemt draait buiten gevecht**. Tijdens gevecht doen we alleen passieve weergave van eerder berekende data.
- Waar we toch unit-data lezen (naam, GUID), eerst controleren met `issecretvalue(waarde)` **[VERIFIEER naam en gedrag]** en bij een geheime waarde de bewerking overslaan.

### 2.4 Taint en beveiligde frames
- Verander geen eigenschappen van beveiligde (secure) frames tijdens gevecht: geen `Show`, `Hide`, `SetPoint`, `SetAttribute` op frames die van `SecureActionButtonTemplate` of vergelijkbaar erven zolang `InCombatLockdown()` true is. Zet wijzigingen in een wachtrij en voer ze uit op `PLAYER_REGEN_ENABLED`.
- Overschrijf geen globale Blizzard-functies. Gebruik `hooksecurefunc` voor na-hooks.
- Raak de Blizzard objective tracker en de wereldkaart niet structureel aan (niet herparenten, geen interne tabellen wijzigen). Dat veroorzaakt taint die spreuken in gevecht kan blokkeren.
- Kaartpins bij voorkeur via de bibliotheek HereBeDragons-Pins (zelfde aanpak als HandyNotes en TomTom) in plaats van eigen manipulatie van `WorldMapFrame`.

### 2.5 Spelregels
- Geen acties namens de speler die een hardware-event vereisen zonder dat de speler klikt of een toets indrukt.
- Auto-accept en auto-turn-in van quests bij een geopend NPC-venster zijn gangbaar en toegestaan (bestaande addons doen dit). Automatisch een beloning kiezen staat standaard uit.
- Geen automatische chatspam. Tekst voor groepszoeken wordt in het invoerveld gezet; de speler drukt zelf op Enter.

---

## 3. Ontwerpprincipes

1. **Werkt altijd op alleen client-data.** Elke feature moet een bruikbare basisversie hebben zonder Questie, zonder TomTom en met een lege geleerde database.
2. **Gelaagde databronnen.** Voor de vraag "waar moet ik heen voor quest X" geldt deze volgorde: (a) client (`C_QuestLog.GetNextWaypoint`, quest-POI's), (b) Questie indien geladen, (c) eigen geleerde database, (d) onbekend, toon dat eerlijk.
3. **Niets doen in gevecht.** Zie 2.3.
4. **Modulair.** Elke module kan in de instellingen uit en mag bij een fout de rest niet meenemen (elke module-init in `xpcall`).
5. **Goedkoop.** Geen `OnUpdate` per frame voor logica. Gebruik events plus een throttle (minimaal 0,2 s) voor de pijl en maximaal één herberekening per 0,5 s voor de lijst.
6. **Defensief.** Elke API-aanroep die `nil` kan geven (questdata nog niet geladen, speler in instance zonder kaartpositie) wordt afgevangen.
7. **Geen externe afhankelijkheden die niet meegeleverd zijn.** Bibliotheken staan in `Libs/` in de repo.

---

## 4. Functionaliteit per module

Elke module heeft: doel, gedrag, gebruikte API, acceptatiecriteria. Prioriteit: P1 = fase 1 tot en met 3, P2 = fase 4 tot en met 6, P3 = later.

### 4.1 Core (P1)
**Doel:** opstart, event-dispatch, opslag, combat-wachtrij, logging.

Gedrag:
- Eén verborgen frame registreert events en stuurt ze door naar modules die zich abonneren.
- `ns.Core:RegisterModule(naam, tabel)`; elke module heeft optioneel `OnInit`, `OnEnable`, `OnDisable`, `OnCombatStart`, `OnCombatEnd`.
- `ns.Core:RunOutOfCombat(fn)`: voert direct uit of zet in wachtrij tot `PLAYER_REGEN_ENABLED`.
- `ns.Core:Debounce(sleutel, seconden, fn)` op basis van `C_Timer.NewTimer`.
- Debugmodus (`/qk debug`) schrijft naar een eigen scrollbaar logvenster, niet naar chat.

Acceptatie:
- Addon laadt zonder Lua-fouten op een schoon profiel (BugSack leeg).
- Een module die in `OnEnable` een fout gooit wordt uitgeschakeld met één chatregel; andere modules werken door.

### 4.2 QuestData (P1)
**Doel:** één interne, genormaliseerde weergave van het questlog, zodat geen andere module rechtstreeks de quest-API aanroept.

Gedrag:
- Bouwt bij `QUEST_LOG_UPDATE` (gedebounced 0,3 s), `QUEST_ACCEPTED`, `QUEST_REMOVED`, `QUEST_TURNED_IN`, `PLAYER_ENTERING_WORLD` een snapshot.
- Snapshot per quest:

```lua
{
  questID = 123,
  title = "…",
  level = 14,               -- questlevel
  difficulty = "yellow",    -- grey/green/yellow/orange/red
  isComplete = false,       -- klaar om in te leveren
  isFailed = false,
  zoneHeader = "Westfall",  -- kop uit het questlog
  suggestedGroup = 0,       -- 0 = solo
  tagName = nil,            -- Elite, Dungeon, Raid, PvP of nil
  objectives = {
    { text = "Defias Thug slain", type = "monster", done = 3, need = 10, finished = false },
  },
  xpReward = 850,
  moneyReward = 1200,       -- in koper
  hasUsableItem = true, itemLink = "…", itemTexture = 12345,
  isWatched = true,
  distanceSq = 15234.5,     -- nil als onbekend
  mapID = 52,               -- nil als onbekend
}
```
- Vergelijkt nieuwe snapshot met vorige en vuurt interne callbacks: `QK_QUEST_ADDED`, `QK_QUEST_REMOVED`, `QK_QUEST_COMPLETED` (klaar om in te leveren), `QK_OBJECTIVE_PROGRESS(questID, objectiveIndex, oud, nieuw)`, `QK_QUEST_TURNED_IN(questID, xp, money)`.

API (moderne namen, allemaal **[VERIFIEER]** in de export):
- `C_QuestLog.GetNumQuestLogEntries()`, `C_QuestLog.GetInfo(index)` (velden onder meer `title`, `questID`, `level`, `isHeader`, `suggestedGroup`, `frequency`, `isHidden`)
- `C_QuestLog.GetQuestObjectives(questID)` (velden `text`, `type`, `finished`, `numFulfilled`, `numRequired`)
- `C_QuestLog.IsComplete(questID)`, `C_QuestLog.IsFailed(questID)`, `C_QuestLog.ReadyForTurnIn(questID)`
- `C_QuestLog.GetQuestTagInfo(questID)`, `C_QuestLog.GetSuggestedGroupSize(questID)`
- `C_QuestLog.GetQuestDifficultyLevel(questID)`, `GetQuestDifficultyColor(level)`
- `C_QuestLog.GetDistanceSqToQuest(questID)`
- `C_QuestLog.GetLogIndexForQuestID(questID)`, `GetQuestLogSpecialItemInfo(logIndex)`
- `GetQuestLogRewardXP(questID)`, `GetQuestLogRewardMoney(questID)`
- `C_QuestLog.IsQuestFlaggedCompleted(questID)`
- `C_QuestLog.RequestLoadQuestByID(questID)` plus event `QUEST_DATA_LOAD_RESULT` voor data die nog niet in de cache zit

Acceptatie:
- `/qk dump` toont de snapshot en die klopt met het questlog voor minstens 10 quests in 2 zones.
- Bij het doden van een questmob vuurt exact één `QK_OBJECTIVE_PROGRESS`.
- Geen fouten wanneer questdata bij inloggen nog niet beschikbaar is (titels `nil`): quest wordt later aangevuld.

### 4.3 Tracker (P1)
**Doel:** eigen questvenster, het hart van de addon.

Gedrag:
- Verplaatsbaar, vergrendelbaar, schaalbaar venster. Positie per character opgeslagen.
- Sortering (instelbaar): op afstand (standaard), op level, op zone, handmatig.
- Groepering: "Klaar om in te leveren" bovenaan, daarna huidige zone, daarna overige zones (ingeklapt).
- Per quest één kopregel: `[14] Titel` in moeilijkheidskleur, rechts afstand in yards en een richtingsindicator. Daaronder doelen met voortgang `3/10`; afgeronde doelen grijs of verborgen (instelbaar).
- Markeringen: `+` voor groepsquest met aanbevolen aantal, schedel voor elite, slotje voor dungeon, klokje voor quest met timer.
- Muis:
  - Linksklik op titel: quest als navigatiedoel zetten (zie 4.4).
  - Shift-linksklik: quest linken in chat-invoerveld als dat open is.
  - Rechtsklik: contextmenu met Navigeer hierheen, Open in questlog, Deel met groep, Niet meer volgen, Opgeven (met bevestiging), Notitie toevoegen.
  - Hover: tooltip met questbeschrijving, beloningen, XP, en geleerde locaties.
- Voettekst (instelbaar): aantal quests `17/25` (maximum uit `C_QuestLog.GetMaxNumQuestsCanAccept()` **[VERIFIEER]**), XP per uur van deze sessie, geschatte quests tot volgend level.
- In gevecht: optioneel vervagen naar 30% dekking en muis doorlaten. Het venster is een gewoon (niet-secure) frame, dus tonen en verbergen mag in gevecht, maar we herbouwen de inhoud dan niet.
- Standaard Blizzard-tracker: optie "verberg standaard tracker". **Voorzichtig**: alleen via een ondersteunde route (Edit Mode-instelling of `ObjectiveTrackerFrame:SetAlpha(0)` plus muis uit, buiten gevecht), nooit herparenten. **[VERIFIEER]** welke aanpak geen taint geeft.

Acceptatie:
- Venster toont alle gevolgde quests correct en werkt bij binnen 1 s na voortgang.
- Slepen, vergrendelen, schaal 0,7 tot 1,5 werken en blijven bewaard na `/reload`.
- 25 quests in het log: herbouw kost onder 5 ms (meet met `debugprofilestop()`).

### 4.4 Navigator (P1)
**Doel:** pijl en afstand naar het actieve doel.

Gedrag:
- Eén "actief doel": een quest (dan bepaalt de addon het punt) of een vrij kaartpunt.
- Puntbepaling voor een quest, in volgorde:
  1. Client: `C_QuestLog.GetNextWaypoint(questID)` geeft `mapID, x, y` **[VERIFIEER beschikbaarheid op Forever; in een vanilla-achtige wereld kan dit voor veel quests leeg zijn]**.
  2. Client quest-POI's: `C_QuestLog.GetQuestsOnMap(uiMapID)`. Let op: er is gemeld dat Forever hiervoor deels de retail-achtige `C_TaskQuest.GetQuestsOnMap` gebruikt. **[VERIFIEER]** welke van de twee data geeft.
  3. Questie-brug (4.12).
  4. Geleerde database (4.6): inleverpunt als de quest klaar is, anders dichtstbijzijnde geleerde voortgangsplek.
  5. Onbekend: pijl verbergen en in de tracker "locatie onbekend" tonen.
- Weergave, twee modi:
  - **Native**: `C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(mapID, x, y))` plus `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`; voor quests `C_SuperTrack.SetSuperTrackedQuestID(questID)`. Dit gebruikt de ingebouwde navigatie van de client.
  - **Eigen pijl** (standaard als native niets toont): klein verplaatsbaar frame met pijltextuur, afstand in yards, naam van het doel en geschatte aankomsttijd. Richting = hoek tussen `GetPlayerFacing()` en de vector speler naar doel. `GetPlayerFacing()` geeft `nil` in instances: pijl dan verbergen.
  - Als TomTom geladen is en de optie aan staat: `TomTom:AddWaypoint(mapID, x, y, {title = …})` in plaats van eigen pijl.
- Afstand in yards: wereldcoördinaten via `C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))` voor zowel speler als doel, of via HereBeDragons `GetZoneDistance`. Aanbevolen: HereBeDragons, want die lost zonegrenzen en continenten op.
- Doel op ander continent of in een andere zone zonder berekenbare afstand: toon zonenaam en "andere zone" in plaats van yards.
- Automatisch doorschakelen (instelbaar, standaard aan): bij `QK_QUEST_COMPLETED` of `QK_QUEST_TURNED_IN` kiest de Navigator het volgende doel uit de Planner (4.5).
- Aankomst: binnen 10 yards van het punt een zacht geluid en pijl wordt een vinkje.

Acceptatie:
- Klik op een quest in de tracker laat binnen 0,5 s een pijl zien die correct wijst (controle: lopen naar het punt verkleint de afstand tot onder 10).
- Pijlupdate is gethrottled op 0,1 tot 0,2 s en kost geen merkbare fps.
- Geen fouten in instances, op boten en tijdens een vlucht (positie `nil`).

### 4.5 Planner (P2)
**Doel:** volgorde voorstellen: "wat is nu het slimst".

Gedrag:
- Berekent buiten gevecht een aanbevolen volgorde voor quests in de huidige zone:
  1. Inleverklare quests waarvan het inleverpunt bekend is, dichtstbijzijnde eerst.
  2. Actieve quests met bekende locatie, via nearest-neighbour vanaf de spelerpositie.
  3. Quests met onbekende locatie onderaan.
- Clustering: doelen binnen 150 yards van elkaar gelden als één stop ("3 quests hier").
- Weging (instelbaar): voorkeur voor quests die bijna klaar zijn, straf voor rode en groepsquests als je solo bent, grijze quests onderaan.
- Uitvoer: genummerde volgorde in de tracker (kleine cijfers voor de titel) en een knop "Volgende".
- Geen hele-wereldroutering in versie 1. Alleen binnen de huidige zone; andere zones worden als blok getoond met aantal quests.

Acceptatie:
- Met 6 quests in één zone is de voorgestelde volgorde aantoonbaar korter dan logvolgorde (som van afstanden, zichtbaar in `/qk plan debug`).
- Herberekening hooguit eens per 2 s en nooit in gevecht.

### 4.6 Learn: zelflerende locatiedatabase (P2)
**Doel:** de database die Forever-specifieke quests dekt waar andere bronnen nog gaten hebben, opgebouwd door te spelen.

Wat wordt vastgelegd (alleen buiten instances, alleen als de positie beschikbaar is):
- Bij `QUEST_ACCEPTED`: questID, titel, level, `mapID, x, y` van de speler, naam en NPC-ID van de questgever (uit `UnitGUID("npc")` of `UnitGUID("questnpc")`, GUID-formaat `Creature-0-…-npcID-…`; bij een object of item als bron: type vastleggen). **[VERIFIEER unit-tokens]**
- Bij `QUEST_TURNED_IN`: hetzelfde voor het inleverpunt, plus XP en geld.
- Bij `QK_OBJECTIVE_PROGRESS`: `mapID, x, y` van de speler op dat moment, objective-index en objective-tekst. Punten binnen 40 yards worden samengevoegd tot een hotspot met teller. Maximaal 12 hotspots per objective (minst gebruikte vervalt).
- Questketens: als binnen 10 s na een inlevering bij dezelfde NPC een nieuwe quest wordt geaccepteerd, leg `vervolgVan = vorigeQuestID` vast.
- Voorwaarden: level van het character bij acceptatie (laagste ooit gezien = indicatie minimumlevel), factie, en klasse en ras als de quest daar mogelijk aan gebonden is (alleen vastleggen, niet concluderen).

Gebruik:
- Navigator en Planner lezen eruit (laag 4 in de bronvolgorde).
- MapPins toont geleerde questgevers van quests die dit character nog niet gedaan heeft.
- Tooltip in de tracker: "Vorige keer: 4 hotspots, opgepakt bij Gryan Stoutmantle".

Opslag: account-breed in `QuestKompasDB.learned` (zie hoofdstuk 6), zodat alts meteen profiteren.

Delen:
- `/qk export [zone|alles]` maakt een tekenreeks (LibSerialize plus LibDeflate, voor print gecodeerd) in een kopieervenster.
- `/qk import` opent een plakvenster; data wordt samengevoegd (hotspots optellen, nieuwste questgever wint bij conflict) na een bevestiging met een samenvatting ("312 quests, 41 nieuw").
- Import valideert typen en bereiken (coördinaten tussen 0 en 1, ID's numeriek, tekenreeksen maximaal 200 tekens) en voert nooit code uit.

Acceptatie:
- Na het doen van 5 quests staan oppak- en inleverpunt binnen 5 yards van de werkelijke NPC.
- Een alt ziet op de kaart de questgevers van die 5 quests.
- Export gevolgd door import op een leeg profiel levert identieke data op.
- Bestandsgrootte SavedVariables blijft onder 2 MB bij 1500 quests (afronden van coördinaten op 4 decimalen, korte sleutels).

### 4.7 AutoQuest (P1)
**Doel:** minder klikken bij NPC's.

Gedrag:
- **Auto-accept** (standaard aan): bij `QUEST_DETAIL` wordt `AcceptQuest()` aangeroepen. Bij `GOSSIP_SHOW` en `QUEST_GREETING` worden beschikbare quests één voor één geselecteerd.
- **Auto-turn-in** (standaard aan): bij `QUEST_PROGRESS` met `IsQuestCompletable()` wordt `CompleteQuest()` aangeroepen; bij `QUEST_COMPLETE` wordt `GetQuestReward(keuze)` aangeroepen **alleen als er nul of één beloningskeuze is** (`GetNumQuestChoices() <= 1`). Bij meerdere keuzes stopt de automatisering en neemt RewardHelper (4.8) het over.
- **Modifier om over te slaan**: Shift ingedrukt houden bij het aanspreken schakelt alles voor dat venster uit (instelbaar welke toets).
- **Uitzonderingen**, nooit automatisch:
  - Quests die geld of items kosten bij inleveren (`GetQuestMoneyToGet() > 0` of vereiste items die geen questitems zijn). Dan wachten op de speler.
  - Herhaalbare quests (instelbaar, standaard niet automatisch).
  - Quests op de persoonlijke zwarte lijst (rechtsklik in tracker: "Nooit automatisch accepteren").
  - Quests met een level boven spelerlevel plus 4 (instelbaar), om rode quests niet ongemerkt op te pakken.
  - Volle questlog: melding in het midden van het scherm in plaats van een foutgeluid.
  - Escortquests en quests met timer bij acceptatie: bevestiging vragen.
- **Gossip overslaan** (standaard uit): als een NPC precies één gossip-optie heeft en geen quests, die optie kiezen. Uit bij vendors, trainers, flight masters en bankiers (herkennen aan het icoontype van de optie) om verkeerde keuzes te voorkomen.
- Elke automatische actie geeft één korte chatregel (instelbaar): `QuestKompas: geaccepteerd [14] The People's Militia`.

API **[VERIFIEER]**: `C_GossipInfo.GetAvailableQuests()`, `C_GossipInfo.GetActiveQuests()`, `C_GossipInfo.SelectAvailableQuest(questID)`, `C_GossipInfo.SelectActiveQuest(questID)`, `C_GossipInfo.GetOptions()`, `C_GossipInfo.SelectOption(gossipOptionID)`, `GetNumAvailableQuests()`, `GetNumActiveQuests()`, `SelectAvailableQuest(i)`, `SelectActiveQuest(i)`, `AcceptQuest()`, `CompleteQuest()`, `GetQuestReward(i)`, `GetNumQuestChoices()`, `IsQuestCompletable()`, `GetQuestID()`, `QuestGetAutoAccept()`, `AcknowledgeAutoAcceptQuest()`.

Acceptatie:
- Een NPC met 3 beschikbare en 2 inleverbare quests: alles wordt afgehandeld zonder klik, behalve een eventuele beloningskeuze.
- Shift ingedrukt: niets gebeurt automatisch.
- Geen eindeloze lus bij een NPC die een quest blijft aanbieden (bewaker: per questID maximaal 1 automatische poging per 3 s).

### 4.8 RewardHelper (P2)
**Doel:** helpen kiezen bij meerdere beloningen, zonder zelf te kiezen.

Gedrag bij `QUEST_COMPLETE` met meer dan één keuze:
- Markeer op de beloningsknoppen: gouden muntje op het item met de hoogste verkoopprijs; groene pijl op items die een waarschijnlijke upgrade zijn.
- Upgrade-inschatting, eenvoudig en transparant: item is draagbaar door de klasse (pantsertype, wapentype), en itemlevel is hoger dan het huidig gedragen item in dat slot. Geen stat-gewichten in versie 1. Als Pawn geladen is, laat Pawn dat doen en toon alleen het muntje.
- Tooltipregel onder elke keuze: `Verkoopprijs: 12s 40c` en `Huidig: [itemnaam] (ilvl 18)`.
- Optie (standaard uit): "Kies automatisch duurste als niets een upgrade is".

API **[VERIFIEER]**: `GetQuestItemLink("choice", i)`, `GetQuestItemInfo("choice", i)`, `C_Item.GetItemInfo(link)` (verkoopprijs is de elfde returnwaarde), `C_Item.GetDetailedItemLevelInfo(link)`, `GetInventoryItemLink("player", slot)`, `C_Item.IsEquippableItem`, itemdata kan asynchroon zijn: gebruik `Item:CreateFromItemLink(link):ContinueOnItemLoad(fn)`.

Acceptatie:
- Bij een quest met 3 keuzes staat het muntje op het item met de hoogste verkoopprijs (controle bij vendor).
- Geen automatische keuze tenzij de optie expliciet aan staat.

### 4.9 MapPins (P2)
**Doel:** relevante questpunten op wereldkaart en minimap.

Pinsoorten (elk apart aan en uit):
- Inleverpunt van klare quests (geel vraagteken).
- Geleerde of bekende voortgangshotspots van actieve quests (gekleurde stip per quest, zelfde kleur als in de tracker).
- Questgevers van quests die dit character nog niet gedaan heeft, uit de geleerde database (geel uitroepteken; grijs als het level te laag is).
- Het actieve navigatiedoel (grote ring).

Gedrag:
- Implementatie met HereBeDragons-Pins-2.0: `pins:AddWorldMapIconMap(ref, frame, mapID, x, y, showFlag)` en `pins:AddMinimapIconMap(ref, frame, mapID, x, y, showInParentZone, floatOnEdge)`.
- Pinframes uit een eigen pool (hergebruik, geen nieuwe frames per update).
- Klik op een pin: zet als navigatiedoel. Hover: questtitel, level, doeltekst.
- Coördinaten: klein tekstveld onderaan de wereldkaart met speler- en cursorcoördinaten (de standaardkaart toont die niet).
- `/qk way 45.2 67.8 [zone]`: vrij navigatiepunt, zelfde syntaxis als TomTom voor herkenbaarheid.

Acceptatie:
- Pins verschijnen op de juiste plek op zonekaart en continentkaart en verdwijnen na inleveren.
- Kaart openen en sluiten in gevecht geeft geen "action blocked"-melding (taintcontrole met `/console taintLog 1`).

### 4.10 ItemBar (P2)
**Doel:** questitems die je moet gebruiken direct bij de hand.

Gedrag:
- Rij knoppen (maximaal 6) met bruikbare questitems van actieve quests, dichtstbijzijnde quest eerst.
- Knoppen zijn `SecureActionButtonTemplate` met `type = "item"` en `item = itemnaam of item:ID`. Opbouw en wijzigingen **uitsluitend buiten gevecht**; verandert de set tijdens gevecht, dan pas na `PLAYER_REGEN_ENABLED` bijwerken.
- Toont cooldown en aantal. Keybind instelbaar voor knop 1 via `SetOverrideBindingClick` (buiten gevecht).
- Verbergt zichzelf als er geen bruikbare items zijn (ook dat alleen buiten gevecht; in gevecht blijft hij staan zoals hij was).

Acceptatie:
- Een quest met gebruiksitem toont binnen 1 s na acceptatie een werkende knop.
- Geen taintmeldingen na 10 gevechten met de balk zichtbaar.

### 4.11 LogTools (P2)
**Doel:** questlog schoon houden.

Gedrag:
- **Grijze quests**: `/qk grey` toont een lijst van quests die grijs zijn geworden, met per stuk een knop Opgeven en een knop "Alles opgeven" (dubbele bevestiging, met aantal).
- **Vol log**: bij 23 van 25 quests een eenmalige hint met de 3 beste kandidaten om op te geven (grijs, verste weg, laagste XP).
- **Niet af te maken**: markeer mislukte quests rood met de suggestie opnieuw op te pakken.
- **Notities**: vrije tekst per quest (maximaal 300 tekens), zichtbaar in tracker-tooltip, account-breed bewaard per questID.
- **Zoeken**: `/qk find tekst` zoekt in titels en doelen van actieve quests en in de geleerde database.

API **[VERIFIEER]**: opgeven vereist de reeks `C_QuestLog.SetSelectedQuest(questID)`, `C_QuestLog.SetAbandonQuest()`, `C_QuestLog.AbandonQuest()`.

Acceptatie:
- Bulk opgeven doet niets zonder twee bevestigingen en geeft nooit een quest op die niet in de getoonde lijst stond.

### 4.12 Bridges: Questie en TomTom (P3)
**Doel:** externe data gebruiken als die er is, zonder ervan afhankelijk te zijn.

Gedrag:
- Detectie met `C_AddOns.IsAddOnLoaded("Questie")` en `"TomTom"`.
- Questie heeft geen stabiele publieke API. De brug is daarom één bestand met alle aanroepen in `pcall`, en een zelftest bij het laden: lukt het opvragen van één bekende quest niet, dan schakelt de brug zichzelf uit met één debugregel. **[VERIFIEER]** de actuele interne modulestructuur van Questie voor Forever (historisch: `QuestieLoader:ImportModule("QuestieDB")` en `QuestieDB.GetQuest(questID)` met velden voor starters, finishers en objectives met spawns). Bouw dit pas na inspectie van de geïnstalleerde Questie-broncode.
- TomTom: `TomTom:AddWaypoint(mapID, x, y, opts)` en `TomTom:RemoveWaypoint(uid)`.

Acceptatie:
- Met en zonder Questie en TomTom geen enkele Lua-fout.
- Na een Questie-update die de structuur wijzigt valt de brug stil terug in plaats van fouten te gooien.

### 4.13 Stats (P2)
**Doel:** voortgang inzichtelijk.

Gedrag:
- Sessie: XP per uur (totaal en alleen uit quests), quests per uur, geld uit quests, tijd tot volgend level bij huidig tempo.
- Historie per character: lijst van ingeleverde quests met datum, zone, level, XP, geld. Maximaal 2000 regels, oudste vervalt.
- `/qk stats` opent een eenvoudig venster; `/qk stats reset` wist de sessie.
- "Quests tot level": resterende XP gedeeld door gemiddelde quest-XP van de laatste 10 inleveringen.

API: `UnitXP("player")`, `UnitXPMax("player")`, `GetXPExhaustion()`, events `PLAYER_XP_UPDATE`, `PLAYER_LEVEL_UP`, `QUEST_TURNED_IN(questID, xpReward, moneyReward)`.

### 4.14 Party (P3)
**Doel:** samen questen.

Gedrag:
- Deel alle deelbare quests met één knop (`C_QuestLog.IsPushableQuest(questID)`, `QuestLogPushQuest()` na `C_QuestLog.SetSelectedQuest`), met 0,5 s tussen aanroepen.
- Groepszoekregel: rechtsklik op een groepsquest zet `LFM [Titel] (elite, 3 spelers)` in het chat-invoerveld. Niet automatisch versturen.
- Voortgang van groepsleden die ook QuestKompas hebben, via addonberichten (`C_ChatInfo.RegisterAddonMessagePrefix("QKOMPAS")`, `C_ChatInfo.SendAddonMessage(prefix, bericht, "PARTY")`). **[VERIFIEER]**: de moderne client beperkt addonberichten in instances en tijdens gevecht. Alleen versturen buiten gevecht en buiten instances, maximaal 1 bericht per 2 s, payload onder 200 tekens.
- Inkomende berichten zijn onbetrouwbare invoer: strikt parsen, lengte en typen controleren, nooit `loadstring`.

### 4.15 Options (P1 basis, daarna meegroeien)
- Registratie in het standaard instellingenmenu via de `Settings`-API (`Settings.RegisterVerticalLayoutCategory`, `Settings.RegisterAddOnSetting`, `Settings.CreateCheckbox`, `Settings.CreateSlider`, `Settings.CreateDropdown`, `Settings.RegisterAddOnCategory`). **[VERIFIEER]** exacte signaturen in de export; ze zijn tussen patches gewijzigd.
- Knop in het addon-compartiment (TOC-veld `AddonCompartmentFunc`).
- Profielen: account-standaard plus optioneel per character overschrijven. Geen AceDB nodig; eigen eenvoudige merge met defaults.
- Knop "Alles terugzetten" en per module "Module terugzetten".

---

## 5. Architectuur en bestandsstructuur

```
QuestKompas/
├── QuestKompas.toc
├── CLAUDE.md                  -- korte werkinstructie, verwijst naar dit document
├── README.md
├── CHANGELOG.md
├── .luacheckrc
├── Libs/
│   ├── LibStub/
│   ├── CallbackHandler-1.0/
│   ├── HereBeDragons/         -- HereBeDragons-2.0 en HereBeDragons-Pins-2.0
│   ├── LibSerialize/
│   └── LibDeflate/
├── Locales/
│   ├── enUS.lua               -- basis, altijd geladen
│   └── nlNL.lua               -- addon-eigen Nederlandse teksten (zie hoofdstuk 9)
├── Core/
│   ├── Init.lua               -- namespace, versie, constanten
│   ├── Compat.lua             -- wrappers rond API's die kunnen ontbreken
│   ├── Events.lua             -- dispatcher, interne callbacks
│   ├── Combat.lua             -- wachtrij, InCombatLockdown-bewaking
│   ├── DB.lua                 -- defaults, migraties, opslag
│   ├── Util.lua               -- afstand, kleuren, geldopmaak, debounce
│   └── Debug.lua              -- logvenster, profiler
├── Modules/
│   ├── QuestData.lua
│   ├── Tracker.lua
│   ├── Navigator.lua
│   ├── Planner.lua
│   ├── Learn.lua
│   ├── AutoQuest.lua
│   ├── RewardHelper.lua
│   ├── MapPins.lua
│   ├── ItemBar.lua
│   ├── LogTools.lua
│   ├── Stats.lua
│   ├── Party.lua
│   └── Bridges.lua
├── UI/
│   ├── Widgets.lua            -- herbruikbare rijen, knoppen, pools
│   ├── Options.lua
│   ├── ExportFrame.lua
│   └── Media/                 -- pijl.tga, pins.tga, geluiden (.ogg)
├── Slash.lua
├── tests/
│   ├── wow_stub.lua           -- nagebootste WoW-API voor tests buiten het spel
│   ├── run.lua
│   └── spec_*.lua
└── tools/
    ├── install.sh             -- kopieert of symlinkt naar de AddOns-map (macOS, Linux)
    ├── install.ps1            -- idem voor Windows
    └── package.sh             -- maakt een zip voor delen
```

### 5.1 TOC-bestand

```
## Interface: 16001
## Title: QuestKompas
## Notes: Questhulp voor WoW Forever: tracker, navigatie, auto-quest en een zelflerende locatiedatabase.
## Author: Scott
## Version: 0.1.0
## SavedVariables: QuestKompasDB
## SavedVariablesPerCharacter: QuestKompasCharDB
## OptionalDeps: Questie, TomTom, Pawn
## AddonCompartmentFunc: QuestKompas_OnCompartmentClick
## IconTexture: Interface\AddOns\QuestKompas\UI\Media\icon

Libs\LibStub\LibStub.lua
Libs\CallbackHandler-1.0\CallbackHandler-1.0.lua
Libs\HereBeDragons\HereBeDragons-2.0.lua
Libs\HereBeDragons\HereBeDragons-Pins-2.0.lua
Libs\LibSerialize\LibSerialize.lua
Libs\LibDeflate\LibDeflate.lua

Locales\enUS.lua
Locales\nlNL.lua

Core\Init.lua
Core\Compat.lua
Core\Events.lua
Core\Combat.lua
Core\DB.lua
Core\Util.lua
Core\Debug.lua

Modules\QuestData.lua
Modules\Learn.lua
Modules\Navigator.lua
Modules\Planner.lua
Modules\Tracker.lua
Modules\AutoQuest.lua
Modules\RewardHelper.lua
Modules\MapPins.lua
Modules\ItemBar.lua
Modules\LogTools.lua
Modules\Stats.lua
Modules\Party.lua
Modules\Bridges.lua

UI\Widgets.lua
UI\Options.lua
UI\ExportFrame.lua
Slash.lua
```

Opmerkingen:
- Alleen Forever is doel, dus één TOC volstaat. Mocht er ooit een tweede client bij komen: aparte bestanden met achtervoegsel `_Forever.toc` worden herkend.
- Neem alleen bibliotheekversies die Interface 16001 ondersteunen. **[VERIFIEER]** dat de gekozen HereBeDragons-versie Forever-kaart-ID's kent; zo niet, val terug op eigen afstandsberekening met `C_Map.GetWorldPosFromMapPos`.

### 5.2 Kernpatronen (referentiecode)

Namespace en modules:
```lua
-- Core/Init.lua
local ADDON, ns = ...
ns.name = ADDON
ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version")
ns.modules, ns.moduleOrder = {}, {}

function ns:RegisterModule(name, mod)
  mod.name = name
  self.modules[name] = mod
  self.moduleOrder[#self.moduleOrder + 1] = name
  return mod
end
```

Event-dispatcher met foutisolatie:
```lua
-- Core/Events.lua
local ADDON, ns = ...
local frame = CreateFrame("Frame")
local handlers = {}

function ns:On(event, owner, fn)
  if not handlers[event] then
    handlers[event] = {}
    -- interne events beginnen met QK_ en worden niet bij de client geregistreerd
    if event:sub(1, 3) ~= "QK_" then frame:RegisterEvent(event) end
  end
  handlers[event][owner] = fn
end

function ns:Fire(event, ...)
  local list = handlers[event]
  if not list then return end
  for owner, fn in pairs(list) do
    local ok, err = xpcall(fn, geterrorhandler(), owner, ...)
    if not ok then ns.Debug:Log("fout in", event, tostring(err)) end
  end
end

frame:SetScript("OnEvent", function(_, event, ...) ns:Fire(event, ...) end)
```

Combat-wachtrij:
```lua
-- Core/Combat.lua
local ADDON, ns = ...
local queue = {}

function ns:RunOutOfCombat(fn)
  if InCombatLockdown() then
    queue[#queue + 1] = fn
  else
    fn()
  end
end

ns:On("PLAYER_REGEN_ENABLED", "Combat", function()
  local pending = queue
  queue = {}
  for i = 1, #pending do
    xpcall(pending[i], geterrorhandler())
  end
end)
```

Veilige waarden:
```lua
-- Core/Compat.lua
local ADDON, ns = ...
local issecret = _G.issecretvalue  -- [VERIFIEER] bestaat op 16001

function ns.IsSafe(v)
  if v == nil then return false end
  if issecret and issecret(v) then return false end
  return true
end
```

---

## 6. Datamodel (SavedVariables)

### 6.1 Account-breed: `QuestKompasDB`
```lua
QuestKompasDB = {
  schema = 1,                      -- voor migraties
  settings = { ... },              -- zie 6.3
  learned = {
    quests = {
      [questID] = {
        t = "The People's Militia",   -- titel
        l = 12,                       -- questlevel
        ml = 10,                      -- laagste spelerlevel waarop geaccepteerd
        f = "A",                      -- A, H of B (beide gezien)
        s = { m = 52, x = 0.5632, y = 0.4763, n = "Gryan Stoutmantle", id = 234, k = "npc" },  -- start
        e = { m = 52, x = 0.5632, y = 0.4763, n = "Gryan Stoutmantle", id = 234, k = "npc" },  -- einde
        o = {                         -- objectives
          [1] = { txt = "Defias Thug slain", h = { { m = 52, x = 0.4812, y = 0.3655, c = 7 } } },
        },
        prev = 12,                    -- vervolg van questID
        seen = 1794268800,            -- laatst bijgewerkt (unix)
      },
    },
  },
  notes = { [questID] = "tekst" },
  blacklist = { [questID] = true },   -- nooit automatisch accepteren
}
```

### 6.2 Per character: `QuestKompasCharDB`
```lua
QuestKompasCharDB = {
  schema = 1,
  overrides = { ... },             -- instellingen die afwijken van account
  positions = { tracker = { "TOPRIGHT", -40, -220 }, arrow = { ... }, itembar = { ... } },
  history = { { id = 123, ts = 1794268800, z = "Westfall", l = 12, xp = 850, c = 1200 }, ... },
  session = { start = 0, xp = 0, questXP = 0, quests = 0, money = 0 },
  nav = { kind = "quest", questID = 123 },   -- laatste navigatiedoel
}
```

### 6.3 Instellingen met standaardwaarden
```lua
defaults = {
  modules = { Tracker = true, Navigator = true, Planner = true, Learn = true, AutoQuest = true,
              RewardHelper = true, MapPins = true, ItemBar = true, LogTools = true, Stats = true,
              Party = false, Bridges = true },
  tracker = { scale = 1.0, width = 260, locked = false, sort = "distance", hideDone = true,
              fadeInCombat = true, hideBlizzard = false, showFooter = true, maxRows = 30 },
  nav = { mode = "own", useTomTom = false, autoAdvance = true, arriveYards = 10, sound = true },
  auto = { accept = true, turnin = true, skipModifier = "SHIFT", repeatable = false,
           maxLevelAbove = 4, gossip = false, announce = true, autoReward = false },
  pins = { turnin = true, hotspots = true, givers = true, coords = true, minimap = true },
  learn = { enabled = true, maxHotspots = 12, mergeYards = 40 },
  planner = { clusterYards = 150, preferNearDone = true, penalizeGroup = true },
  itembar = { enabled = true, max = 6, key = nil },
  general = { language = "auto", debug = false },
}
```

### 6.4 Migraties
`Core/DB.lua` bevat een tabel `migrations[n] = function(db) ... end`. Bij laden: voer alle migraties uit met een nummer hoger dan `db.schema` en verhoog daarna `schema`. Nooit velden hernoemen zonder migratie. Defaults worden ingevuld met een diepe merge die bestaande waarden nooit overschrijft.

---

## 7. Events: overzicht

| Event | Gebruikt door | Doel |
|---|---|---|
| `ADDON_LOADED` | Core | DB initialiseren (argument is addonnaam, filter op de eigen naam) |
| `PLAYER_LOGIN` | Core | modules inschakelen |
| `PLAYER_ENTERING_WORLD` | QuestData, Navigator | eerste snapshot, positie herstellen |
| `PLAYER_LOGOUT` | Stats, Learn | sessie wegschrijven |
| `QUEST_LOG_UPDATE` | QuestData | snapshot (gedebounced) |
| `QUEST_ACCEPTED` | QuestData, Learn | nieuw, startpunt leren |
| `QUEST_REMOVED` | QuestData | verwijderd |
| `QUEST_TURNED_IN` | QuestData, Learn, Stats | eindpunt leren, XP en geld |
| `QUEST_WATCH_LIST_CHANGED` | Tracker | gevolgde quests |
| `QUEST_POI_UPDATE` | Navigator | client-locaties vernieuwd |
| `QUEST_DATA_LOAD_RESULT` | QuestData | asynchrone questdata binnen |
| `QUEST_DETAIL`, `QUEST_PROGRESS`, `QUEST_COMPLETE`, `QUEST_GREETING`, `QUEST_FINISHED` | AutoQuest, RewardHelper | NPC-vensters |
| `GOSSIP_SHOW`, `GOSSIP_CLOSED` | AutoQuest | gossip |
| `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED` | Core | gevecht begint en eindigt |
| `ZONE_CHANGED_NEW_AREA`, `ZONE_CHANGED` | Planner, MapPins | zonewissel |
| `PLAYER_XP_UPDATE`, `PLAYER_LEVEL_UP` | Stats, QuestData | XP, moeilijkheidskleuren herberekenen |
| `BAG_UPDATE_DELAYED` | ItemBar | aantallen |
| `GROUP_ROSTER_UPDATE` | Party, Planner | solo of groep |
| `CHAT_MSG_ADDON` | Party | synchronisatie |
| `SUPER_TRACKING_CHANGED`, `USER_WAYPOINT_UPDATED` | Navigator | native navigatie gewijzigd |

Alle namen **[VERIFIEER]** tegen de event-documentatie in de export; registreer events binnen `pcall` zodat een niet-bestaand event de addon niet breekt (een onbekend event gooit een fout bij `RegisterEvent`).

---

## 8. Interface en bediening

### 8.1 Visuele stijl
- Sober en leesbaar, aansluitend op de standaard UI. Achtergrond donker met 60% dekking, instelbaar.
- Lettertype: standaard gamefont (`GameFontNormalSmall`, `GameFontHighlightSmall`), schaalbaar via vensterschaal.
- Kleuren per quest: vaste reeks van 8 goed onderscheidbare kleuren, toegewezen op volgorde van acceptatie; dezelfde kleur op kaartpins en in de tracker.
- Moeilijkheidskleuren via `GetQuestDifficultyColor(level)`.
- Geen animaties behalve een korte flits (0,3 s) op een regel bij voortgang.

### 8.2 Slash-commando's
| Commando | Werking |
|---|---|
| `/qk` of `/questkompas` | opent instellingen |
| `/qk toggle` | tracker tonen of verbergen |
| `/qk lock` | vensters vergrendelen of ontgrendelen |
| `/qk reset` | posities terugzetten |
| `/qk next` | volgende doel uit de planner |
| `/qk way x y [zone]` | vrij navigatiepunt |
| `/qk clear` | navigatiedoel wissen |
| `/qk auto` | auto-quest aan of uit |
| `/qk grey` | grijze quests opruimen |
| `/qk find tekst` | zoeken |
| `/qk stats` | statistieken |
| `/qk export [zone|alles]`, `/qk import` | geleerde data delen |
| `/qk debug`, `/qk dump`, `/qk plan debug` | ontwikkelhulp |
| `/qk version` | versie, interfacenummer, geladen bruggen |

### 8.3 Keybindings
Via `Bindings.xml` of de moderne bindings-registratie **[VERIFIEER]**: Tracker tonen of verbergen, Volgende doel, Questitem 1 gebruiken, Navigatiedoel wissen.

---

## 9. Taal

- WoW heeft geen Nederlandse client; `GetLocale()` geeft dus nooit `nlNL`. Spelteksten (questtitels, doelen) komen in de clienttaal uit de API.
- Eigen teksten van de addon staan in `Locales/`. Instelling `general.language`: `auto` (Engels), `en`, `nl`. Standaard voor Scott: `nl`.
- Patroon: `local L = ns.L` met een metatable die bij een ontbrekende sleutel de sleutel zelf teruggeeft en in debugmodus logt.
- Nooit op spelteksten matchen (bijvoorbeeld "slain") voor logica. Gebruik de gestructureerde velden (`numFulfilled`, `type`).
- In Nederlandse teksten geen em-dash; gebruik komma, dubbele punt of haakjes.

---

## 10. Kwaliteit, prestaties en veiligheid

### 10.1 Prestatiebudget
- Geheugen bij inloggen onder 3 MB exclusief geleerde data; met 1500 geleerde quests onder 6 MB.
- CPU: geen module boven gemiddeld 0,5 ms per seconde in rust. Meet met `/qk debug profile` (eigen meting rond handlers met `debugprofilestop()`).
- Frame- en tabelhergebruik: pools voor rijen en pins; geen nieuwe tabellen in hete paden.

### 10.2 Foutafhandeling
- Elke eventhandler loopt via `xpcall`.
- Een module die 3 keer binnen 10 s faalt wordt uitgeschakeld tot de volgende `/reload`, met één melding.
- Geen `error()` naar de speler tijdens gevecht.

### 10.3 Veiligheid
- Importdata en addonberichten zijn onbetrouwbaar: valideren, begrenzen, nooit uitvoeren.
- Geen `loadstring`, geen `RunScript` op externe invoer.
- Geen netwerk, geen bestanden buiten SavedVariables (kan ook niet in WoW-Lua).

---

## 11. Fasering

Elke fase eindigt met een werkende, in-game geteste addon. Ga niet door voordat de acceptatiecriteria van de fase gehaald zijn en BugSack leeg is na 15 minuten spelen.

| Fase | Inhoud | Klaar als |
|---|---|---|
| 0. Skelet | Repo, TOC, Core (Init, Events, Combat, DB, Debug), `/qk version`, installatiescript, luacheck, teststub | Addon laadt, `/qk version` toont 16001, tests draaien lokaal |
| 1. Data | QuestData compleet met interne callbacks, `/qk dump` | Criteria 4.2 |
| 2. Tracker | Venster, sortering, klikgedrag, opties basis | Criteria 4.3 |
| 3. Auto en pijl | AutoQuest volledig; Navigator met native modus en eigen pijl op client-data | Criteria 4.7 en 4.4 (bronlaag 1 en 2) |
| 4. Leren | Learn, export en import, Navigator bronlaag 4 | Criteria 4.6 |
| 5. Kaart en plan | MapPins, Planner, coördinaten, `/qk way` | Criteria 4.9 en 4.5 |
| 6. Comfort | RewardHelper, ItemBar, LogTools, Stats | Criteria 4.8, 4.10, 4.11 |
| 7. Samen | Bridges (Questie, TomTom), Party | Criteria 4.12, 4.14 |
| 8. Afwerking | Volledige opties, nl-teksten, README, prestatieronde, taintronde | Budget 10.1 gehaald, geen taint in log |

Na elke fase: versienummer ophogen (0.1.0, 0.2.0, …), CHANGELOG bijwerken, git-tag.

---

## 12. Ontwikkelworkflow

### 12.1 Lokale opzet
1. Repo ergens buiten de gamemap. `tools/install.sh` (of `.ps1`) maakt een symlink van de repo-map `QuestKompas` naar de AddOns-map van Forever. Het script vraagt het pad de eerste keer en bewaart het in `.env.local` (niet in git).
2. In-game: `/reload` na elke wijziging aan Lua. Een nieuw bestand in de TOC of een gewijzigde TOC vereist een volledige herstart van de client.
3. Installeer als speler: BugSack en BugGrabber (vangen Lua-fouten), en zet `/console scriptErrors 1`.

### 12.2 De echte API opzoeken (verplicht voor alles met [VERIFIEER])
- Exporteer de interfacecode van de client: start de client met de console ingeschakeld en voer `ExportInterfaceFiles code` uit. **[VERIFIEER]** de exacte procedure voor Forever. Dit levert een map `BlizzardInterfaceCode` met alle FrameXML en `Blizzard_APIDocumentationGenerated`.
- Zet (een kopie van) die export buiten de repo en geef het pad door in `CLAUDE.md`, zodat Claude Code erin kan zoeken met grep. Dit is de primaire bron, boven elke wiki en boven kennis uit training.
- In-game hulpmiddelen: `/api zoekterm` (ingebouwde API-documentatie), `/fstack` (frames onder de cursor), `/etrace` (eventstroom), `/dump expressie`, `/tinspect tabel`.
- Naslag: Warcraft Wiki (API-pagina's en TOC-formaat). Controleer bij elke functie of die voor Mainline geldt.

### 12.3 Statische controle
`.luacheckrc` met `std = "lua51"`, `max_line_length = 120`, en een lijst `read_globals` met de gebruikte WoW-globals. Regel: `luacheck .` geeft nul waarschuwingen voordat je iets als klaar meldt.

### 12.4 Tests buiten het spel
- `tests/wow_stub.lua` bootst het minimum na: `CreateFrame` (met `RegisterEvent`, `SetScript`), `C_Timer`, `C_QuestLog` met instelbare nepdata, `C_Map`, `InCombatLockdown`, `GetTime`.
- Unit-tests voor pure logica: snapshot-diff in QuestData, sortering in Tracker, nearest-neighbour en clustering in Planner, samenvoegen van hotspots in Learn, export en import heen en terug, DB-migraties, validatie van importdata.
- Draaien met `lua5.1 tests/run.lua` (of LuaJIT). Geen testframework nodig; een eigen `assertEq` volstaat.
- Wat niet buiten het spel te testen is (frames, secure gedrag, taint) staat in het handmatige testplan.

### 12.5 Handmatig testplan (per fase herhalen)
1. Nieuw character level 1: startzone doorlopen tot level 6. Let op auto-accept, tracker, pijl.
2. Bestaand character met 15 of meer quests in het log: inloggen, `/reload`, zonewissel, vlucht nemen, boot of zeppelin.
3. Gevecht: 10 gevechten met alle vensters zichtbaar; kaart openen in gevecht; questitem gebruiken in gevecht. Daarna `Logs/taint.log` controleren (`/console taintLog 1` vooraf).
4. Dungeon in: geen fouten, pijl verborgen, niets geleerd.
5. Groep van 2: quests delen, groepsquest-markering.
6. Dood en als geest lopen: geen fouten.
7. Volle questlog: melding klopt.
8. Alt op hetzelfde account: geleerde questgevers zichtbaar.

---

## 13. Werkregels voor Claude Code

1. **Eén fase tegelijk.** Begin met fase 0. Lever per fase: code, tests, bijgewerkte CHANGELOG, en een korte lijst "in-game te controleren" voor Scott.
2. **Verifieer voor je bouwt.** Zoek elke API-functie en elk event eerst op in de geëxporteerde interfacecode. Staat de export nog niet klaar, vraag Scott erom en bouw in de tussentijd alleen dingen die er niet van afhangen (Core, DB, Util, tests).
3. **Alle onzekere API-aanroepen via `Core/Compat.lua`.** Modules roepen `ns.Compat.GetQuestObjectives(questID)` aan, niet rechtstreeks `C_QuestLog`. Zo zit elke correctie op één plek.
4. **Geen aannames uit Classic.** Zie 2.1.
5. **Niets in gevecht.** Elke functie die frames wijzigt of beslist, begint met een controle of loopt via `ns:RunOutOfCombat`.
6. **Geen globale vervuiling.** Alleen deze globals: `QuestKompasDB`, `QuestKompasCharDB`, `QuestKompas_OnCompartmentClick`, `SLASH_QUESTKOMPAS1`, `SLASH_QUESTKOMPAS2`, `SlashCmdList.QUESTKOMPAS`. Al het andere `local` of in `ns`.
7. **Kleine commits** met duidelijke berichten in het Nederlands of Engels, één onderwerp per commit.
8. **Meld onzekerheid.** Kun je iets niet verifiëren, markeer het in de code met `-- TODO(verify):` en zet het in de lijst voor Scott. Lever nooit iets op als "getest" dat alleen tegen de stub gedraaid heeft.
9. **Geen scope-uitbreiding.** Ideeën die niet in dit document staan gaan in `IDEAS.md`, niet in de code.
10. **Tekst voor de speler** in het Nederlands in `nlNL.lua`, zonder em-dash. Code, commentaar en identifiers in het Engels.

### 13.1 Voorgestelde eerste opdracht aan Claude Code
> Lees `QuestKompas-SPEC.md` volledig. Maak de repo-structuur uit hoofdstuk 5, schrijf `CLAUDE.md` met de werkregels uit hoofdstuk 13 en het pad naar de interface-export, en bouw fase 0. Gebruik nog geen API's met [VERIFIEER] behalve in `Core/Compat.lua` achter een bestaanscontrole. Sluit af met de lijst "in-game te controleren".

---

## 14. Risico's en open vragen

| Onderwerp | Risico | Aanpak |
|---|---|---|
| Client-questlocaties | Onbekend hoeveel quests op Forever een waypoint of POI van de client hebben | In fase 3 meten met `/qk dump`; bij weinig dekking Learn (fase 4) naar voren halen |
| Addonregels veranderen | Blizzard synchroniseert nieuwe beperkingen tussen retail en Forever; er is al een verdere beperking rond spellcast-events aangekondigd | Wij gebruiken geen gevechtsdata; na elke clientpatch het testplan draaien |
| Interfacenummer | Verandert bij patches, addon staat dan als verouderd gemarkeerd | TOC bijwerken; `/qk version` toont beide nummers |
| Questie-brug | Geen stabiele API, kan bij elke update breken | Geïsoleerd bestand, zelftest, stille terugval |
| Taint door tracker of kaart | Kan spreuken in gevecht blokkeren | HereBeDragons voor pins, standaard tracker niet aanraken tenzij geverifieerd, taintlog in testplan |
| Geheime waarden buiten gevecht | Mogelijk zijn sommige unit-waarden ook buiten gevecht beperkt (instances) | `ns.IsSafe` overal waar unit-data gelezen wordt |
| Kaart-ID's | Forever heeft nieuwe en gewijzigde zones; bibliotheekdata kan achterlopen | Afstand zelf berekenen als terugval; mapID's nooit hardcoderen |
| Dubbele automatisering | Leatrix Plus of ForeverPlus doet ook auto-quest | Detectie en waarschuwing (1.4) |
| Addonberichten | Beperkt in instances en gevecht | Party is P3 en standaard uit |

Open vragen voor Scott (beantwoorden voor fase 2):
1. Speel je Alliance of Horde, en welke klasse? (bepaalt de eerste testroute en RewardHelper-testgevallen)
2. Gebruik je nu Questie, TomTom of Leatrix Plus? (bepaalt of Bridges eerder moet)
3. Wil je de standaard questtracker verbergen of ernaast laten staan?
4. Windows of Mac? (installatiescript en pad)

---

## 15. Bronnen

- Kami-labs, "WoW Forever Addons: As Restricted As Midnight" (addonbeperkingen gelijk aan Midnight, filosofie tonen versus berekenen): https://kami-labs.fr/en/wow-classic/wow-forever-addons-restreints-comme-sur-midnight/
- Kami-labs, addonoverzicht WoW Forever (Retail-client, interface 16001, gesloten combat log, bestaande questaddons): https://kami-labs.fr/en/addons-wow-forever/
- ForeverMeta, "WoW Forever addons and interface" (Mainline 12.1.5 API, TOC-achtervoegsels): https://forevermeta.me/en/guides/wow-forever-addons-interface
- GitHub tobarisu1/wow_forever_addons (interface 16001, Mainline API, installatiepaden): https://github.com/tobarisu1/wow_forever_addons
- GitHub RGXMods/SimpleQuestPlates releases (melding over `C_TaskQuest.GetQuestsOnMap` op Forever): https://github.com/RGXMods/SimpleQuestPlates/releases
- GitHub ninepointlabs/wow-storytracker-addon releases (quest-events werkend op 1.60.1, beta-pad `_classic_beta_`): https://github.com/ninepointlabs/wow-storytracker-addon/releases
- Blizzard, "Combat Philosophy and Addon Disarmament in Midnight": https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight
