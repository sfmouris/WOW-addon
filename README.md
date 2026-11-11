# QuestKompas

Questhulp voor **World of Warcraft: Forever** (client 1.60.1, Interface 16001): een eigen questvenster gesorteerd op afstand, een pijl naar het volgende doel, automatisch accepteren en inleveren, en een database die onthoudt waar jij quests oppakt, inlevert en voortgang boekt, zodat je alts daarvan profiteren.

Ontwerp en scope: [`docs/QuestKompas-SPEC.md`](docs/QuestKompas-SPEC.md). In-game controlelijst: [`docs/INGAME-TESTPLAN.md`](docs/INGAME-TESTPLAN.md).

## Installeren op de Mac

1. Haal de repo binnen, ergens buiten de gamemap:
   ```bash
   git clone https://github.com/sfmouris/WOW-addon.git ~/Code/WOW-addon
   ```
2. Installeer de addon (maakt een symlink, zodat je wijzigingen direct na `/reload` ziet):
   ```bash
   ~/Code/WOW-addon/tools/install.sh
   ```
   Het script zoekt in `/Applications/World of Warcraft` naar `_forever_` (of `_classic_beta_`) en vraagt het pad als het niets vindt. Het pad wordt bewaard in `.env.local`. Wil je liever een kopie: `tools/install.sh --copy`. Verwijderen: `tools/install.sh --remove`.
3. Start WoW Forever volledig opnieuw en controleer in het spel:
   ```
   /run print(select(4, GetBuildInfo()))
   /qk version
   ```
   Het eerste moet `16001` geven. Wijkt het af, pas dan `## Interface:` aan in `QuestKompas/QuestKompas.toc`.
4. Aanrader: installeer BugSack en BugGrabber, en zet `/console scriptErrors 1`.

Geen git? Download de zip van GitHub, pak uit, en sleep de map `QuestKompas` naar `/Applications/World of Warcraft/_forever_/Interface/AddOns/`.

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
