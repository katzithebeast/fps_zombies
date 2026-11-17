# Průchod kvalitou — 16. 11. 2026

Záloha původních souborů: `_backups/quality_pass/`.

- Menu: nový tmavý vzhled, animovaný jemný vodní stín, nástup titulu, čitelný fokus klávesnice, škálování podle obou rozměrů okna. Původní nastavení a multiplayerové akce zůstávají dostupné.
- Zbraně: omezená setrvačnost při změně rychlosti ve společné póze obou rukou, potlačená při ADS. Nastavení rázu platí už pro právě vypálenou ránu, včetně náklonu kamery. Kontrola překážky mezi kamerou a ústím.
- Zombie: svižnější přechod do útoku, plynulá obnova pohybu po zásahu; tempo klipu odpovídá zpomalené chůzi. Blízké živé zombie mají prostorové kroky.
- Ragdoll: přenos omezené lineární a úhlové rychlosti jednotlivých kostí z poslední živé pózy. Energie závisí na zbrani, boční náhodný odhoz je omezen a zásah nohy nepřidává stejný odhoz trupu jako zásah hrudi. Anatomické limity a stabilizace zůstaly zachované.
- Zvuk: bez okamžitého opakování téže nahrávky; volné prostorové hlasy se využijí před přerušením již hrajících. Zdi ztiší a ztlumí prostorové zvuky, kontrola má pevný rozpočet 3 paprsků / 80 ms.
- Atmosféra: delší mezery mezi náhodnými hrozbami, jejich časovače ustupují boji. Temná podkladová plocha má pomalé změny hlasitosti a menší maximální úroveň.

Ověření: `tools/verify_fps_actions.gd`, `tools/verify_body.gd`, `tools/verify_hit_reactions.gd`, `tools/verify_zombie.gd`, `tools/verify_quality_pass.gd`; grafický scénář `_backups/quality_pass/game_test.gd`, menu `_backups/quality_pass/preview.gd`. Logy a náhledy jsou v záloze tohoto průchodu. Zvuková kontrola je technická (směrování, útlum, výběr hlasů); finální poslechový mix je potřeba ladit s hráčem.

Toto je průchod existujícími systémy, nikoli kompletní náhrada všech animací motion capture ani hotová AAA hra. Další velké kroky: originální ruční/finger animace zbraní, další útoky a chůze zombie, animované interakce, fyzické reakce na schody a stěny, jednotná výtvarná úroveň modelů a dlouhé herní testy. Staré varování o chybějících tangentách modelů a zdrojích při ukončení hry zůstává samostatnou technickou prací.
