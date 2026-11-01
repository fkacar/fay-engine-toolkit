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

## Prefab

Prefab dosyası `res/prefabs/ad.prefab.json`, tek köklü küçük bir sahnedir. Sahne yalnızca kök satırını tutar: `prefab` yolu ve `overrides` listesi. Alt nesneler yüklenirken açılır, kimlikleri `kök/parça` biçimindedir. Farklar elle izlenmez, kayıtta prefab'la karşılaştırılarak bulunur.

Oyun, sahneyi yüklemeden önce dosya okuyucuyu verir:

```haxe
level.prefabLoader = path -> hxd.Res.load(path).toText();
```

Derleme kontrolü için `common.hxml` içine `--macro scene.macro.SceneCheck.run("res/prefabs")` eklenir. Eksik prefab dosyası, iki köklü prefab ve artık kodda olmayan bir alanı gösteren fark derlemeyi durdurur. Editörde bozuk prefab sahneyi düşürmez, kök nesne yolu ve farklarıyla korunur.

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
```

- `Main.render` içinde `editor.render(e)` çağrılır, model önizlemeleri orada çizilir.
- Editör ikilisi `--play <sahne> --camera x y z x y z` ile oyun olarak açılır, `PlayOptions.parse(Sys.args())` bunu okur. "Buradan oyna" bunu kullanır, çünkü oyun derlemesi kaynakları gömülü taşır ve yeni kaydedilen sahneyi görmez.
- Kişiye özel ayarlar `.editor/` altındadır ve git'e girmez: son açılanlar, editörde gizlenenler, otomatik yedekler.
- Görünürlük iki ayrı durumdur. `entity.active` sahneye yazılır ve oyunu etkiler, `entity.hiddenInEditor` yalnızca o bilgisayarda geçerlidir. İkisi bağımsızdır: oyunda kapalı nesne editörde düzenlenebilir kalır.
- İçe aktarma `assets/` altındaki FBX'i `res/models/` altına HMD olarak yazar. Oyun derlemesi FBX'i makro içinde dönüştürür ve normal map'li modelde `meshTools` ister, HMD'de bu adım yoktur. Yeni oyunun `.gitattributes` dosyasında `*.hmd` LFS'te olmalıdır.
- Heaps'in normal map ve specular gölgelendiricisi UV'yi temel renk dokusundan alır. Temel dokusu olmayan malzeme çizimde hata verir, içe aktarıcı bu malzemelere 1x1 beyaz doku ekler. Eksik doku da Heaps'te modelin tamamını düşürür, bu yüzden modelden çıkarılıp uyarı verilir.
- Seçim mesh üçgenlerine bakar. Heaps indekssiz `Polygon` için çarpışma verisi üretemez, `Picker` bunları kendi üçgen testiyle tarar. Yeni bir primitive türü `getCollider` veremezse seçici sınır kutusuna düşer, geniş bir kutu bütün tıklamaları yutar.
- `ModelLibrary.load` modeli tek önbellekten verir, kopyalar geometri ve dokuyu paylaşır. Bileşenler `ModelCache` açmamalı.
- `FocusGuard.install()` odak kaybında tuşları bırakır. Heaps bunu yapmaz, Cmd+Tab veya Alt+Tab sonrası tuş basılı kalır. Editör kendisi kurar, oyun `init` içinde çağırır.
- Heaps kamerası sol ellidir: ekranın sağı bakış yönünün saat yönünün tersindedir. Kamera yönleri kendi vektörleriyle değil, noktanın ekranda gittiği yerle test edilir.
- Heaps yatay tekerlek değerini atar. Mac'teki yamalı `hxd.Window` bunu `horizontalWheel` alanında saklar, Option + iki parmak böyle döndürür. Windows'ta bu değer yoktur, orada Ctrl + iki parmak döndürür. `hlsdl` iki değeri de tam sayıya keser, 1'in altındaki çok yavaş kaydırma kaybolur.
- ImGui çizim listesi renkleri `0xAARRGGBB` biçimindedir.
- hlimgui bağlamasında iki tuzak var: `selectable` sabit `true`/`false` ile çöker, değer değişkenle verilir. `getColorU32(ImGuiCol.X)` saydam döner, `getStyleColorVec4` kullanılır.

## Retina

Mac derlemeleri `hidpi.hxml` ile Retina ekranda gerçek piksel boyutunda çizer. Heaps bunu desteklemediği için `hidpi/hxd/Window.hl.hx`, Heaps 2.1.0 dosyasının yamalı kopyasıdır. Windows derlemesine girmez.

- `hidpi.hxml`, Mac `.hxml` dosyalarında `common.hxml`'den önce gelmelidir. Sonra gelirse Haxe, Heaps'in kendi dosyasını seçer ve derleme `pixelDensity` hatası verir.
- Oyun `init` içinde `HiDpi.fit(s2d)` çağırır. `s2d` eski birimlerini korur, `s3d` ve `engine.width` gerçek pikseldir.
- Editör `imguiScene` sahnesini yakınlaştırmaz, çünkü hlimgui kırpmayı ham pikselle yapar. Font ve stil `HiDpi.density` ile büyür.
- Sabit boyutlu bitmap fontlar `s2d`'de yumuşatılarak büyütülür. Keskin olmaları için 2x atlas gerekir.
- Heaps yükseltilirken yama yeni dosyaya yeniden uygulanır, değişen satırlar `HiDPI` ile işaretlidir.
- Mac `.app` paketinin `Info.plist` dosyasında `NSHighResolutionCapable` açık olmalıdır.

## Testler

Hızlı kontrol, proje kökünden: `haxe libs/scene-toolkit/tests.hxml`

Gerçek hedefte, HashLink'te: `./run.sh test` veya `run.bat test`. Sayı ve tip davranışı yorumlayıcıdan farklı olabildiği için asıl geçerli olan budur.
