# Milo: avslutad designgranskning och placering

2026-09-12. Fortsättning på Claude-konversationen **avatarMilo integration across app**.

## Vad de tolv agenterna kom fram till

Alla resultat hade sparats: fyra layoutgranskningar, fem alternativa designsystem och tre bedömningar. Underlaget finns i Claudes lokala workflow `wf_c353d109-445`, session `718ba285-0414-4527-8a1e-089f512da62e`, i `journal.jsonl` under sessionens `subagents/workflows`.

| Förslag | Bedömare 1 | Bedömare 2 | Bedömare 3 | Medel |
| --- | ---: | ---: | ---: | ---: |
| Snittet — gränssnittet står framför Milo | 9 | 8 | 8,5 | 8,5 |
| Milos golv — the floor system | 7,5 | 7,5 | 8 | 7,7 |
| Horisonten — Milo stiger vid ankomst, sjunker när du jobbar | 6,5 | 6,5 | 7 | 6,7 |
| Rampljus — Milo på scenkanten | 8 | 4 | 6 | 6,0 |
| Golvet — Milo kommer in, spelar, och går ut | 7 | 5,5 | 5 | 5,8 |

Poängen är agenternas designbedömningar, inte användartestresultat. Alla tre valde Snittet, men föreslog delar från de andra systemen.

De viktigaste gemensamma fynden:

- En helfigur i 64 punkter är oläslig. Små ytor behöver ett porträtt, större ytor kan bära kroppen.
- Chatten betalade för stort navigationshuvud, separat Milo-huvud, statusblock och porträtt på varje svar. Samtalet fick för lite plats.
- `MiloPeek` kapade silhuetten nära halsen. Kortkanten behöver i stället passera över axlarna, med mindre transparent marginal ovanför huvudet.
- Meningsövningarnas fria yta varierar med ordlängd, ledtrådar, återkoppling och textstorlek. En fast figur ovanpå nederkanten kan täcka text eller hamna bakom flikraden.
- Laddningsrader skapade en andra livefigur på flera skärmar.
- Porträttkomponenternas `onDisappear` stoppade talet. Det gjorde bland annat att tangentbordets öppning avbröt uppläsningen i chatten.

## Påståenden som korrigerades mot koden

Några agenter drog slutsatsen att glad, nyfiken och framåtlutad Milo saknade visuell reaktion eftersom de delar `Idle_Watching`. Det stämmer inte: `MiloAnimation.swift` lägger egna ansiktsuttryck, huvudvinklar och överkroppsrörelser ovanpå grundklippet. De befintliga uttrycken behålls.

Formlerna för exakt huvudstorlek var uppskattningar som bedömarna själva var oense om. De används inte som ett löfte om en viss huvudstorlek; placeringarna granskas i simulatorn.

Att `MiloAssets.isWarm` är sant gör inte en ny rigg gratis. Kloning och uppbyggnad av scenen återstår. Därför införs ingen ständig in/ut-animation, timerstyrd närvaro eller rigg som återskapas vid varje scrollrörelse.

## Genomfört

- **Chatten:** en beständig 44-punkters porträttrad med sammanhang och ljudkontroller, kompakt navigation och en smal förloppsindikator. Avsluta/sammanfatta ligger i verktygsraden. Meddelanden behåller avsändarens namn men inte en separat bildrad. Milo är stilla här för att ge läsningen arbetsro; större reaktioner finns i övningarna och sammanfattningen.
- **Lek och repetera / Bygg meningen:** `MiloPracticeCanvas` mäter själva innehållet, utan figuren. En 260-punkters helfigur eller 152-punkters byst, beskuren till 121,6 punkters höjd använder bara återstående yta inom den säkra vyn. Om inget utsnitt ryms utelämnas figuren. Innehållets position beror inte på Milo. Stor tillgänglighetstext får hela utrymmet.
- **Hälsningskortet på hemsidan:** en större, direkt inklippt Milo i kortet. Figuren renderas i 188 punkter och beskärs till 140 × 156, utan extra padding runt bilden. Texten har egen liten indragning.
- **Kort, lektionsöversikt och Mitt lärande:** större, axelbeskurna porträtt bakom kortkanten. Mitt lärande använder en stillbild under läsning.
- **Pronomenspelet:** Milo presenterar introduktionskortet och reagerar vid själva frågekortet. Den lilla livefiguren i poängraden tas bort.
- **Ordkort:** större utsnitt bakom kortleken, större figur när rundan är klar och scrollreserv när innehållet inte ryms på höjden.
- **Laddning och små signaturer:** laddningsrader använder stillbilder och kan därför aldrig skapa en andra rigg. Små signaturer har förstorats eller tagits bort när namnet redan räcker.
- **Livscykel:** skärmen äger stopp vid navigering/bakgrund. Att ett porträtt försvinner får inte avbryta pågående uppläsning.
- **Onboarding:** språkvalets hälsning och lokala uppläsning behålls. Promenaden är begränsad till tillräckligt stora helfigursytor.

Cirkeln används sparsamt: i chattens lilla identitetsmarkör och i den uttryckligen runda avatarstudion. Övriga placeringar använder Milos naturliga silhuett. I Bygg meningen fortsätter kroppen ned bakom flikraden enligt önskemålet, med huvudet kvar på samma plats och i samma storlek. Endast den dekorativa figuren får gå utanför nedre safe area; den tar inga tryck. Inga figurer täcker övningens knappar eller ordbrickor. Riggstorlek och zoom interpoleras inte vid scrollning.

## Verifiering

Se `Art/Milo/Validation/2026-09-12-placement/README.md` för byggresultat, verifierade interaktioner och skärmbilder. `MiloPlacementPreview.swift` ger reproducerbara DEBUG-vyer med studier i minnet och separat inställningsprofil. De hämtar inga modellgenererade svar vid start.
