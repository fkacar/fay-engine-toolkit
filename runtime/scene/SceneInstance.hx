package scene;

import scene.data.SceneData;

// Yüklenmiş sahne. Dosya verisini canlı nesnelere çevirir ve geri yazar.
@:allow(scene)
class SceneInstance {
  public var root(default, null) : h3d.scene.Object;
  public var mode(default, null) : SceneMode;
  public var registry(default, null) : ComponentRegistry;
  public var entities(default, null) : Array<Entity> = [];
  public var warnings(default, null) : Array<String> = [];

  var isReady = false;
  var services = new Map<String, Dynamic>();

  public function new(registry : ComponentRegistry, mode : SceneMode, parent : h3d.scene.Object) {
    this.registry = registry;
    this.mode = mode;
    root = new h3d.scene.Object(parent);
  }

  // Bileşenlerin ihtiyaç duyduğu oyun sistemleri (arazi gibi) buradan alınır.
  public function provide<T>(type : Class<T>, service : T) {
    services.set(Type.getClassName(type), service);
  }

  public function service<T>(type : Class<T>) : T {
    return services.get(Type.getClassName(type));
  }

  public function find(id : String) : Null<Entity> {
    for (entity in entities) if (entity.id == id) return entity;
    return null;
  }

  public function createEntity(name : String, ?id : String) : Entity {
    var entity = new Entity(this, id == null ? Guid.make() : id, name);
    entities.push(entity);
    return entity;
  }

  public function destroyEntity(entity : Entity) {
    for (child in entity.children.copy()) destroyEntity(child);
    for (component in entity.components) component.onDestroy();
    entity.setParent(null);
    entity.object.remove();
    entities.remove(entity);
  }

  public function clear() {
    isReady = false;
    for (entity in entities.filter(entity -> entity.parent == null)) destroyEntity(entity);
    warnings = [];
  }

  public function load(data : SceneData) {
    clear();
    for (item in data.entities) {
      var entity = createEntity(item.name, item.id);
      entity.setPosition(item.position[0], item.position[1], item.position[2]);
      entity.setRotation(item.rotation[0], item.rotation[1], item.rotation[2]);
      entity.setScale(item.scale[0], item.scale[1], item.scale[2]);
      entity.active = item.active;
    }

    // Üst nesne dosyada alttan sonra gelebilir, bu yüzden bağlar ayrı geçişte kurulur.
    for (item in data.entities) {
      if (item.parent == null) continue;
      var parent = find(item.parent);
      if (parent == null) warnings.push('${item.name}: üst nesne bulunamadı (${item.parent})');
      else find(item.id).setParent(parent);
    }

    for (item in data.entities) {
      var entity = find(item.id);
      for (saved in item.components) loadComponent(entity, saved);
    }

    isReady = true;
    for (entity in entities) for (component in entity.components) component.onCreate();
    if (mode == Game) for (warning in warnings) Sys.println('Sahne uyarısı: $warning');
  }

  public function toData() : SceneData {
    var data = new SceneData(scene.data.SceneFormat.VERSION);
    for (entity in entities) data.entities.push(saveEntity(entity));
    return data;
  }

  public function start() {
    if (mode != Game) return;
    for (entity in entities.copy()) for (component in entity.components) component.onStart();
  }

  public function update(dt : Float) {
    if (mode != Game) return;
    for (entity in entities) {
      if (!entity.active) continue;
      for (component in entity.components) component.onUpdate(dt);
    }
  }

  function loadComponent(entity : Entity, saved : ComponentData) {
    var component = registry.create(saved.type);
    if (component == null) {
      warnings.push('${entity.name}: tanınmayan bileşen ${saved.type}');
      entity.unknownComponents.push(saved);
      return;
    }
    for (name => value in saved.fields) {
      if (component.writeField(name, value)) continue;
      warnings.push('${entity.name}: ${saved.type} bileşeninde tanınmayan alan $name');
      component.unknownFields.set(name, value);
    }
    entity.addComponent(component);
  }

  function saveEntity(entity : Entity) {
    var data = new EntityData(entity.id, entity.name);
    data.parent = entity.parent == null ? null : entity.parent.id;
    data.active = entity.active;
    data.position = [entity.x, entity.y, entity.z];
    data.rotation = [entity.rotX, entity.rotY, entity.rotZ];
    data.scale = [entity.scaleX, entity.scaleY, entity.scaleZ];
    for (component in entity.components) {
      var saved = new ComponentData(component.componentId());
      for (field in component.describeFields()) saved.fields.set(field.name, component.readField(field.name));
      for (name => value in component.unknownFields) saved.fields.set(name, value);
      data.components.push(saved);
    }
    for (saved in entity.unknownComponents) data.components.push(saved);
    return data;
  }
}
