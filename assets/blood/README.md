# Zombie Blood Pack v1

24 krvavych motivu pro zombie / horror grafiku, PNG RGBA s pruhlednosti.

- 8 cakancu: radialni zasah, vodorovny rozstrik, diagonalni zasah, jemna mlha, velky strikanec, kapky, dvojity zasah a stopa kapek.
- 8 motivu otisku rukou: plne i castecne dlane, otisky s tahem a rozmazane otisky.
- 8 smouh: vodorovne a diagonalni tahy, svisle setreni, stekajici krev, kapka, louze, obloukovy tah a zaschla krev.

## Soubory a skutecne rozliseni

- `atlases_4k/`: tri atlasy, kazdy presne **3840 x 2160 px**, mrizka 4 sloupce x 2 radky. Kazda bunka ma 960 x 1080 px.
- `individual/`: 24 samostatnych PNG vyrezu v puvodnim rozliseni, kazdy 418 x 470 nebo 418 x 471 px. Rada cislovani: zleva doprava, nejdrive horni radek.
- `originals/`: tri neupravene zdrojove PNG, kazdy 1672 x 941 px.
- `manifest.json`: seznam motivu, rozmery a souradnice vyrezu.
- `PROMPTS.json`: uplne generacni prompty. Pouzit byl vestaveny nastroj image_gen.

**4K atlasy jsou bicubicky zvetsene ze zdroju 1672 x 941 px. Nejde o nativne vygenerovany 4K detail.** Samostatne motivy jsou vyrezy z puvodnich atlasu, ne samostatne 4K textury.

## Pouziti

PNG obsahuji skutecny alfa kanal; pozadi neni soucasti motivu. Pro overlaye nastav standardni alpha blending. V Godotu lze PNG pretahnout do textury Sprite2D; pro 3D Decal pouzit jako Albedo a upravit velikost projekce. Soubor manifest.json uvadi take obdelniky bunek 4K atlasu.

Pack je ulozen jako nova samostatna sada; scena hry nebyla upravena.
