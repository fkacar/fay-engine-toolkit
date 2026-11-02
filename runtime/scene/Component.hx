package scene;

import scene.FieldInfo;

// Oyun mantığının sahneye bağlandığı birim. `@:editable` alanlar macro ile toplanır,
// Inspector'da görünür ve sahne dosyasına yazılır.
//
// Dosyada sınıf adı değil `@:component("kimlik")` saklanır, sınıf rahatça yeniden adlandırılır.
// Kimlik veya `@:editable` alan adı değişirse eskisi `@:formerly("eski")` ile bildirilir;
// bildirilmezse SceneCheck derlemeyi durdurur, tasarımcının işi sessizce kaybolmaz.
//
// Yaşam döngüsü:
//   onCreate   Oyunda ve editörde çalışır: görseli kurar.
//   onStart    Yalnızca oyunda, sahne hazır olunca bir kez çalışır.
//   onUpdate   Yalnızca oyunda, her karede çalışır.
//   onDestroy  Oyunda ve editörde çalışır: onCreate'in kurduğunu kaldırır.
@:autoBuild(scene.macro.ComponentMacro.build())
@:allow(scene)
class Component {
  public var entity(default, null) : Entity;

  // Bu derlemede tanınmayan alanlar kaybolmasın diye dosyaya geri yazılır.
  var unknownFields : Map<String, Dynamic> = [];

  public function new() {}

  public function componentId() : String {
    return null;
  }

  public function formerIds() : Array<String> {
    return [];
  }

  public function describeFields() : Array<FieldInfo> {
    return [];
  }

  public function readField(name : String) : Dynamic {
    return null;
  }

  public function writeField(name : String, value : Dynamic) : Bool {
    return false;
  }

  // Nesnenin altında olmayan görseller: seçim ve gizleme bunları da kapsar.
  public function visuals() : Array<h3d.scene.Object> {
    return [];
  }

  // Yol ağında yürünemeyen alanlar, dünya koordinatında.
  public function navShapes() : Array<scene.nav.NavCell.NavShape> {
    return [];
  }

  // Inspector'da ve "Bileşen ekle" menüsünde görünen ad.
  public function title() : String {
    return componentId();
  }

  // "Bileşen ekle" menüsündeki grup.
  public function category() : String {
    return "Bileşen";
  }

  // Uyarılar panelinde görünecek sorunlar: eklentinin kendi kuralları buraya yazılır.
  // Inspector bu gruplar için bileşenin altında "+ Grup" düğmesi gösterir: tetikleyiciye koşul ve eylem gibi.
  public function addable() : Array<String> {
    return [];
  }

  // Görev bağlantıları: hangi olayı bekler veya yayar, hangi değişkeni okur veya ayarlar. Uyarılar
  // ve ajan, yanlış yazılmış olay ve değişken adlarını bunlarla bulur.
  public function storyLinks() : Array<scene.story.StoryLink> {
    return [];
  }

  public function issues() : Array<String> {
    return [];
  }

  // Hücre boşaltılmadan önce sorulur. Hücreden çıkıp oyuncunun yanına gelen şeyler, örneğin
  // takip edilen kervan, hücreyle birlikte silinmesin diye true döner.
  public function keepsCell(isNear : (Float, Float) -> Bool) : Bool {
    return false;
  }

  // Editörde her karede çağrılır: görünmeyen şekiller, sınırlar ve rotalar burada çizilir.
  public function drawOverlay(overlay : scene.Overlay, selected : Bool) {}

  // Editörde bir alan değişince görsel yeniden kurulur.
  public function refresh() {
    entity.scene.destroyComponent(this);
    entity.scene.createComponent(this);
  }

  function onCreate() {}

  function onStart() {}

  function onUpdate(dt : Float) {}

  function onDestroy() {}

  function onEntityMoved() {}
}
