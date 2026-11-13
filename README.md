# QuestKompas

Questhulp voor **World of Warcraft: Forever** (client 1.60.1, Interface 16001): een eigen questvenster gesorteerd op afstand, een pijl naar het volgende doel, automatisch accepteren en inleveren, en een database die onthoudt waar jij quests oppakt, inlevert en voortgang boekt, zodat je alts daarvan profiteren.

Ontwerp en scope: [`docs/QuestKompas-SPEC.md`](docs/QuestKompas-SPEC.md). In-game controlelijst: [`docs/INGAME-TESTPLAN.md`](docs/INGAME-TESTPLAN.md).

## Installeren op de Mac

**Makkelijkst (zip):**
1. Pak `QuestKompas-<versie>.zip` uit (dubbelklik in Finder).
2. Sluit WoW en dubbelklik op `Installeer QuestKompas.command`. Meldt macOS "onbekende ontwikkelaar": rechtsklik, Open, nogmaals Open.
3. Start WoW Forever en typ `/qk version`. Je hoort `16001` te zien.

Met de hand kan ook: sleep de map `QuestKompas` uit de zip naar `/Applications/World of Warcraft/_forever_/Interface/AddOns/`.

**Voor ontwikkelen (symlink, wijzigingen direct na `/reload`):**
```bash
git clone https://github.com/sfmouris/WOW-addon.git ~/Code/WOW-addon
```
```bash
~/Code/WOW-addon/tools/install.sh
```
Het script zoekt `_forever_` (of `_classic_beta_`) en vraagt het pad als het niets vindt. Een nieuwe zip maak je met `tools/package.sh`.

**Automatisch bijwerken (Mac):** dubbelklik in de repo op `tools/mac/Automatisch bijwerken.command`. Dat zet een achtergrondtaak klaar die bij het inloggen en elke vier uur de nieuwste versie ophaalt en een melding toont als er iets is bijgewerkt (herstart WoW daarna). Het script regelt zo nodig ook de symlink naar de AddOns-map. Is een branch samengevoegd of verwijderd, dan stapt de taak zelf over naar de standaardbranch. Lokale wijzigingen worden nooit overschreven. Uitzetten: `Automatisch bijwerken uitzetten.command`. Logboek: `~/Library/Logs/QuestKompas-update.log`. Voorwaarde: git kan de repo zonder wachtwoord ophalen (openbare repo, of Terminal ingelogd bij GitHub); het script test dat en zegt wat je moet doen.

Aanrader: installeer BugSack en BugGrabber, en zet `/console scriptErrors 1`.

## Gebruik

| Commando | Werking |
|---|---|
| `/qk` | instellingen openen (ook via het addon-compartiment bij de minimap) |
| `/qk toggle`, `/qk lock`, `/qk reset` | tracker tonen of verbergen, vensters vergrendelen, posities terugzetten |
| `/qk next`, `/qk clear` | volgend doel uit de planner, navigatiedoel wissen |
| `/qk way 45.2 67.8 [zone]` | vrij navigatiepunt (zelfde syntaxis als TomTom) |
| `/qk auto` | auto-accept en auto-inleveren aan of uit |
| `/qk grey` | grijze quests opruimen (twee bevestigingen voor alles) |
| `/qk find tekst` | zoeken in je questlog en de geleerde database |
| `/qk stats [reset]` | XP per uur, quests tot level, laatste inleveringen |
| `/qk export [zone\|alles]`, `/qk import` | geleerde data delen met vrienden of alts |
| `/qk share` | alle deelbare quests delen (module Groep, standaard uit) |
| `/qk debug [profile]`, `/qk dump`, `/qk plan debug` | ontwikkelhulp |
| `/qk version`, `/qk help` | versie, interfacenummer, geladen bruggen |

In de tracker: **klik** op een quest om erheen te navigeren, **Shift-klik** om hem in de chat te linken, **rechtsklik** voor het menu (navigeren, delen, notitie, nooit automatisch accepteren, opgeven). Houd **Shift** ingedrukt bij het aanspreken van een NPC om de automatisering voor dat venster over te slaan.

Titelbalk van de tracker: knoppen voor het volgende doel, de instellingen, vergrendelen en inklappen. Past de lijst niet, dan scrol je met het muiswiel. De knop bij de minimap toont of verbergt de tracker (rechtsklik: instellingen, slepen: verplaatsen).

Toetsen instellen: Esc, Opties, Toetsenbinding, sectie QuestKompas (tracker tonen, volgende doel, doel wissen, questitem 1).

## Modules

| Module | Wat | Standaard |
|---|---|---|
| Tracker | questvenster, sortering op afstand, level, zone of handmatig | aan |
| Navigator | eigen pijl met afstand en aankomsttijd, of de ingebouwde navigatie | aan |
| Planner | slimste volgorde in de huidige zone, nummers in de tracker | aan |
| Leren | onthoudt questgevers, inleverpunten en voortgangsplekken (account-breed) | aan |
| Auto-quest | accepteren en inleveren met veiligheidsregels | aan |
| Beloningshulp | muntje op de duurste beloning, groene pijl op upgrades; kiest zelf niets | aan |
| Kaartpins | inleverpunten, hotspots, geleerde questgevers, coördinaten onder de kaart | aan |
| Questitembalk | knoppen voor bruikbare questitems | aan |
| Logtools | grijze quests, hint bij een vol log, notities, zoeken | aan |
| Statistieken | sessie en historie | aan |
| Groep | quests delen, voortgang van groepsleden, LFM-regel in het invoerveld | uit |
| Bruggen | Questie (locaties) en TomTom (waypoints) als die geladen zijn | aan |

Waar komt een locatie vandaan? In volgorde: de client (waypoint of kaart-POI), Questie als dat geladen is, je eigen geleerde data. Is het onbekend, dan zegt de tracker dat eerlijk.

## Ontwikkelen

```bash
brew install luajit luarocks
```
```bash
luarocks install luacheck
```
```bash
tools/check.sh
```

`tools/check.sh` draait luacheck en de tests (`tests/run.lua`) tegen een nagebootste client. Die tests vervangen het spel niet: frames, secure gedrag en taint controleer je in game met het testplan. Voor API-onderzoek: `tools/fetch-ui-source.sh` haalt de Blizzard-interfacecode van Forever op. Een zip maken: `tools/package.sh`.

## Bibliotheken

LibStub en CallbackHandler-1.0 (Ace3), HereBeDragons 2.0 (r35, kent Interface 16001), LibSerialize (MIT) en LibDeflate (zlib). Zie `QuestKompas/Libs/`.
