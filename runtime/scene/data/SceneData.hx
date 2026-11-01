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

  public function new(id : String, name : String) {
    this.id = id;
    this.name = name;
  }
}

class ComponentData {
  public var type : String;
  public var fields : Map<String, Dynamic> = [];

  public function new(type : String) {
    this.type = type;
  }
}
