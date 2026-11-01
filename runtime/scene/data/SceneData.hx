package scene.data;

// Sahne dosyasının bellekteki hali. Heaps'e bağlı değildir.
class SceneData {
  public var version : Int;
  public var entities : Array<EntityData> = [];

  public function new(version : Int) {
    this.version = version;
  }
}

class EntityData {
  public var id : String;
  public var name : String;
  public var parent : Null<String>;
  public var active = true;
  public var position = [0., 0., 0.];
  public var rotation = [0., 0., 0.];  // derece
  public var scale = [1., 1., 1.];
  public var components : Array<ComponentData> = [];
  // Prefab instance'ı: alt nesneler dosyada değil prefab'da durur, burada yalnızca farklar vardır.
  public var prefab : Null<String>;
  public var overrides : Array<OverrideData> = [];

  public function new(id : String, name : String) {
    this.id = id;
    this.name = name;
  }

  public function clone() {
    var copy = new EntityData(id, name);
    copy.parent = parent;
    copy.active = active;
    copy.position = position.copy();
    copy.rotation = rotation.copy();
    copy.scale = scale.copy();
    copy.components = [for (component in components) component.clone()];
    copy.prefab = prefab;
    copy.overrides = overrides.copy();
    return copy;
  }
}

class OverrideData {
  public var target : String;  // instance köküne göre kimlik, kök için boş
  public var field : String;
  public var value : Dynamic;

  public function new(target : String, field : String, value : Dynamic) {
    this.target = target;
    this.field = field;
    this.value = value;
  }
}

class ComponentData {
  public var type : String;
  public var fields : Map<String, Dynamic> = [];

  public function new(type : String) {
    this.type = type;
  }

  public function clone() {
    var copy = new ComponentData(type);
    for (name => value in fields) copy.fields.set(name, value);
    return copy;
  }
}
