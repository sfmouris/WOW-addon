# CLAUDE.md: werkinstructie voor QuestKompas

De enige bron van waarheid voor scope en ontwerp is `docs/QuestKompas-SPEC.md`. Lees eerst hoofdstuk 2 (harde randvoorwaarden) en 13 (werkregels).

## Repo-indeling
- `QuestKompas/` is de addonmap zelf (TOC, Core, Modules, UI, Libs, Locales). Alleen deze map gaat naar `Interface/AddOns`.
- `tests/` draait buiten het spel (`tools/check.sh` of `lua5.1 tests/run.lua`), met `tests/wow_stub.lua` als nagebootste client.
- `tools/` bevat `install.sh` (Mac/Linux, symlink naar de AddOns-map), `package.sh` (zip), `check.sh` (luacheck plus tests), `fetch-ui-source.sh` (Blizzard-export) en `make_media.py` (texturen).
- Afwijking van de boom in spec 5: `tests/` en `tools/` staan naast `QuestKompas/` in plaats van erin, zodat de symlink geen ontwikkelbestanden in de AddOns-map zet.

## De echte API opzoeken (spec 12.2)
- Interface-export van WoW Forever 1.60.1 (build 70888): `../wow-ui-source-forever` (ophalen met `tools/fetch-ui-source.sh`; bron is Gethe/wow-ui-source, branch `forever`).
- API-signaturen: `../wow-ui-source-forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/*.lua`, zoeken met grep op `Name = "Functienaam",`.
- FrameXML-gebruik: grep in `../wow-ui-source-forever/Interface/AddOns/Blizzard_*`. Forever (`WOW_PROJECT_CAMELOT = 18`) laadt de `Mainline`-bestanden, plus `Camelot`-overrides.
- Lukt verifiëren niet: `-- TODO(verify):` in de code en op de lijst in `docs/INGAME-TESTPLAN.md`.

## Werkregels (spec 13)
1. Eén fase tegelijk; lever code, tests, CHANGELOG en de lijst "in-game te controleren".
2. Verifieer elke API-functie en elk event in de export voor je erop bouwt.
3. Alle onzekere API-aanroepen via `Core/Compat.lua`. Modules roepen nooit rechtstreeks `C_QuestLog`, `C_GossipInfo`, `C_Map`, `C_SuperTrack` of `C_TaskQuest` aan (`tests/spec_static.lua` controleert dit).
4. Geen aannames uit Classic: moderne API (Mainline 12.1.5-achtig), Lua 5.1.
5. Niets in gevecht: frames wijzigen of beslissen alleen buiten gevecht of via `ns:RunOutOfCombat`.
6. Geen globale vervuiling. Toegestaan: `QuestKompasDB`, `QuestKompasCharDB`, `QuestKompas_OnCompartmentClick`, `SLASH_QUESTKOMPAS1/2`, `SlashCmdList.QUESTKOMPAS`. Onvermijdelijke uitzondering voor keybindings: `BINDING_HEADER_QUESTKOMPAS`, `BINDING_NAME_*` en de secure knop `QuestKompasItemButton1` (CLICK-binding vereist een naam).
7. Kleine commits, één onderwerp per commit.
8. Meld onzekerheid; lever nooit iets op als "getest" dat alleen tegen de stub gedraaid heeft.
9. Geen scope-uitbreiding: ideeën gaan in `IDEAS.md`.
10. Spelerstekst in het Nederlands in `Locales/nlNL.lua` (Engels in `enUS.lua`), zonder em-dash. Code, commentaar en identifiers in het Engels.

## Klaar melden
- `tools/check.sh` moet 0 luacheck-waarschuwingen en 0 falende tests geven.
- Nieuwe tekst: sleutel in beide taalbestanden met dezelfde `%`-plaatshouders (getest).
- Nieuw Lua-bestand: ook in `QuestKompas.toc` (getest).
