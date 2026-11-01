package scene;

import scene.data.SceneData;

// Sahneden ayrılmış alt ağaç. attach aynı nesneleri aynı sıraya geri koyar.
typedef DetachedEntity = {
  var entity : Entity;
  var parent : Null<Entity>;
  var childIndex : Int;
  var slots : Array<EntitySlot>;
}

typedef EntitySlot = {
  var entity : Entity;
  var index : Int;
}

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
    for (component in entity.components) destroyComponent(component);
    entity.setParent(null);
    entity.object.remove();
    entities.remove(entity);
  }

  // Silme geri alınabilsin diye nesne yok edilmez: komutlar aynı nesneyi tutmaya devam eder.
  public function detach(entity : Entity) : DetachedEntity {
    var slots = [];
    collect(entity, slots);
    for (slot in slots) for (component in slot.entity.components) destroyComponent(component);
    for (slot in slots) {
      slot.index = entities.indexOf(slot.entity);
      entities.remove(slot.entity);
    }
    var parent = entity.parent;
    var childIndex = parent == null ? 0 : parent.children.indexOf(entity);
    if (parent != null) parent.children.remove(entity);
    entity.object.remove();
    return {entity: entity, parent: parent, childIndex: childIndex, slots: slots};
  }

  public function attach(detached : DetachedEntity) {
    var slots = detached.slots;
    var i = slots.length;
    // Çıkarıldığı sıranın tersiyle eklenir, böylece her nesne eski sırasına döner.
    while (i-- > 0) entities.insert(slots[i].index, slots[i].entity);
    if (detached.parent != null) detached.parent.children.insert(detached.childIndex, detached.entity);
    (detached.parent == null ? root : detached.parent.object).addChild(detached.entity.object);
    for (slot in slots) for (component in slot.entity.components) createComponent(component);
  }

  public function contains(entity : Entity) {
    return entities.indexOf(entity) >= 0;
  }

  // Editörde bozuk bir asset tüm sahneyi düşürmesin, uyarı olarak görünsün.
  public function createComponent(component : Component) {
    if (mode == Game) component.onCreate();
    else try component.onCreate() catch (e : Dynamic) warn('${component.entity.name}: ${component.componentId()} kurulamadı: $e');
    component.entity.syncVisuals(component);
  }

  public function destroyComponent(component : Component) {
    if (mode == Game) {
      component.onDestroy();
      return;
    }
    try component.onDestroy() catch (e : Dynamic) warn('${component.entity.name}: ${component.componentId()} kapatılamadı: $e');
  }

  public function clear() {
    isReady = false;
    for (entity in entities.filter(entity -> entity.parent == null)) destroyEntity(entity);
    warnings = [];
  }

  public function load(data : SceneData) {
    clear();
    instantiate(data.entities);
    if (mode == Game) for (warning in warnings) Sys.println('Sahne uyarısı: $warning');
  }

  // Dosyadaki, panodaki veya çoğaltılan nesneleri sahneye ekler.
  public function instantiate(items : Array<EntityData>) : Array<Entity> {
    isReady = false;
    var created = [];
    for (item in items) {
      var entity = createEntity(item.name, item.id);
      created.push(entity);
      entity.setPosition(item.position[0], item.position[1], item.position[2]);
      entity.setRotation(item.rotation[0], item.rotation[1], item.rotation[2]);
      entity.setScale(item.scale[0], item.scale[1], item.scale[2]);
      entity.active = item.active;
    }

    // Üst nesne dosyada alttan sonra gelebilir, bu yüzden bağlar ayrı geçişte kurulur.
    for (i in 0...items.length) {
      var item = items[i];
      if (item.parent == null) continue;
      var parent = find(item.parent);
      if (parent == null) warnings.push('${item.name}: üst nesne bulunamadı (${item.parent})');
      else created[i].setParent(parent);
    }

    for (i in 0...items.length) for (saved in items[i].components) loadComponent(created[i], saved);

    isReady = true;
    for (entity in created) for (component in entity.components) createComponent(component);
    return created;
  }

  public function toData() : SceneData {
    var data = new SceneData(scene.data.SceneFormat.VERSION);
    for (entity in entities) data.entities.push(saveEntity(entity));
    return data;
  }

  // Nesne ve tüm alt nesneleri, sahnedeki sırasıyla.
  public function toDataOf(selected : Array<Entity>) : SceneData {
    var data = new SceneData(scene.data.SceneFormat.VERSION);
    for (entity in entities) if (Lambda.exists(selected, root -> entity.isInside(root))) data.entities.push(saveEntity(entity));
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

  function collect(entity : Entity, slots : Array<EntitySlot>) {
    slots.push({entity: entity, index: 0});
    for (child in entity.children) collect(child, slots);
  }

  function warn(message : String) {
    if (warnings.indexOf(message) < 0) warnings.push(message);
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
