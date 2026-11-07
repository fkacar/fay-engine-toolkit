# Fay Engine Toolkit

Haxe + Heaps ile yazılan 3D oyunlarımızın ortak sahne altyapısı ve editörü.

| Klasör | İçerik | Nereye girer |
|---|---|---|
| `runtime/` | Sahne formatı, bileşen modeli, kalıcı kimlikler, `@:editable` macro'su | Oyun ve editör |
| `editor/` | Docking kabuğu, Hierarchy, Inspector, komut sistemi | Yalnızca `-D scene_editor` derlemesi |
| `tests/` | Testler | Hiçbiri |
| `template/` | Yeni oyun için başlangıç projesi | Yeni proje |
| `tools/` | Çalıştırma, `hlimgui` derleme ve proje oluşturma script'leri | Hiçbiri |
| `vendor/hashlink/` | Mac için sabit HashLink kitaplıkları | Mac derlemesi |
| `third_party/hlimgui` | Commit'e sabit Dear ImGui binding'i | Editör |

## Yeni oyun

```sh
sh libs/scene-toolkit/tools/new-project.sh ../yeni-oyun
cd ../yeni-oyun
./run.sh editor
```

Şablon araç takımını `libs/scene-toolkit` altına git submodule olarak ekler ve bulunduğun commit'e sabitler.

Toolkit ve oyun birlikte `./push.sh "mesaj"` ile gönderilir, sıra elle yönetilmez. Ayrıntı için `tools/push.sh` başındaki açıklamaya bak.

## Oyuna bağlama

Oyunlar bu repoyu `libs/scene-toolkit` yoluna submodule olarak ekler. Klonlarken `git clone --recursive` kullanılır. Sonradan alınan değişiklikler için `git submodule update --init --recursive` çalıştırılır.

Repo gizlidir, ekipteki herkesin erişim izni olmalıdır.

## Bileşen yazmak

```haxe
@:component("house")
class HouseComponent extends Component {
  @:editable("Yükseklik", 2, 12) public var height : Float = 4;

  override function onCreate() {
    // Görseli kur. Oyunda ve editörde çalışır.
  }

  override function onUpdate(dt : Float) {
    // Yalnızca oyunda çalışır.
  }
}
```

Bileşen `ComponentRegistry.register` ile kaydedilir. Alan tipi açıkça `Float`, `Int`, `Bool`, `String`, `Array<String>` veya `Array<Float>` olmalıdır.

Metin alanının anlamı işaretlenirse Inspector uygun girişi gösterir, kayıt doğrulaması da bakar:

```haxe
@:editable("Model") @:asset public var path : String = "";     // Asset Browser'dan sürüklenir, dosya aranır
@:editable("Hedef") @:entity public var target : String = "";  // Listeden seçilir, nesne aranır
@:editable("Parça") @:prefab public var part : String = "";     // Prefab listesinden seçilir, dosya aranır
@:editable("Tür") @:choice("kolay", "zor") public var kind : String = "kolay";  // Açılır liste
@:editable("Renk") @:color public var tint : Int = 0xFF8000;    // Renk seçici
```

Tablo ve diyalog alanları:

```haxe
@:editable("Fraksiyon") @:ref("fraksiyonlar") public var faction : String = "tarafsiz";  // res/data/fraksiyonlar.table.json
@:editable("Diyalog") @:dialog public var dialog : String = "";                          // res/data/dialogs/<id>.dialog.json
```

Tabloda olmayan satır veya olmayan diyalog derleme uyarısı verir ama derlemeyi durdurmaz, editörde Uyarılar panelinde görünür. Bunlar kod değil içeriktir: bir tasarımcının silmesi veya iki kişinin birleştirmesi ekibin editörünü açılmaz hale getirmemelidir. Veri paneli kullanılan satırın silinmesini ve kimliğinin değişmesini engeller (`scene.editor.DataUsage`). Kod tarafındaki uyuşmazlıklar, yani bileşen, alan ve `@:choice` seçenekleri, derlemeyi durdurmaya devam eder.

Bileşen `storyLinks()` ile görev bağlantılarını bildirir (`scene.story.StoryLink`): bekler veya yayar (olay), okur veya ayarlar (değişken), ister, verir veya alır (eşya), başlatır (diyalog). Uyarılar ve ajanın `explain_quest` aracı bunları eşleştirir. Bileşen `title()` ile Türkçe adını, `category()` ile "Bileşen ekle" grubunu, `issues()` ile Uyarılar paneline düşecek kendi kurallarını verir. `addable()` grup adları döndürürse Inspector bileşenin altında "+ Grup" düğmeleri gösterir; tetikleyici `[TriggerCondition.CATEGORY, TriggerAction.CATEGORY]` döndürür.

`@:choice` alanı `String` olmalı ve varsayılanı seçeneklerden biri olmalıdır. Seçenek koddan çıkarılınca o değeri kullanan sahne, prefab veya prefab farkı derlemeyi durdurur.

Görseli `entity.object` altında olmayan bileşen (sahne köküne bağlı birim gibi) `visuals()` döndürür. Seçim ve gizleme bu görselleri de kapsar.

Oyunda görünmeyen şekiller `drawOverlay(overlay, selected)` içinde çizilir. Hazır biçimler `OverlayShapes` içindedir.

## İşaretçi yazmak

İşaretçi, oyunda görünmeyen ve editörde tıklanabilen bir bileşendir. `Marker`'dan türer, `ComponentRegistry` ile kaydedilir, `Düzen > İşaretçi ekle` menüsüne kendiliğinden girer:

```haxe
@:component("camp")
class CampMarker extends Marker {
  @:editable("Yarıçap", 1, 100) public var radius : Float = 8;

  override public function color() : Int {
    return 0xE08040;
  }

  override public function title() : String {
    return "Kamp";
  }

  override function drawShape(overlay : Overlay, tint : Int, at : h3d.Vector) {
    OverlayShapes.circle(overlay, flatFrame(at), radius, 0, tint);
  }

  override function onStart() {
    // Oyun başlarken çalışır. Editörde çalışmaz.
  }
}
```

Rota için `RouteMarker`'dan türeyin ve `WaypointMarker`'ı da kaydedin. Noktalar alt nesnedir, `waypoints()` sırayla verir. `collider` bileşeni için `ColliderComponent` kaydedilir.

Zeminin yüksekliğini bilen oyun `level.provide(GroundHeight, terrain)` çağırır, işaretçiler zemine oturur ve `z` zeminden yükseklik olur. Verilmezse `z` olduğu gibi kullanılır.

## Dünya

Dünya isteğe bağlıdır. Tek sahneyle çalışan oyun bu bölümü atlar. Veri ve araçlar toolkit'tedir, çizim oyuna aittir: görsellik oyundan oyuna değişir.

```
res/world/main.world.json      ızgara, arazi katmanları
res/world/global.scene.json    hücreye bağlı olmayan nesneler
res/world/environment.json     saat, güneş, sis
res/world/c_3_2.scene.json     hücrenin nesneleri, sahneyle aynı biçim
res/world/c_3_2.terrain.json   yükseklik ve boya
res/world/c_3_2.scatter.json   dağıtılan nesneler
res/world/c_3_2.nav.json       yol ağı
res/world/c_3_2.terrain.mesh   arazi modelinin bu hücreye düşen parçası, ikili (LFS)
res/world/textures/            arazi modellerinin dokuları
```

Bağlamak için:

1. Oyun `WorldView` arayüzünü yazar: arazi ve dağıtma çizimi, dağıtma türleri, hava durumu hazır ayarları, ortamın uygulanması.
2. Oyun `WorldData.read` ile `WorldState` kurar ve `state.view` verir.
3. Editörde `state.loadAllTerrain()` ve `new Editor(level, "res/world/main.world.json", state)`.
4. Oyunda `new CellStreamer(state, level, true)`, `start(x, y)` ve her karede `update(x, y)`.
5. Derleme kontrolü için `common.hxml` içine `--macro scene.macro.SceneCheck.run("res/world")`.

Editörde yeni dünya oluşturma komutu yoktur, ilk `main.world.json` elle yazılır. Olmayan arazi dosyası düz arazi sayılır, ilk kayıtta oluşur.

Bileşenler iki yerden dünyaya katılır:

```haxe
// Yol ağında yürünemeyen alan
override public function navShapes() {
  return [NavShapes.box(entity.object.getAbsPos(), width, depth)];
}

// Hücresinden çıkıp oyuncunun yanına gelen şey hücreyle birlikte silinmesin
override public function keepsCell(isNear : (Float, Float) -> Bool) {
  return Lambda.exists(units, unit -> isNear(unit.x, unit.y));
}
```

`CellStreamer` hücreyi `objectRadius` halkasında yükler, bir hücre dışına çıkınca boşaltır. Arazi `terrainRadius` halkasında kalır. Oyun sürerken gelen hücrelerde `onStart` da çalışır.

Arazi modeli `assets/terrain/` altındaki FBX'ten gelir. FBX `.editor/terrain/` altında HMD'ye çevrilir ve repoya girmez. Üçgenler ağırlık merkezine göre hücrelere bölünür, kesilmez. Yükseklik 2 metre aralıkla hücrenin `.terrain.json` dosyasına yazılır ve modelin dört köşesini kapladığı kareler `TerrainCell.COVERED` olur. Oyun bu karelerde kendi arazisini çizmez, parçayı `WorldView.terrainChanged` içinde `state.surfaces` üzerinden çizer. Yeniden uygulamada her hücre eskisiyle karşılaştırılır, yalnızca farklı olanlar komuta girer. `.gitattributes` içinde `*.mesh` LFS'te olmalıdır. Heaps FBX'i X ekseninde aynalar, model binalar gibi bu kurala uyar.

Yol bulma `NavWorld.findPath` ile yapılır. Hücre başına düğüm ızgarasıdır, saf Haxe'dir, yerel kütüphane gerektirmez. Hücreler ilk gerektiğinde okunur, yol ağı olmayan hücre yürünebilir sayılır. `NavWorld.findPathInto` yolu yeniden kullanılan bir tampona yazar, arama başına bellek ayırmaz. `NavSearch` bir aramayı parçalara böler (`begin`, düğüm ya da süre sınırıyla `step`, `result`): kare bütçesi uzun bir aramayı karelere yayabilir, bölünmüş arama aynı yolu bulur. `labelRegions` bağlı bölgeleri baştan (örneğin yüklemede) etiketler, ilk kullanımda değil. Recast'e geçilirse `NavWorld` ve `NavBaker` değişir, bileşenler etkilenmez.

## Görevler ve diyaloglar

`scene.story` paketidir. Oyun `Story` kurar ve `level.provide(Story, story)` ile verir; oyun durumu (`GameState`: eşya, değişken, fraksiyon ilişkisi), açık diyalog ve adlı olaylar oradadır.

- Koşul `TriggerCondition`'dan, eylem `TriggerAction`'dan türeyen bileşendir. Tetikleyici nesnesine eklenir, `story.fire(entity)` bütün koşullar sağlanırsa eylemleri bileşen sırasıyla çalıştırır.
- Diyalog `Dialog` biçimindedir, `DialogRunner` oynatır. Olay düğümü `story.emit(ad)` çağırır, `story.listen(ad, entity)` ile bekleyen tetikleyici çalışır. Eşya ve değişken işleri böylece tek yerde, eylemlerde kalır.
- Diyalog kutusunun çizimi oyuna aittir: `story.dialog` okunur, `next()` ve `choose(i)` çağrılır.
- Editörde diyalog `scene.editor.DialogWorkspace` ile sahne görünümünün yerinde düzenlenir, seçili düğüm Inspector'da açılır. Alt paneldeki `DialogPanel` yalnızca listedir.
- Düğüm konumları dosyada ekran netliğinden bağımsız birimdedir, tuvale `interfaceScale` ile çarpılarak verilir. Yerleştir `scene.story.DialogLayout` ile ekranda ölçülen boydan değil içerikten hesaplanır: Retina Mac ile Windows aynı dosyayı üretir.
- "Tetikleyici ekle" kayıtlı bileşenlerden bulunur: `addable()` içinde eylem grubu olan yerleştirilebilir işaretçi ve `@:dialog` alanlı bir `TriggerAction`. İkisi yoksa düğme görünmez.
- Oyun `editor.dialogs.itemTable` ile eşya tablosunu söylerse koşul düğümünde eşya listeden seçilir ve satır silinirken diyaloglar da taranır.

Oyun verisi `scene.data.DataTable` ve `GameData` ile okunur. Her tablo `res/data/<ad>.table.json` dosyasıdır.

## Dosya güvenliği

Editör dosyayı hiç kör yazmaz (`DiskGuard`, `StoreGuard`):
- Kaydetmeden önce diski yeniden okur. Dosya dışarıda değiştiyse `scene.data.ThreeWay` ile üç yönlü birleştirir: sahnede nesne, tabloda satır, diyalogda düğüm düzeyinde.
- Aynı birim iki tarafta da farklı değiştiyse dosyayı yazmaz. İki hali `.editor/catismalar/` altına yedekler, Uyarılar panelinde seçtirir.
- Açık dosyaları saniyede bir yoklar. Temiz olanı yeniden yükler ve o dosyanın geri alma adımlarını `CommandStack.forget` ile düşürür.

Yeni bir dosya türü yazan kod bu yoldan geçmelidir.

## Ajan sunucusu

`scene.editor.agent.AgentServer`, editör açılınca `127.0.0.1:8890`'da MCP (HTTP) sunucusu açar. Soket her karede yoklanır, araçlar ana döngüde çalışır. Bir araçtaki hata editörü düşürmez, ajana hata olarak döner. `Origin` başlıklı ve başka `Host`'lu istekler reddedilir.

`ContextTools` salt okunur bağlam araçlarını ve istemleri (`addPrompt`) kaydeder. `PlayTools` oyun gözünü, `EditTools` yazma araçlarını, `ExamTools` ajan sınavını (`tests/ajan-sinavi/*.sinav.json`) kaydeder. Oyun kendi araçlarını `editor.agent.add` ile ekler; başka bir aracı `callTool` ile çağırabilir. `AgentPanel` son çağrıları gösterir (`agent.log`).

**Model içe aktarma:** `AssetImporter` FBX'i HMD'ye çevirmeden önce `FbxCurves.sync` ile animasyon eğrilerini eşitler. Heaps bir düğümün X, Y, Z eğrilerini ilk eğrinin anahtar zamanlarıyla okur, eksen eksen azaltılmış anahtarlar sıfıra düşerdi. Ayarlar kaynağın yanındaki `<ad>.aktarim.json` dosyasındadır (`ImportSettings`: `trim`, `clips`, `sockets`, `joints`, `length`, `grip`, `blender`). Klasördeki `klasor.aktarim.json` alt klasörlerdeki bütün modellere uygulanır (`ImportSettings.effective`); modelin kendi dosyası aynı adlı klibi, noktayı ve alanı ezer, kırpma yalnızca modelin kendisinden gelir.
- `BlenderConverter` GLB, glTF ve OBJ'yi (ayarda `blender: true` ise FBX'i de) başsız Blender'la FBX'e çevirir (`tools/blender_fbx.py`: `FBX_SCALE_UNITS`, gömülü dokular, her karede anahtar). Çıktı `.editor/donusum/` altında, kaynak ya da betik değişince yenilenir. Blender `BLENDER` ortam değişkeninden ya da Mac ve Windows'un bilinen kurulum yerlerinden bulunur.
- `scene.JointNames` (runtime) eklem adlarını standart adlara eşler: Mixamo, `mixamorig:` öneki, Rigify (`DEF-`, `ORG-`). İçe aktarma eşlemeyi `<ad>.model.json`'un `joints` alanına yazar; oyun aynı eşlemeyle arar, yeni iskelet için kod değişmez.
- Çok klipli FBX: klip satırının `take` alanı dosyadaki klibin adıdır (sonundan eşleşir); `source` boşsa klip modelin kendi dosyasındandır.
- `skins` kaplamalar için kaynağa göre bir kalıptır (`textures/{ad}_skin*.png`); uyan dokular modelin yanına kopyalanır, adları `<ad>.model.json`'un `skins` alanına yazılır. Çalışma zamanında `ModelLibrary.texture(path)` dokuyu verir.
- İskeletsiz modelde `length` en uzun kenarı metreye ölçekler (`RigidModel.scaleTo`), `grip: true` tutamak noktasını köşelerden tahmin eder (`GripEstimate`: temel eksen, ince uç sap, X başın en geniş yönü).
- `ModelTrim` kutularla üçgen kırpar. Üçgen tek noktaya indirilir, köşe ve deri verisi bozulmaz.
- `ModelClips` başka FBX'lerin kliplerini HMD'ye ekler, rigin dinlenme pozuna yeniden hedefler (`retarget`) ve adım hızını ölçer.
  - Klipler ayrı bir `HMDOut` ile okunur; `leftHandConvert()` `loadAnimation()`'dan önce çağrılmalı, yoksa dönüşler aynalanmaz ve kollar yer değiştirir.
  - Klip satırında `arms` verilirse kol eklemleri (köprücükten ele) o klibin ilk karesinde sabit kalır (`holdArms`): kütüphanede olmayan silahlı klipler böyle türetilir.
- Takma noktaları (`ImportSettings.sockets`) `<ad>.model.json`'a yazılır; iskeletli modelde ayar yoksa standart eklemlere (eşlemeyle) varsayılanlar (avuç ele bağlı köşelerden). Eksen bağlama pozundaki gövdeye göre, yönü `socketFrame`. İskeletsiz modelde yalnızca noktalar yazılır.
- Veri tablolarında `varlik` türü: `res/` altındaki dosya yolu. `GameData.forget` tablo değişince önbelleği bırakır.
- `Editor.requestRender` çizim karesinin içinde bir kez ekran dışı çizim yaptırır (oyunun ajan önizlemesi bununla çizer).
- Kayıt (`scene.save`, oyunun kullandığı genel parçalar; ne saklanacağına oyun karar verir):
  - `Saveable`: bileşen farkını verir ve geri yükler.
  - `WorldDelta`: kapanan hücrelerin farkı. `SceneInstance.delta` atanınca `destroyEntity` farkı alır, `stream` ve `start` `onStart`'tan önce geri yükler.
  - `SaveFile`: bölümlü, sıkıştırılmış, CRC32'li dosya; güvenli yazma ve yedek.
  - `SaveSlots`: seferler ve yuvalar.
  - `PlayOptions.save` (`--save`), `CellStreamer.restart`, `GameState.watch` ve `restore`.
  - `Random`: tohumlu üretici, `hxd.Rand`'ın birebir kopyası (Heaps güncellemesi tohumdan çıkan sayıları değiştiremez; testte altın değerlerle kilitli). Kodda `Math.random`, `Std.random`, `hxd.Rand` yasak, bekçi test tarar. `RandomStreams`: seferin tohumundan adlı, kaydedilebilir akışlar.
  - Oyunda yok etmek `SceneInstance.removeEntity` (fark kaydına "silindi"; hücre açılınca kurulmaz), oyunda kurmak `spawnEntities(veri, hücre, sahip)` (tam veri kayda girer, hücreyle açılıp kapanır). `destroyEntity` hücre kapanışı içindir, kayda "silindi" yazmaz. Kimlik `WorldDelta.newId(akış)`.
  - Kayıttan oyna: `SaveInspector` (oyun kayıt listesini ve raporu verir), `panels/SavesWindow` (Oyun > Kayıttan oyna…), `Editor.playFromSave`, görev testinin `save` alanı (`--save` ile açılan oyun). Sınav görevinde `files` (görev dosyalarını yerine koyar, sonunda kaldırır) ve `quest_test` için `save: true`.
  - Donmasız kayıt: `SaveFile.pack` / `encodePacked` (sıkıştırılmış bölümler), `DeltaSections` (hücre bölümleri önbellekte; `WorldDelta.touch`/`takeDirty` değişen hücreleri izler, yalnızca onlar yeniden kodlanır), `SaveWriter` (arka planda iş parçacığı: sırayla yazma, `later` bölümleri orada hazırlanır, `poll`/`flush`). `SaveSlots.AUTO_COUNT` 5.
  - Optimizasyon motoru (`scene.tune`, oyunun planı `docs/OPTIMIZASYON_PLANI.md`): `TuneModule` (ayarlar, kilitli ayarlar, ölçütler `Max`/`Min`/`Band`/`Limit`, senaryo, eğitim ve doğrulama tohumları, kaynak `sentetik`/`iz`), `Tuner` (kaba kuvvet ya da rastgele örnekleme ve yerel iyileştirme, önbellek, doğrulamada da sert sınırı tutan seçim, kalite-performans sınırı), `TuneReport` (Markdown rapor).
  - Sürümler: `Migrations` (biçim göçleri sırayla; oyun adımları ekler), `ContentPrint` (hücre dosyalarının ve tabloların CRC32 izi, `diff` kayıttan sonra değişenleri verir), `WorldIndex` (tasarlanmış bütün nesneler, prefab içleri açılmış; yetim fark ve yerine geçen adayı için).
  - Sıfırlamadan sağ çıkanlar: `WorldDelta.isPlayerOwned` (bileşen durumunda `owner: "oyuncu"` ya da oyuncunun kurduğu) ve `isStory` (durumda `story: true`, hikâye ilerlemesi: çalışmış tetikleyici). `forgetCell` (bölge sıfırlama) bunları korur, `importPart` (Import) yalnızca bunları taşır.
  - `WorldDelta.remap`: kimlik eşlemesi. Editörde `ReleaseIds` yayın listesini yazar, kaybolan yayın nesnesini uyarır, yerine geçeni önerir ve `kayit_esleri` tablosuna eşler. Yayın listesi yalnızca büyür; eşlemeler zincirlenir (`ReleaseIds.resolve`, `WorldDelta.remap`), bilerek kaldırılan nesne bırakılır (`birak` sütunu). `Issue.actions` uyarının yanında düğmeler çizer.
  - Yeniden hedefleme: her eklem için rig dünya = rig dinlenme × klip dinlenmesi⁻¹ × klip dünya. Kemik boyları rigden alınır.
  - Klibin iskeleti bir okuyucudan, kareleri ayrı bir okuyucudan gelir. Heaps `loadAnimation`'ı aynı okuyucuda ikinci kez çağırınca açıları yeniden radyana çevirir.
  - Kareler `HMDOut.makeAnimation` ile yazılır.
- İskeletli modelin yanına `<ad>.model.json` yazılır: boy, kalçanın yeri ve klip hızları metre cinsinden, bakış yönü (yürürken yere basan ayağın tersi).
- Ayar dosyası veya bir klibin kaynağı HMD'den yeniyse model yeniden alınacaklar listesine girer.
- Çalışma zamanında `ModelLibrary.animation(path, name)` adlı klibi önbellekten verir.
- İçe aktarma, yazdığı modeli `ModelLibrary`'den düşürür ve `AssetWatch.changed` ile dinleyicileri hemen haberdar eder. Önbellekte kalan eski başlık yeni dosyayı yanlış okur; deride boş erişim olur.
- Ajan araçları: `model_info` (sınırlar, eklemler, eklem eşlemesi, dosyadaki klip adları, klipler, karakter bilgisi, etkin ayar, taban haritası) ve `import_model`'in `trim`, `clips` (`take` ile), `sockets`, `joints`, `length`, `grip`, `blender` ve `folder` (klasör ayarına yazar) alanları. Yazma araçları editör komutlarını kullanır ve çağrıyı tek adım olarak geçmişe yazar (`CommandStack.record`). Hata olursa uygulanan komutlar geri alınır. Ekran görüntüsü için oyunun `Main.render`'ı `super.render(e)`'den sonra `editor.afterRender(e)` çağırmalıdır, şablon bunu yapar. Oyun kendi aracını `editor.agent.add({name, description, schema, readOnly, run})` ile ekler. `run` bir nesne döndürür: `{value}` JSON olarak, `{text}` düz metin olarak, `{png}` görüntü olarak gider. Projenin `.mcp.json`'u ve `.claude/settings.json`'u şablonda `mcp.json` ve `claude-settings.json` adlarıyla durur, `new-project.sh` yerine koyar. `settings.json`'daki `PostToolUse` hook'u `tools/agent-hook.sh`'ı çalıştırır. Betik, editörün iki saniyede bir yazdığı `.editor/ajan-durum.json`'a bakar. Editör kapalıysa sessiz kalır, sunucuya hiç bağlanmaz; bu yüzden editör kapalıyken hata mesajı çıkmaz.

## Oyun gözü ve görev testleri

Editör F5 veya görev testi için oyunu `--play` ile ayrı süreçte açar. Haberleşme dosyayladır (`scene.PlayFiles`):
- Oyun durumunu `bin/ajan/oyun-durumu.json`'a, hikâye izini `bin/ajan/oyun-izi.jsonl`'a yazar.
- Görev testinde editör `bin/ajan/senaryo.json`'u yazar. Oyun onu okur, oynar, `bin/ajan/sonuc.json`'u yazıp kapanır.

İz için oyun `story.log = new scene.story.StoryLog()` verir; Story ve `DialogRunner` adımları kendisi kaydeder.

Durumu yazan köprü ve test adımlarını oynayan çalıştırıcı oyuna aittir, çünkü ekip ve birim oyunun kendi türleridir. Bu oyunda `src/agent/PlayBridge.hx` ve `QuestTestRunner.hx`'te durur. Başka bir oyun aynı dosyaları yazdığı sürece editör ve ajan araçları değişmeden çalışır. Görev testleri `res/tests/*.test.json`'dadır, biçim kılavuzda.

## Prefab

Prefab dosyası `res/prefabs/ad.prefab.json`, tek köklü küçük bir sahnedir. Sahne yalnızca kök satırını tutar: `prefab` yolu ve `overrides` listesi. Alt nesneler yüklenirken açılır, kimlikleri `kök/parça` biçimindedir. Farklar elle izlenmez, kayıtta prefab'la karşılaştırılarak bulunur.

Oyun, sahneyi yüklemeden önce dosya okuyucuyu verir:

```haxe
level.prefabLoader = path -> hxd.Res.load(path).toText();
```

Derleme kontrolü için `common.hxml` içine `--macro scene.macro.SceneCheck.run("res/prefabs")` eklenir. Artık kodda olmayan bir alanı gösteren fark derlemeyi durdurur. Eksik prefab dosyası ve iki köklü prefab ise içeriktir: derleme uyarı verir, durmaz, `push.sh` uyarıyı onaydan önce gösterir. Açılamayan prefab sahneyi düşürmez: editörde kök nesne yolu ve farklarıyla korunur, oyunda boş nesne olarak kurulur ve `Sahne uyarısı` yazılır.

## Yeniden adlandırma

Dosyada sınıf adı değil `@:component` kimliği saklanır, bu yüzden sınıfı taşımak veya yeniden adlandırmak sahneleri etkilemez.

Kimlik veya `@:editable` alan adı değişirse eskisi bildirilir. Sahneler eski adla açılır, ilk kayıtta yeni ada geçer:

```haxe
@:component("house")
@:formerly("hut")
class HouseComponent extends Component {
  @:editable @:formerly("h") public var height : Float = 4;
}
```

Bildirim unutulursa derleme durur ve hangi sahnede hangi nesnenin etkilendiğini söyler. Bunun için oyunun derleme ayarında şu satır olmalıdır:

```
--macro scene.macro.SceneCheck.run("res/scenes")
```

Bir bileşen veya alan bilerek silindiyse sahne dosyası da güncellenir.

`@:choice` seçeneklerinin eski ad bildirimi yoktur. Seçenek silinir veya yeniden adlandırılırsa derleme durur, `res/scenes/` ve `res/prefabs/` altındaki değerler aynı commit'te değiştirilir.

## Sahne dosyası

JSON'dur ve deterministik yazılır: aynı sahne her sistemde aynı dosyayı üretir. Sayılar 5 ondalığa yuvarlanır, dönüşler derecedir, alanlar alfabetik sıralıdır. Bu derlemede tanınmayan bileşen ve alanlar silinmez, olduğu gibi geri yazılır.

Prefab kopyasının satırında `prefab` ve `overrides` bulunur, kopya olmayan nesnelerde bu alanlar yazılmaz.

Biçim değişirse `SceneFormat.VERSION` artırılır ve `MIGRATIONS` listesine yükseltme eklenir.

## Oyunu editöre bağlama

Şablondaki `Main.hx` hazır örnektir. Oyuna özel her şey başlangıçta kaydedilir:

```haxe
editor = new Editor(level, "res/" + MAIN_SCENE);
editor.actions.groundRay = ray -> terrain.raycast(ray);        // Verilmezse z = 0 düzlemi
editor.actions.addAssetType("fbx", "model", "path");           // Sürüklenen dosya hangi bileşene yazılır
editor.validator.rules.push(scene -> myIssues(scene));         // Kayıtta çalışan oyun kuralı
editor.addPanel("Fraksiyonlar", drawFactions);                 // Oyuna özel panel
editor.inspector.sections.set("house", peers -> drawHouse(peers)); // Inspector'da bileşenin alanlarının altında bölüm
```

- Inspector bölümü alanı ImGui ögesinin hemen ardından `editor.inspector.editField(peers, ad, değer, edited)` ile yazar (sürüklerken canlı, bırakınca tek geri alma adımı, alan gibi) ya da `setField(peers, ad, değer)` ile (hemen, tek adım).

- `Main.render` içinde `editor.render(e)` çağrılır, model önizlemeleri orada çizilir.
- Kare koruması (`scene.editor.FrameGuard`): editörde bir kare yarıda kalınca Dear ImGui sonraki `NewFrame`'de uygulamayı durdurur (assert, abort) ve kaydedilmemiş iş gider. Uygulama dört yer bağlar, şablondaki `Main.hx` örnektir:
  - `init` içinde `FrameGuard.install()`: Heaps'in hata bildirimi sarılır, hata metni saklanır.
  - `mainLoop` başında `FrameGuard.beforeFrame()`, sonuç `editor.frameFailed`'e verilir: önceki kare yarıda kaldıysa ImGui toparlanır.
  - `update` gövdesi `FrameGuard.run` ile, hata `editor.failed`'e verilir.
  - `render` içinde sahne çizimi `try` içinde, hata `editor.renderFailed`'e verilir: çizim hedefleri bırakılır, ImGui arayüzü yine çizilir.
  - Editör kendi bölümlerini ve her paneli `FrameGuard.run` ile çizer. Hata veren panel "Yeniden dene"ye kadar durur. Hata bildirimde, Uyarılar panelinde, günlükte ve ajanın `get_warnings` aracında görünür; sahnenin yedeği hemen alınır (`SceneDocument.backupNow`, en çok 10 saniyede bir).
  - Yerel tarafı `editor/native/imgui_guard.cpp`, hlimgui eklentisine derlenir. Üçüncü taraf hlimgui'ye dokunulmaz: Mac'te `tools/build-hlimgui.sh` kaynak listesine ekler, Windows'ta `tools/hlimgui/CMakeLists.txt` sarmalayıcısı aynı hedefe ekler.
  - Eklenti değişince `tools/hlimgui-surum.txt` artar. Derleme betikleri damgayı hdll'in yanına yazar; `run.sh editor` ve `run.bat editor` eski hdll'i tanıyıp yeniden derlemeyi söyler. Eski hdll'de yeni yerel işlevler yoktur; HashLink bunu açılışta anlaşılmaz bir hatayla bildirirdi.
- Editör ikilisi `--play <sahne> --camera x y z x y z` ile oyun olarak açılır, `PlayOptions.parse(Sys.args())` bunu okur. "Buradan oyna" bunu kullanır, çünkü oyun derlemesi kaynakları gömülü taşır ve yeni kaydedilen sahneyi görmez.
- Kişiye özel ayarlar `.editor/` altındadır ve git'e girmez: son açılanlar, editörde gizlenenler, otomatik yedekler.
- Görünürlük iki ayrı durumdur. `entity.active` sahneye yazılır ve oyunu etkiler, `entity.hiddenInEditor` yalnızca o bilgisayarda geçerlidir. İkisi bağımsızdır: oyunda kapalı nesne editörde düzenlenebilir kalır.
- İçe aktarma `assets/` altındaki modeli (FBX; GLB, glTF ve OBJ Blender'la çevrilerek) `res/models/` altına HMD olarak yazar; `assets/models/mock/` altındakiler `res/models/mock/` altına. Editör arayüzü olmadan da çağrılır: `new AssetImporter().run(kaynak)`. Oyun derlemesi FBX'i makro içinde dönüştürür ve normal map'li modelde `meshTools` ister, HMD'de bu adım yoktur. Yeni oyunun `.gitattributes` dosyasında `*.hmd` LFS'te olmalıdır.
- Heaps'in normal map ve specular gölgelendiricisi UV'yi temel renk dokusundan alır. Temel dokusu olmayan malzeme çizimde hata verir, içe aktarıcı bu malzemelere 1x1 beyaz doku ekler. Eksik doku da Heaps'te modelin tamamını düşürür, bu yüzden modelden çıkarılıp uyarı verilir.
- Seçim mesh üçgenlerine bakar. Heaps indekssiz `Polygon` için çarpışma verisi üretemez, `Picker` bunları kendi üçgen testiyle tarar. Yeni bir primitive türü `getCollider` veremezse seçici sınır kutusuna düşer, geniş bir kutu bütün tıklamaları yutar.
- `ModelLibrary.load` modeli tek önbellekten verir, kopyalar geometri ve dokuyu paylaşır. Bileşenler `ModelCache` açmamalı.
- Model başvurusu katalog kimliği ya da dosya yoludur (`scene.ModelRef`). Oyun kataloğu `ModelRef.catalog`'a verir (kimlik → dosya); `ModelLibrary.load`, `animation` ve `exists` başvuruyu kabul eder. Kimlik `[a-z0-9_]`, yol `/` ya da uzantı içerir; eski içerikteki yollar okunmaya devam eder. `ModelRef` Heaps'e bağlı değildir.
- Editörde `editor.actions.catalog` (`{find, ensure}`) verilirse sahneye bırakılan dosyanın alanına katalog kimliği yazılır; satır yoksa `ensure`'un tablo komutu nesneyle aynı geri alma adımına girer. İçe aktarma (Asset Browser ve ajanın `import_model`'i) da satırı ekler; `import_model` kimliği `catalog` olarak döner, `list_models` dosyaların kimliğini verir. `editor.data.onApplied` her tablo uygulanışında (düzenleme, geri alma, ajan) hemen çağrılır; oyun önbelleğini orada boşaltırsa aynı karedeki okuma yeni tabloyu görür.
- `SceneInstance.observers`: oyunun sistemleri (fizik gibi) nesnelerin oyunda başlamasını (bileşenler başladıktan sonra) ve silinmesini (bileşenler kapanmadan önce) dinler. Yalnızca oyun kipinde, sahne başlamışken.
- Komut satırından içe aktarma: `./run.sh ice-aktar <dosya ya da klasör>` (`scene.editor.ImportMain`, `import-mac.hxml`; Windows'ta bayt kodu için `import.hxml`). Pencere açmaz, editörle aynı `AssetImporter.run`; klasördeki modellerin hepsi aktarılır. Katalog satırını oyun ekler.
- Çarpışma bileşeni (`ColliderComponent`) yalnızca veridir; oyunun fizik servisi `ColliderComponent.bridge`'i (`added`, `removed`, `moved`) verirse bileşen oyunda başlayınca (`onStart`), silinince ve taşınınca haber verir. Sonradan bağlanan servis yüklü arazi hücrelerini `WorldTerrain.loaded()` ile kurar, sonrakileri `WorldView.terrainChanged` ile alır.
- `FocusGuard.install()` odak kaybında tuşları bırakır. Heaps bunu yapmaz, Cmd+Tab veya Alt+Tab sonrası tuş basılı kalır. Editör kendisi kurar, oyun `init` içinde çağırır.
- Mac'te HL/C clang ile `-O2 -g` derlenir (`-O0`'dan yaklaşık 7 kat hızlı, derleme birkaç saniye uzun) ve `-fwrapv` şarttır: Haxe'nin Int'i taşınca sarar, C'de işaretli taşma tanımsızdır. `-O1` ve üstünde karma ve rastgele sayı döngüleri bozulur (FNV tohumu her metinde 0 çıkıyordu). `tools/run.sh` bayrağı verir; kendi derleme betiğine de ekle.
- Heaps kamerası sol ellidir: ekranın sağı bakış yönünün saat yönünün tersindedir. Kamera yönleri kendi vektörleriyle değil, noktanın ekranda gittiği yerle test edilir.
- Heaps yatay tekerlek değerini atar. Mac'teki yamalı `hxd.Window` bunu `horizontalWheel` alanında saklar, Option + iki parmak böyle döndürür. Windows'ta bu değer yoktur, orada Ctrl + iki parmak döndürür. `hlsdl` iki değeri de tam sayıya keser, 1'in altındaki çok yavaş kaydırma kaybolur.
- ImGui çizim listesi renkleri `0xAARRGGBB` biçimindedir.
- hlimgui bağlamasında iki tuzak var: `selectable` sabit `true`/`false` ile çöker, değer değişkenle verilir. `getColorU32(ImGuiCol.X)` saydam döner, `getStyleColorVec4` kullanılır.

## Yüksek DPI (Retina ve Windows ölçeği)

Derlemeler `hidpi.hxml` ile gerçek piksel boyutunda çizer: Mac'te Retina, Windows'ta %125, %150, %200 gibi ekran ölçekleri. Heaps bunu desteklemediği için `hidpi/hxd/Window.hl.hx`, Heaps 2.1.0 dosyasının yamalı kopyasıdır. hlsdl 1.16 SDL3 kullanır, iki sistem farklı davranır (SDL3 README-highdpi):

| | Pencere koordinatı | `pixelDensity` | `contentScale` (ekranın ölçeği) |
| --- | --- | --- | --- |
| Mac Retina | nokta | 2 | 2 |
| Windows %150 | piksel | 1 | 1,5 |

- `hidpi.hxml`, bütün `.hxml` dosyalarında (Mac ve Windows) `common.hxml`'den önce gelmelidir. Sonra gelirse Haxe, Heaps'in kendi dosyasını seçer ve derleme `pixelDensity` hatası verir.
- Yama nokta–piksel dönüşümünü yalnızca Mac'te yapar (`pixelDensity`); Windows'ta pencere zaten pikseldir. Arayüzün büyütme payı ikisinde de `contentScale`'dir.
- `HiDpi.prepare()` `main` içinde, SDL açılmadan çağrılır: Windows'ta süreç ekran başına DPI'a duyarlı açılır (`SDL_WINDOWS_DPI_AWARENESS=permonitorv2`), işletim sistemi görüntüyü bulanık büyütmez.
- Oyun `init` içinde `HiDpi.fit(s2d, enKüçükYükseklik)` çağırır. `s2d` eski birimlerini korur, `s3d` ve `engine.width` gerçek pikseldir. `HiDpi.density` sahnenin ölçeğidir: oyunun seçimi (`HiDpi.choice`, sonra `HiDpi.refresh()`), yoksa ekranın ölçeği; sahne verilen yükseklikten kısa kalacaksa kısılır.
- Pencere boyutu ölçeksiz birimle seçilir, piksel boyutu için `HiDpi.displayScale` ile çarpılır; masaüstü boyutuyla karşılaştırırken `displayScale / pixelDensity` (Mac'te 1, Windows'ta ölçek). Ölçekle büyüyen pencere masaüstünü aşabilir (%150 ölçekli 1080p ekranda 1280x720 → 1920x1080): oyun başlık ve görev çubuğu payıyla sığacak kadar küçültmeli, `fit`'e verilen en küçük yükseklik arayüzü yine sığdırır.
- Editör `imguiScene` sahnesini yakınlaştırmaz, çünkü hlimgui kırpmayı ham pikselle yapar. Font ve stil `HiDpi.density` ile büyür.
- Sabit boyutlu bitmap fontlar `s2d`'de yumuşatılarak büyütülür. Keskin olmaları için 2x atlas gerekir; ölçek 1'den büyükse 2x atlası yarım ölçekle çizmek (küçültmek) keskin kalır.
- Windows davranışı belgeden (SDL3) kuruldu, Windows'ta denenmedi.
- Heaps yükseltilirken yama yeni dosyaya yeniden uygulanır, değişen satırlar `HiDPI` ile işaretlidir.
- Mac `.app` paketinin `Info.plist` dosyasında `NSHighResolutionCapable` açık olmalıdır.

## Testler

Hızlı kontrol, proje kökünden: `haxe libs/scene-toolkit/tests.hxml`. Heaps'in matematik türlerini (`h3d.Vector`, `h3d.Matrix`) isteyen testler ayrı: `haxe libs/scene-toolkit/tests-heaps.hxml` (`tests/heaps`); yorumlayıcı Heaps'in model verisini (`hxd.fmt.hmd`) derleyemediği için buradaki kod ona bağlanmaz.

Gerçek hedefte, HashLink'te: `./run.sh test` veya `run.bat test`. Sayı ve tip davranışı yorumlayıcıdan farklı olabildiği için asıl geçerli olan budur.

## Lisans

Araç takımı Heaps ile aynı lisansla, MIT Lisansı altındadır: [LICENSE](LICENSE).

İçindeki üçüncü taraf parçalar kendi lisanslarını korur:

- `vendor/hashlink/`: [HashLink](https://github.com/HaxeFoundation/hashlink) kitaplıkları, MIT Lisansı ([HashLink lisansı](https://github.com/HaxeFoundation/hashlink/blob/master/LICENSE)). `libopenal`, [OpenAL Soft](https://github.com/kcat/openal-soft), GNU LGPL 2 ([OpenAL Soft lisansı](https://github.com/kcat/openal-soft/blob/master/COPYING)).
- `hidpi/hxd/Window.hl.hx`: [Heaps](https://github.com/HeapsIO/heaps) dosyasının yamalı kopyası, MIT Lisansı ([hidpi/LICENSE_HEAPS](hidpi/LICENSE_HEAPS)).
- `editor/fonts/`: DejaVu Sans Mono ([editor/fonts/LICENSE_DEJAVU](editor/fonts/LICENSE_DEJAVU)).
- `third_party/hlimgui`: [hlimgui](https://github.com/nspitko/hlimgui) alt modülü, kendi lisansıyla.
