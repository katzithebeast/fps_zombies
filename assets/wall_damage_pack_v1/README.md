# Wall Damage Pack v1

24 realistickych decal motivu pro zdi opustenych budov: poskozeni, spina a vlhkost. PNG RGBA s pruhlednosti.

- **wall_scratches:** diagonalni skrabance, vodorovne odreni, hlubsi ryhy, jemne skrabance, osoupani, svisle ryhy, vetvena ryha, odrena barva.
- **wall_mold_damp:** cerna plisen, zelena plisen, seda plisen, zatekani, vlhka mapa, spinave stekance, silna plisen se stekanci, solny vykvet.
- **wall_cracks_peeling:** svisla prasklina, sit jemnych prasklin, diagonalni prasklina, oloupana barva, svisly pruh loupajici se barvy, vydrolena omitka, naraz s prasklinami, popraskany nater.

## Soubory

- `individual/`: 24 samostatnych PNG vyrezu v puvodnim rozliseni, 418 x 470 nebo 418 x 471 px.
- `atlases_4k/`: tri atlasy 3840 x 2160 px, mrizka 4 sloupce x 2 radky. Jedna bunka 960 x 1080 px.
- `originals/`: tri neupravene zdrojove atlasy 1672 x 941 px.
- `previews/`: JPEG nahledy na sedem pozadi; slouzi ke kontrole vzhledu, nepouzivat jako pruhledne textury.
- `manifest.json`: seznam motivu, jejich rozmery a souradnice vyrezu.
- `PROMPTS.json`: uplne prompty pro vestaveny nastroj image_gen.

**4K atlasy jsou bicubicky zvetsene ze zdroju 1672 x 941 px; nejde o nativni 4K detail. Samostatne motivy jsou v puvodnim rozliseni.**

## Pouziti

Motivy pouzij jako tenkou vrstvu pres stavajici texturu zdi se standardnim alpha blendingem. V Godotu lze pouzit jako Albedo pro 3D Decal nebo jako texturu Sprite2D. Odreni a oloupana barva obsahuji vlastni svetle a sede odstiny; prizpusob odstin a pruhlednost podkladove zdi. Jedna se o barevne textury s alfa kanalem.

Pro spravny nahled vzdy respektuj alfa kanal; barevna data temer pruhlednych pixelu nejsou samostatnym pozadim. Herni sceny nebyly upravene.
