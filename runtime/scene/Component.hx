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

  // Editörde bir alan değişince görsel yeniden kurulur.
  public function refresh() {
    onDestroy();
    onCreate();
  }

  function onCreate() {}

  function onStart() {}

  function onUpdate(dt : Float) {}

  function onDestroy() {}

  function onEntityMoved() {}
}
