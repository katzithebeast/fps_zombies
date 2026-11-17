# Wall Damage Pack v2 — zombie horror

Celkem 56 realistických motivů pro zdi: původních 24 a 32 nových. PNG RGBA se skutečnou průhledností.

## Nových 32 motivů

- **exp_cracks_tiles (8):** čtyři další praskliny a čtyři místa s vypadanými či rozbitými kachlemi; obnažené lepidlo, malta a zbytky keramiky.
- **exp_mold (8):** černá, olivová a vláknitá plíseň, zateklé kolonie, bakteriální film a drobná ložiska.
- **exp_blood_vomit (8):** krvavý cákanec, zaschlá krev, tažený otisk ruky, krvavé stékance, zvratky, zaschlé zbytky, žlučová skvrna a směs tekutin.
- **exp_strange_growth (8):** černý maz, sliz, podivné podhoubí, krusty, jantarové průsaky a hnilobné nánosy.

Původních 24 motivů: škrábance, odřeniny, plíseň, vlhkost, praskliny a oloupaná barva.

## Obsah

- individual/: 56 samostatných PNG v původním rozlišení, 418 × 470 nebo 418 × 471 px.
- atlases_4k/: 7 atlasů 3840 × 2160 px; mřížka 4 sloupce × 2 řádky, buňka 960 × 1080 px.
- originals/: 7 vybraných zdrojových atlasů 1672 × 941 px.
- previews/: 7 JPEG náhledů na šedém podkladu; náhledy nejsou průhledné textury.
- manifest.json: úplný seznam motivů, rozměry a souřadnice výřezů.
- PROMPTS.json, MOLD_EDIT_PROMPT.txt, PROMPTS_EXPANSION.json: úplné generovací a editační prompty. Použit vestavěný nástroj image_gen.

**4K atlasy jsou bicubicky zvětšené ze zdrojů 1672 × 941 px. Nejde o nativní 4K detail. Samostatné motivy jsou výřezy v původním rozlišení.**

## Použití

Překryj stávající texturu zdi se standardním alpha blendingem. V Godotu lze PNG použít jako Albedo pro 3D Decal nebo jako texturu Sprite2D. Odloupnuté kachle a omítka obsahují vlastní barvu keramiky a malty; přizpůsob odstín okolní zdi.

Motivy obsahují barevné informace a alfa kanál; pro správný náhled vždy respektuj průhlednost. Herní scény nebyly upravené.
