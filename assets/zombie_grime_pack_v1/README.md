# Zombie Grime Pack v1

24 realistickych motivu spiny pro zombie / opustene prostredi. PNG RGBA se skutecnou pruhlednosti.

- **mud_dust:** hlina, mokre blato, spinavy otisk ruky, stopa boty, otisk pneumatiky, zaschle blato, prachova smouha, kapky blata.
- **oil_soot:** olejova skvrna, mastne kapance, tah maziva, mastny otisk ruky, saze, kourova stopa, mastny kruh, setrene mazivo.
- **rust_mold:** rez, rezave stekance, oxidace, zelena plisen, cerna plisen, vlhka skvrna, rasy/sliz, mineralni usazenina.

## Obsah

- `atlases_4k/`: 3 atlasy, kazdy 3840 x 2160 px, mrizka 4 sloupce x 2 radky. Bunka 960 x 1080 px.
- `individual/`: 24 samostatnych PNG vyrezu v puvodnim rozliseni, kazdy 418 x 470 nebo 418 x 471 px. Poradi zleva doprava, nejprve horni radek.
- `originals/`: neupravene zdrojove atlasy 1672 x 941 px.
- `previews/`: JPEG nahledy na sedem pozadi pro kontrolu pruhlednosti; nejsou to decal textury.
- `manifest.json`: rozmery a souradnice motivu.
- `PROMPTS.json`: uplne prompty; pouzit vestaveny nastroj image_gen.

**4K atlasy jsou bicubicky zvetsene ze zdroju 1672 x 941 px. Nejde o nativni 4K detail. Samostatne PNG jsou vyrezy v puvodnim rozliseni.**

## Pouziti

Pro obrazove overlaye pouzij standardni alpha blending. V Godotu lze PNG pouzit jako texturu Sprite2D nebo jako Albedo pro 3D Decal. RGB v temer pruhlednych pixelech se muze lisit; vzdy zobrazuj s alfa kanalem. JPEG nahledy ukazuji bezne slozeni pres podklad.

Herni sceny nejsou touto sadou upravene.
