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
