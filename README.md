# HLADINA: poolrooms tech demo (Godot 4.7, Forward+)

## Spuštění
- **SPUSTIT_HRU.bat**: při prvním spuštění naimportuje textury a zvuky (minuta až dvě), pak spustí hru.
- **OTEVRIT_V_EDITORU.bat**: otevře projekt v editoru Godotu (F5 = spustit).
- Godot 4.7.2 je přibalený ve složce `_godot`. Soubor `_godot/godot_linux_test.zip` můžeš smazat, sloužil jen k testování.

## Ovládání
| Klávesa | Akce |
|---|---|
| WASD, myš | pohyb, rozhlížení |
| Shift | běh / rychlejší plavání |
| Mezerník | skok |
| C (přepnout), Ctrl (držet) | přikrčení a plazení |
| F | svítilna na zbrani |
| V | VHS kamera |
| G | rybí oko |
| P | přepnutí první / třetí osoby |
| Q | pravé / levé rameno ve třetí osobě |
| R | přebít AK; bez zbraně ve třetí osobě otočit postavu do směru kamery |
| E | sebrat AK-47 |
| Levé tlačítko myši | automatická střelba |
| Pravé tlačítko myši (držet) | míření přes mířidla a přiblížení |
| Q / kolečko myši | úder pažbou (v první osobě) |
| Z, X | přivolat zombie na zkoušku, uklidit zombie |
| Esc | menu a nastavení (grafika, upscaling, kamera, zvuk) |
| F3, F11 | FPS, okno / celá obrazovka |

## Nové přechody zbraní a reakce na zásahy
- Přepnutí nejprve schová původní zbraň, model vymění mimo obraz a potom vytáhne novou.
  Během výměny nelze vystřelit; rychlé další přepnutí se zapamatuje.
- Doplnění neprázdného zásobníku je kratší a neobsahuje natažení závěru. Prázdná zbraň používá celé přebití.
  Dvojka si ponechává vlastní přebití se zlomením hlavní.
- Ruka má plynulejší dráhu při přebíjení a samostatnou korekci dosahu v první osobě.
- Nesmrtelný zásah lýtka krátce kopne bércem, zásah stehna pohne stehnem ve směru střely.
  Reakce odezní do původní animace; souběžné rány mají omezené úhly, aby klouby nepřetáčely.
- Kontroly: `res://tools/verify_fps_actions.gd` a `res://tools/verify_hit_reactions.gd` (Godot `--headless --path . --script ...`).

## Zombie režim (přežití po vzoru starých CoD Zombies)
Začíná sebráním AK-47 ve vstupní místnosti (mimo multiplayer). Zombie přicházejí v kolech:
polovina se vynořuje z hlubokého bazénu, zbytek přichází z míst, kam zrovna nevidíš.
S každým kolem jich je víc, víc vydrží a přibývají rychlejší typy.

- **Body:** 10 za zásah, 60 za zabití, 100 za zabití do hlavy, 130 za zabití pažbou.
- **Zdraví:** tři zásahy tě složí; po 4,5 s bez zásahu se zdraví samo doplní. Při nízkém je slyšet tep.
- **Munice:** 30 v zásobníku a 210 v zásobě. Když dochází, další zabitá zombie upustí MAX AMMO.
- **Bonusy:** MAX AMMO (zelený) a INSTA-KILL (červený) občas zůstanou po zabité zombie; stačí jimi projít.
- **Zásahy:** hlava ×4, trup ×1, noha ×0,75, ruka ×0,6. Dost ran do nohy ji odstřelí a zombie se plazí dál;
  smrtelná rána do hlavy zblízka hlavu roztrhne. Střela projde až dvěma těly.
- **Zombie umí:** obejít sloupy a bazén po navigační síti, přeplavat bazén, vylézt za tebou do průlezu.
- **Konec hry:** po smrti Enter spustí nové kolo 1 se zbraní v ruce.

Ladění je v `scripts/zombie_mode.gd` (velikost kol `ROUND_SIZES`, strop živých `MAX_ALIVE`, zdraví a typy
v `_make`) a `scripts/zombie.gd` (násobky zásahů `MULTIPLIER`, rychlosti `SPEEDS`, poškození `attack_damage`).
Zvuky zombie, znělky kol a výstřel jsou syntetické (`audio/zombie_*`, `round_*`, `ak_fire.wav`); nahrávky
se stejným názvem je nahradí.

Kontrola bez grafiky: `--headless --path . --script res://tools/t_game.gd` (kola, smrt, restart, střílející bot)
a `res://tools/t_reach.gd` (zombie dojde k hráči z každého výchozího místa).

## Hororová verze mapy
Všude je tma: světlíky propouštějí jen slabé měsíční světlo, voda je temná a svítí jen pár skomírajících
zářivek, podvodní světla bazénu a červené nouzové světlo. **F** zapíná svítilnu na zbrani (rybí oko je nově na **G**).
Jas jde doladit v Nastavení > Obraz.

- **Hala** má strop ve výšce 9 m a pod ním **galerie** (východní a severní stěna). Hráč se na ně nedostane;
  zombie z nich vycházejí z temných dveří a padají dolů do vody.
- **Šatny** (suché) východně od vstupní místnosti, s rampou dolů do haly: okruh vstup -> šatny -> hala.
- **Technická místnost** (zatopená, červené světlo) na západě: okruh chodba -> technická -> hala.
- **Připravená místa** (zatím jen bedna s popiskem a světlem, funkce `_spot` v `main.gd`):
  TAJEMNÁ BEDNA v šatnách, MUNICE a TAJNÝ PRŮCHOD v technické místnosti.
- Místa, odkud zombie chodí, jsou v `zombie_mode.gd`: `WALK_SPAWNS`, `LEDGES` (galerie) a `POOL`.

## Multiplayer (první kooperativní test)
V menu **Multiplayer** může jeden hráč hostovat a ostatní se připojit přes IP/LAN/VPN.
Až 4 hráči se navzájem vidí včetně plynulého pohybu, animací, skoků, otočení,
plavání, zvuků kroků a vln od hráčů. Sebrání vzorkovnice potvrzuje host pro všechny;
pozdější připojení přebírá její aktuální stav. Esc ponechá společnou hru běžet.

Balíček k poslání je v `dist/Hladina-Multiplayer-v0.1.zip`. Návod je uvnitř ZIPu
v `CTI-ME-MULTIPLAYER.txt`. Oba hráči spustí `Hladina.exe` ze stejné rozbalené verze.
Výchozí port je **UDP 24567**. UPnP zkouší automatické otevření portu; při CGNAT
je potřeba veřejná IP nebo společná VPN. Provozní internetový relay tato verze nemá.

Pohyb vlastní klient, host ověřuje formát a předává snímky ostatním 20× za sekundu.
Vzdálená postava používá 100ms vyhlazovací buffer a stejný animační graf jako hráč.
Jednorázové akce běží spolehlivým kanálem; snímky a vlny samostatnými UDP kanály.
Vlastní tělo zůstává na vrstvách 4/8, cizí celá postava má vrstvu 16 viditelnou
z obou kamer. Vzájemné fyzické blokování hráčů není v tomto testu zapnuté.

Síťový test: `--headless --path . --script res://tools/verify_network.gd`.
Regrese těla a animací: `--headless --path . --script res://tools/verify_body.gd`.
Přebalení po změnách: `tools/build_multiplayer_pack.ps1` (Windows PowerShell).

Z bazénu vylezeš tak, že plaveš proti okraji.

Voda nikde samovolně nekape. Vlny vytváří pouze hráč při brodění, plavání,
krocích a dopadu do vody; po zastavení přirozeně dobíhají a utichají.
Nehybné šlapání vody ani automatické detaily shaderu nové vlny nevytvářejí.

Ve vstupní místnosti leží pár kroků před startem vpravo AK-47.
Přibliž se na 1,35 m: objeví se **E — Sebrat AK-47**. Při zvednutí se na chvíli
zastaví pohyb, předmět zmizí při kontaktu ruky a objeví se potvrzení. Přes stěnu
sbírat nejde. Nová hra AK obnoví a odebere hráči zbraň.

## Obraz a kamera
- **Nastavení > Obraz > Kontrast / Gama**: hodnota 1.00 je neutrální. Vyšší kontrast
  prohloubí stíny a zvýrazní světlá místa; nižší gama ztmaví střední tóny.
  Pro tmavší obraz zkus kontrast 1.12 a gamu 0.92. Jas dál ovládá expozici.
- **Nastavení > Kamera > Síla rybího oka**: rozsah 0–1, výchozí 0.35.
  F efekt zapíná a vypíná; nastavená síla zůstává uložená. Zkreslení je nově
  normalizované podle úhlopříčky, takže na širokém monitoru nezesílí.
- **Filmový pohyb kamery**: výchozí 0.65, nula vypne dodatečnou setrvačnost.
  Kamera jemně doznívá při otáčení, rozběhu, zastavení a krocích. Pohled myší
  reaguje přímo. Houpání a třes mají dál vlastní posuvníky.
- Všechny tyto hodnoty se ukládají spolu s ostatním nastavením.
- **Nastavení > Kamera > Perspektiva** nebo **P** přepíná pohled. Záložka **3. osoba**
  nastavuje vzdálenost, odsazení, výšku, rameno, zorné pole a plynulost návratu kamery.
  Kamera testuje prostor kouli proti stěnám a stropu. U velmi blízké překážky a v nízkém
  průlezu dočasně přejde do první osoby; ve volném prostoru se třetí osoba zase obnoví.
- Ve třetí osobě při stání myš pouze obíhá kamerou kolem postavy. Postava drží poslední
  směr; po rozcházení se plynule otočí do směru pohybu. WASD zůstává relativní ke kameře.
- **R** přehraje dodané otočení na místě a natočí postavu do aktuálního směru kamery.
  Samotný orbit myší dál drží postavu v klidu. Rozběhnutí otočení plynule přeruší.
- V první osobě při stání spouští otáčení myší automaticky přešlapování z klipu
  Turning. Kroky se opakují po celou dobu otáčení, reagují na jeho směr a rychlost
  a po zastavení myši plynule přejdou do klidu.
- Výška ramenní kamery při přikrčení i vstávání plynule sleduje přechod postoje.
- **Mezerník** spouští dodaný skok, jehož let a dokončení dopadu se řídí skutečným
  odrazem a kontaktem s podlahou. Animace nepřidává druhý posun celé postavy.
- Boční klipy Left/Right Strafe se používají pouze při **Shift + A/D** (také diagonálně).
  Samotné A/D používá běžnou chůzi; přikrčení a plavání si ponechávají vlastní animace.

## Co je uvnitř
- `assets/scientist/`: dodaný modrý scientist, textury, původní FBX klipy a připravená knihovna animací.
- `scripts/player_body.gd`: směrové prolínání pohybu, skok, otočení a zvednutí předmětu.
- `scripts/pickup_prop.gd`: testovací vzorkovnice s indikací dosahu; interakci řídí `main.gd`.
- `tools/build_first_person.gd`: celé tělo pro vlastní pohled s uzavřeným řezem u krku, se zachováním trupu, paží, výbavy a vah osmi kostí.
- `tools/verify_body.gd`: kontrola, že vlastní pohled obsahuje trup a obě paže a že se kosti při přehrávání všech pohybů skutečně mění v čase.
- `shaders/light_shaft.gdshader`: objemové paprsky tvarované podle světlíků a jejich příček, s měkkými okraji.
- `scripts/main.gd`: stavba úrovně (všechno je z kódu, rozměry v metrech), světla, prostředí, postproces, UI.
- `scripts/water_sim.gd`: simulace hladiny v compute shaderu (vlnová rovnice 2048 x 2048, vlny se odrážejí od stěn a sloupů).
- `scripts/player.gd`: pohyb, brodění, plavání se vztlakem, plazení a kamera.
- `scripts/sfx.gd`: zvuky, ambient a dozvuk podle místnosti.
- `shaders/water.gdshader`: lom, absorpce barvy podle hloubky, planární odraz, Fresnel.
- `shaders/tile.gdshader`: dlaždice, kaustiky, vodní kámen, mokrý pás.
- `shaders/post.gdshader`: VHS, rybí oko, vinětace, zrno, chromatická aberace.

## Ladění vzhledu (nejrychlejší páky)
- Jas a nálada: `sun.light_energy`, `env.sdfgi_energy`, `cam_attr.auto_exposure_scale` v `main.gd`.
- Světelné kužely: `env.volumetric_fog_density` a `sun.light_volumetric_fog_energy`.
- Barva vody: `absorb` a `scatter_color` ve `water.gdshader`.
- Živost hladiny: `wave_c2` a `damping` ve `water_sim.gd`, síly impulsů v `player.gd`.

## Výměna textur a zvuků
Textury ve složce `textures` jsou generované procedurálně ve 4K. Když je nahradíš skenovanými
(stejné názvy souborů), projekt je použije bez dalších úprav:
- `tiles_albedo.png`: barva
- `tiles_normal.png`: normálová mapa ve formátu OpenGL (na ambientCG soubor `NormalGL`)
- `tiles_orm.png`: R = ambient occlusion, G = roughness, B = výška (displacement)

Textura má pokrývat 8 x 8 dlaždic. Pokud má jiný počet, uprav `tiles_per_tex` a `tex_world`
v `tile.gdshader`. Zdroje zdarma (CC0): ambientcg.com a polyhaven.com, kategorie Tiles, rozlišení 4K.

Zvuky ve složce `audio` jsou syntetické. Nahrávky skutečné vody je nahradí pod stejnými názvy
(`drip_1..6`, `step_water_1..6`, `step_tile_1..6`, `swim_1..4`, `splash_big_1..2`, `amb_*`).

## Výkon
V **Nastavení > Obraz** je **Měřítko rozlišení 50–200 %** a **Limit FPS** (neomezeně nebo 30–360 FPS).
Pohyb posuvníku přepne vykreslování na vlastní měřítko s TAA; 200 % vykresluje dvojnásobek
šířky i výšky, tedy čtyřnásobek pixelů. Menu zůstává v rozlišení okna. Volba přednastaveného FSR
nebo grafické kvality zase nastaví odpovídající měřítko. VSync může snímkovou frekvenci omezit dál.
V **Nastavení > Grafika** je také **Síla světelných paprsků**; vypnutí volumetriky vypne i nové paprsky.

Demo míří na výkonnou grafickou kartu. Když je FPS nízko, v Nastavení > Grafika zvol nižší kvalitu
nebo v Nastavení > Obraz zapni FSR 2.2 (kvalita / vyvážený).

## Příprava modelu
Vlastní pohled obsahuje trup, obě celé paže, nohy a výbavu. Skrytá je hlava a s ní propojená výbava včetně hadic; řez
u krku je uzavřený. Tělo se při přikrčení ani plavání neskrývá. Kamera se umisťuje před
aktuální animovanou polohu hlavy a kontroluje kolize se zdmi a stropem. Póza se vyhodnotí
před kamerou, takže při pohybu nevzniká zpoždění mezi tělem a objektivem.
Třetí osoba, stíny a odraz používají celý původní model včetně hlavy.
Pohyb světem řídí kolizní tělo; posun kořenové kosti v X/Z je odstraněný, aby animace
neodjížděla od hráče. Úkroky se řídí směrem pohybu, vodní klipy rychlostí plavání.
Přikrčení i vodní pohyby používají dodané klipy. Směrový graf má explicitní trojúhelníky
a nezávislé časování vnořených blendspace; tím se zamezí zastavení času běhových klipů.
Smyčky jsou uzavřené. Picking Up je zkrácený na 1,8 s a napojený na skutečné sebrání
testovacího předmětu. Jumping a Turning mají odstraněný vodorovný kořenový posun
a natočení; pohyb světem i směr řídí hráč.
Po výměně zdrojových FBX lze připravené prostředky znovu vytvořit:
`_godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/build_scientist.gd`

`_godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/build_first_person.gd`

Kontrola těla a animací:
`_godot\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/verify_body.gd`

## AK-47 (první a třetí osoba)
AK nahrazuje původní vzorkovnici. Po sebrání se zobrazí zbraň i stav zásobníku.
LMB střílí dávku při držení (600 ran/min), RMB plynule přisune zbraň k mířidlům
se zúžením zorného pole. R přehraje 2,2s přebití pohybem levé ruky a zásobníku.
Zásobník má 30 ran; zásoba nábojů je zatím neomezená, při prázdném zásobníku
další stisk/spuštění střelby zahájí přebití. Střely používají raycast proti mapě,
zanechávají nejvýše 40 značek zásahu, mají zvuk, záblesk a zpětný ráz.
Ve vstupní místnosti je testovací zombie; poškození ostatních hráčů zatím není přidané.

`scripts/weapon_rig.gd` řeší obě paže po vyhodnocení pohybových klipů.
Délky kostí zůstávají zachované, ramena se předsunují a při krajním pohledu se
zbraň přitáhne do dosažitelného prostoru. Nohy dál používají původní chůzi,
běh, skok a přikrčení. Při plavání se zbraň schová a střelba je blokovaná.
Celé vlastní tělo zůstává zachované. Zbraně používají stejné vrstvy viditelnosti
jako tělo (4/8 pro místního hráče, 16 pro vzdálenou postavu).

Držení a míření se přenášejí ve snímcích multiplayeru, výstřel a přebití jako
spolehlivé události. Starý ZIP v0.1 tuto změnu neobsahuje; po změnách je potřeba
znovu sestavit balíček a všem hráčům poslat stejnou verzi.
Příprava modelu: `--headless --path . --script res://tools/build_ak.gd`.
Kontrola póz: `--headless --path . --script res://tools/verify_weapon.gd`.

Oprava klipování vlastního pohledu: výbava hlavy se při přípravě mesh odstraňuje
po celých propojených dílech, aby pod řezem nezůstávaly otevřené hadice.
Každý samostatný okraj řezu má vlastní víčko a vlastní váhy kostí.
První osoba má oddělenou kopii kostry se zachovaným celým tělem. Její ruce a AK
se dorovnávají k předsazenému objektivu; ramena tak nevstupují do obrazu při
sprintu a pohledu dolů. Třetí osoba i odrazy dál používají původní celý model.

## Testovací zombie
Ve vstupní místnosti před schody stojí dodaný Warzombie (vlevo, zhruba za místem,
kde se sbírá AK). FBX obsahuje pouze jednokusovou statickou pózu; hra přidává
uvolněné paže, jemné dýchání a pohyb hlavy. Zombie se zatím nepohybuje po mapě
ani neútočí. Tělo má 100 HP, zásah do těla ubere 40, zásah hlavy zabije ihned.
Paprsek z AK respektuje geometrii mapy a zasahuje hitboxy jednotlivých částí.

Po smrti se zastaví idle a zapne PhysicalBoneSimulator3D se 17 fyzikálními
částmi (trup, krk, hlava, paže, ruce, nohy a chodidla). Části drží klouby,
kolena mají omezené jednoosé ohýbání, tělo reaguje na podlahu a místo zásahu.
Další výstřely mohou do mrtvého těla strčit. Nová hra zombíka obnoví.
Ve společné hře vyhodnocuje zásahy host a spolehlivě oznamuje smrt klientům;
samotný pád si počítá každý lokálně, takže přesná poloha mrtvoly se může lišit.
Kontrola fyziky: `--headless --path . --script res://tools/verify_zombie.gd`.

## Zdroje zvuků (skutečné nahrávky)
- `step_tile_*`, `amb_water`, `amb_room`: Oculus Audio Pack, Meta Platforms — CC BY 4.0
  (github.com/facebookincubator/Meta-open-sound, corpora/oculus-audio-pack)
- `step_water_*`, `swim_*`, `splash_big_*`: odvozeno z „water footsteps“ od AGFX (freesound.org/people/AGFX/packs/1253) — CC BY 3.0,
  převzato z balíčku luanti-org/minetest_game
- `ak_fire`: zvuk výstřelu dodaný autorem hry, doplněný o basový úder a dozvuk haly

## Zvuky zbraní a zombíků (přidáno)
- MP 40, Desert Eagle, IŽ-54 (výstřely a přebíjení): AssaultCube (github.com/assaultcube/AC), zvuky od makkE – licence AssaultCube, ověřit před komerčním použitím.
- Zombíci (vrčení, útok, smrt): Freedoom (github.com/freedoom/freedoom), BSD licence, upraveno (nižší tón, filtr).

## Předměty (Sketchfab, autoři dle stažených balíčků)
Weapon Crate, Locker Equipment, Ammo Box, Visible Interactive Human Exploding Skull, Pumpkin Grenade,
Stylized Weapons Workbench, Syringe Gun – Dirty. Před zveřejněním doplnit autory a licence ze Sketchfabu.

## Karanténní pokoj (lobby)
Hráčův pokoj ve starém sanatoriu (`lobby.tscn`, `scripts/lobby.gd`), z menu tlačítkem **My room**, Esc vrací do menu.
Hráčův pokoj 7 (postel, komoda s televizí, gauč, stůl s rádiem, umyvadlo se skutečným zrcadlem, skříňka,
nástěnka a polička jako sloty na odemčené věci) v křídle sanatoria (`scripts/lobby_wing.gd`): chodba s lavičkami,
nástěnkou a blikající zářivkou, pokoje 8 (opuštěný), 9 (zamčený) a 10 (vyrabovaný), společné WC a umývárna
s kabinkami, sesterna za okénkem se žaluzií, společenská místnost (pingpong, televize, knihovna, automat)
a schodiště dolů zamčené mříží. Dveře se otvírají klávesou E.

**Úpravy mapy v editoru:** mapa je normální scéna `maps/lobby_map.tscn` (je vložená i v `lobby.tscn`).
Otevři ji v Godotu a posouvej, maž a přidávej uzly. Složky odpovídají místnostem (Pokoj_7, Chodba, WC_umyvarna,
Spolecenska_mistnost…), `Prostredi` obsahuje světlo a oblohu, `SpawnHrace` je místo, kde se hráč objeví.
Chytré uzly (scripts/lobby/): `Dvere` (stav closed/open/ajar/locked, popisek), `DvereJednokridle` (šířka, otevření),
`Zarivka` (síla, stín, ok/flicker/rare/dead), `Zrcadlo` (velikost), `Interakce` (text a akce pro klávesu E).
Nový nábytek: přetáhni `.glb` z `assets/` do scény. `tools/bake_lobby.gd` mapu vygeneruje znovu kódem –
**přepíše tím ruční úpravy**, používej jen pro start od nuly.
Autoři modelů (CC BY 4.0): `assets/lobby/CREDITS.md`. Náhledy: `--script res://tools/t_lobby_shots.gd`.

## Úpravy hlavní mapy v editoru
Lázně jsou normální scéna `maps/main_map.tscn`. Složky odpovídají částem (Hlavni_lazne, Vychodni_kridlo, Cisterna,
Zachody, Zapadni_sprchy, Severni_kridlo, Jizni_kridlo, Detaily_bazenu…). Každá zeď nese svou kolizi (uzel `Kolize`),
takže se posouvají spolu; ve hře se kolize i zdi pro výkon slijí. Lampy (`Svetlo_lampa`) blikají podle metadat.
Voda, světlíky a barvy podlah jsou data v uzlu `DataMapy` (inspektor) – když posuneš bazén, uprav i jeho obdélník.
Modré plochy ve složce `Voda_nahled` jsou jen náhled hladin pro editor. Za běhu kód přidává: měsíc, pár lamp,
podvodní světla, vodu, krev a nepořádek (náhodně), vzkazy, rozhlas, úkoly a zombíky.
`tools/bake_main.gd` mapu vygeneruje znovu kódem – **přepíše tím ruční úpravy**.

## Bažina (prototyp nové mapy)
Menu → **The swamp (prototype)**, scéna `swamp.tscn`, kód `scripts/swamp.gd`. Noc, déšť, mlha a tma, vidět je jen
kam svítí baterka (F). Všude kalná voda po kolena, ostrůvky, hlubší tůně, suché stromy, keře, rákos a kameny.
Mapa se při každém spuštění vygeneruje jinak (pevný seed pro test: proměnná prostředí `SWAMP_SEED=123`).
Od místa výsadku vede k polozatopenému sovětskému bunkru rozpadlá lávka a cedule; bunkr je poznat podle červeného světla.
Bouřka (blesk a hrom v dálce) se vypíná konstantou `THUNDER` nahoře v `swamp.gd`.
Test boje (`scripts/swamp_waves.gd`): AK-47, MP 40, IŽ-54 a Desert Eagle (1–4 nebo kolečko, nekonečná zásoba),
vlny zombie z hlavní hry (kola, víc a rychlejší), zdraví hráče, po smrti znovu od 1. kola. `SWAMP_DEBUG=1` vypisuje stav kol.
Bažinák (`scripts/swamp_alpha.gd`, test alfy): po ~1 minutě se vynoří ve tmě za hráčem a hýbe se, jen když se na něj
nedíváš. Zamrzne, když je v záběru a nezakrytý a zároveň na něj svítí baterka, blýskne se nebo je blíž než 4,5 m.
Plíží se po navigaci a čvachtá. U hráče udeří (45), ponoří se a vynoří se jinde. Má 2400 HP a po každé ztracené třetině uteče pod hladinu;
zabitý padne do bahna. `SWAMP_ALPHA_T=3` = vynoří se hned (test).
V bažině je od začátku zapnutá bodycam (B), VHS kamera (V) a hledí helmy: déšť na něj postupně napadá
(za ~40 s je celé pokapané) a otírá se klávesou H (ruka přejede po skle, pak začne pršet na čisté). Stromy, keře a kameny mají shader mokré vegetace
(`shaders/swamp_foliage.gdshader`: přebarvení, lesk a kapky deště, prosvítání listů, vítr). Autoři modelů: `assets/swamp/CREDITS.md`.
