package scene;

// Oyunun kullandığı bileşen türleri. Kayıt derleme sırasında değil başlangıçta yapılır,
// çünkü editör oyun koduyla birlikte derlenir ve eklenti yüklemeye gerek yoktur.
class ComponentRegistry {
  var factories = new Map<String, Void->Component>();

  public function new() {}

  public function register<T:Component>(type : Class<T>) {
    var create = () -> (cast Type.createInstance(type, []) : Component);
    var sample = create();
    var id = sample.componentId();
    if (id == null) throw '${Type.getClassName(type)}: @:component kimliği yok';
    for (name in [id].concat(sample.formerIds())) {
      if (factories.exists(name)) throw 'Bileşen kimliği iki kez kullanılmış: $name';
      factories.set(name, create);
    }
  }

  public function create(type : String) : Null<Component> {
    var factory = factories.get(type);
    return factory == null ? null : factory();
  }

  public function types() : Array<String> {
    var names = [for (name in factories.keys()) name];
    names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
    return names;
  }
}
