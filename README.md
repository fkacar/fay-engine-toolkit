# Scene Toolkit

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

Şablon araç takımını kopya olarak alır. Araç takımı kendi reposuna ayrılınca submodule'e geçilecek.

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

Bileşen `ComponentRegistry.register` ile kaydedilir. Alan tipi açıkça `Float`, `Int`, `Bool` veya `String` olmalıdır.

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

## Sahne dosyası

JSON'dur ve deterministik yazılır: aynı sahne her sistemde aynı dosyayı üretir. Sayılar 5 ondalığa yuvarlanır, dönüşler derecedir, alanlar alfabetik sıralıdır. Bu derlemede tanınmayan bileşen ve alanlar silinmez, olduğu gibi geri yazılır.

Biçim değişirse `SceneFormat.VERSION` artırılır ve `MIGRATIONS` listesine yükseltme eklenir.

## Testler

Hızlı kontrol, proje kökünden: `haxe libs/scene-toolkit/tests.hxml`

Gerçek hedefte, HashLink'te: `./run.sh test` veya `run.bat test`. Sayı ve tip davranışı yorumlayıcıdan farklı olabildiği için asıl geçerli olan budur.
