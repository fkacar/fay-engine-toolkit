package scene;

import scene.data.Prefabs;
import scene.data.SceneData;
import scene.data.SceneFormat;

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
  // Prefab dosyasının metnini verir. `res` köküne göre yol alır.
  public var prefabLoader : Null<String->String>;

  var prefabs = new Map<String, SceneData>();
  var isReady = false;
  var hasStarted = false;
  var services = new Map<String, Dynamic>();
  var byId = new Map<String, Entity>();

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
    return byId.get(id);
  }

  public function createEntity(name : String, ?id : String) : Entity {
    var entity = new Entity(this, id == null ? Guid.make() : id, name);
    entities.push(entity);
    byId.set(entity.id, entity);
    return entity;
  }

  public function destroyEntity(entity : Entity) {
    for (child in entity.children.copy()) destroyEntity(child);
    for (component in entity.components) destroyComponent(component);
    entity.setParent(null);
    entity.object.remove();
    entities.remove(entity);
    byId.remove(entity.id);
  }

  // Silme geri alınabilsin diye nesne yok edilmez: komutlar aynı nesneyi tutmaya devam eder.
  public function detach(entity : Entity) : DetachedEntity {
    var slots = [];
    collect(entity, slots);
    for (slot in slots) for (component in slot.entity.components) destroyComponent(component);
    for (slot in slots) {
      slot.index = entities.indexOf(slot.entity);
      entities.remove(slot.entity);
      byId.remove(slot.entity.id);
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
    while (i-- > 0) {
      entities.insert(slots[i].index, slots[i].entity);
      byId.set(slots[i].entity.id, slots[i].entity);
    }
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
    hasStarted = false;
    for (entity in entities.filter(entity -> entity.parent == null)) destroyEntity(entity);
    warnings = [];
  }

  public function load(data : SceneData) {
    clear();
    prefabs = new Map();
    instantiate(data.entities);
    if (mode == Game) for (warning in warnings) Sys.println('Sahne uyarısı: $warning');
  }

  // Dosyadaki, panodaki veya çoğaltılan nesneleri sahneye ekler.
  public function instantiate(items : Array<EntityData>) : Array<Entity> {
    isReady = false;
    var created = [];
    var flat = [];
    for (item in items) {
      var entries = item.prefab == null ? null : expandPrefab(item);
      if (entries == null) {
        var entity = spawn(item);
        // Açılamayan instance sahnede kalır, kayıtta yolu ve farkları korunur.
        if (item.prefab != null) {
          entity.prefab = item.prefab;
          entity.instanceRoot = entity;
          entity.unresolvedOverrides = item.overrides;
        }
        created.push(entity);
        flat.push(item);
        continue;
      }
      var root = null;
      for (entry in entries) {
        var entity = spawn(entry.data);
        if (root == null) root = entity;
        entity.instanceRoot = root;
        entity.prefabBase = entry.base;
        entity.prefabRelative = entry.relative;
        created.push(entity);
        flat.push(entry.data);
      }
      root.prefab = item.prefab;
    }

    // Üst nesne dosyada alttan sonra gelebilir, bu yüzden bağlar ayrı geçişte kurulur.
    for (i in 0...flat.length) {
      var item = flat[i];
      if (item.parent == null) continue;
      var parent = find(item.parent);
      if (parent == null) warnings.push('${item.name}: üst nesne bulunamadı (${item.parent})');
      else created[i].setParent(parent);
    }

    for (i in 0...flat.length) for (saved in flat[i].components) loadComponent(created[i], saved);

    isReady = true;
    for (entity in created) for (component in entity.components) createComponent(component);
    return created;
  }

  // Prefab değişince instance yeniden kurulmaz: nesneler aynı kaldığı için undo geçmişi geçerli
  // kalır. Farklar yapıyı değiştiremediğinden yalnızca değerler yazılır.
  public function syncInstance(data : EntityData) {
    if (find(data.id) == null) return;
    for (entry in Prefabs.expand(data, prefabData, warn)) {
      var entity = find(entry.data.id);
      if (entity == null) {
        warn('${data.name}: prefab\'ın yapısı değişmiş, sahneyi yeniden aç');
        continue;
      }
      entity.prefabBase = entry.base;
      syncValues(entity, entry.data);
    }
  }

  public function forgetPrefab(path : String) {
    prefabs.remove(path);
  }

  // Açılabilen tüm instance'lar, farklarıyla birlikte.
  public function instances() : Array<EntityData> {
    return [for (entity in entities) if (entity.prefab != null && entity.isPrefabResolved) saveEntity(entity)];
  }

  public function prefabData(path : String) : SceneData {
    var data = prefabs.get(path);
    if (data != null) return data;
    if (prefabLoader == null) throw "prefab yükleyici tanımlı değil";
    data = SceneFormat.read(prefabLoader(path));
    prefabs.set(path, data);
    return data;
  }

  public function toData() : SceneData {
    var data = new SceneData(SceneFormat.VERSION);
    for (entity in entities) if (!entity.isPrefabPart) data.entities.push(saveEntity(entity));
    return data;
  }

  // Nesne ve tüm alt nesneleri, sahnedeki sırasıyla. Kopyası alınan prefab parçası bağımsız nesne olur.
  public function toDataOf(selected : Array<Entity>) : SceneData {
    var data = new SceneData(SceneFormat.VERSION);
    for (entity in entities) {
      if (!Lambda.exists(selected, root -> entity.isInside(root))) continue;
      var comesWithRoot = entity.isPrefabPart && Lambda.exists(selected, root -> entity.instanceRoot.isInside(root));
      if (!comesWithRoot) data.entities.push(saveEntity(entity));
    }
    return data;
  }

  // Kökü verilen koşula uyan nesneler: dünyada her hücre kendi dosyasına böyle yazılır.
  public function toDataWhere(rootMatches : Entity->Bool) : SceneData {
    var data = new SceneData(SceneFormat.VERSION);
    for (entity in entities) if (!entity.isPrefabPart && rootMatches(entity.root)) data.entities.push(saveEntity(entity));
    return data;
  }

  // Instance'ın prefab'dan farkları. Elle takip edilmez: gizmo, Inspector ve komutların hepsi
  // aynı alanları değiştirdiği için kayıtta karşılaştırmak yeterlidir.
  public function overridesOf(root : Entity) : Array<OverrideData> {
    if (root.prefabBase == null) return root.unresolvedOverrides;
    var result = [];
    for (entity in entities) {
      if (entity.instanceRoot != root) continue;
      var base = entity.prefabBase;
      var target = entity.prefabRelative;
      function compare(field : String, was : Dynamic, now : Dynamic) {
        if (!sameValue(was, now)) result.push(new OverrideData(target, field, now));
      }
      if (entity != root) {
        compare("name", base.name, entity.name);
        compare("active", base.active, entity.active);
        compare("position", base.position, [entity.x, entity.y, entity.z]);
        compare("rotation", base.rotation, [entity.rotX, entity.rotY, entity.rotZ]);
        compare("scale", base.scale, [entity.scaleX, entity.scaleY, entity.scaleZ]);
      }
      for (saved in base.components) {
        var component = componentOf(entity, saved.type);
        if (component == null) continue;
        var original = savedCopy(saved);
        for (field in component.describeFields())
          compare(Prefabs.COMPONENT_FIELD + component.componentId() + ":" + field.name, original.readField(field.name), component.readField(field.name));
      }
    }
    Prefabs.sort(result);
    return result;
  }

  public function start() {
    if (mode != Game) return;
    hasStarted = true;
    for (entity in entities.copy()) for (component in entity.components) component.onStart();
  }

  // Oyun sürerken gelen hücre: nesneler başlangıcı kaçırmasın.
  public function stream(items : Array<EntityData>) : Array<Entity> {
    var created = instantiate(items);
    if (hasStarted) for (entity in created) for (component in entity.components) component.onStart();
    return created;
  }

  public function update(dt : Float) {
    if (mode != Game) return;
    for (entity in entities) {
      if (!entity.active) continue;
      for (component in entity.components) component.onUpdate(dt);
    }
  }

  function syncValues(entity : Entity, item : EntityData) {
    entity.name = item.name;
    entity.active = item.active;
    entity.setPosition(item.position[0], item.position[1], item.position[2]);
    entity.setRotation(item.rotation[0], item.rotation[1], item.rotation[2]);
    entity.setScale(item.scale[0], item.scale[1], item.scale[2]);
    for (saved in item.components) {
      var component = componentOf(entity, saved.type);
      if (component == null) continue;
      var target = savedCopy(saved);
      var changed = false;
      for (field in component.describeFields()) {
        var value = target.readField(field.name);
        if (sameValue(value, component.readField(field.name))) continue;
        component.writeField(field.name, value);
        changed = true;
      }
      if (changed) component.refresh();
    }
  }

  function componentOf(entity : Entity, type : String) {
    return Lambda.find(entity.components, item -> item.componentId() == type || item.formerIds().indexOf(type) >= 0);
  }

  // Kayıttaki değerleri taşıyan, sahneye bağlı olmayan kopya.
  function savedCopy(saved : ComponentData) {
    var component = registry.create(saved.type);
    for (name => value in saved.fields) component.writeField(name, value);
    return component;
  }

  static function sameValue(a : Dynamic, b : Dynamic) {
    return SceneFormat.writeValue(a) == SceneFormat.writeValue(b);
  }

  function spawn(item : EntityData) {
    var entity = createEntity(item.name, item.id);
    entity.setPosition(item.position[0], item.position[1], item.position[2]);
    entity.setRotation(item.rotation[0], item.rotation[1], item.rotation[2]);
    entity.setScale(item.scale[0], item.scale[1], item.scale[2]);
    entity.active = item.active;
    return entity;
  }

  // Açılamazsa null döner: bozuk prefab sahneyi düşürmez.
  function expandPrefab(item : EntityData) {
    try {
      return Prefabs.expand(item, prefabData, warn);
    } catch (e : Dynamic) {
      if (mode == Game) throw e;
      warn('${item.name}: prefab açılamadı (${item.prefab}): $e');
      return null;
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
    if (entity.prefab != null) {
      data.prefab = entity.prefab;
      data.overrides = overridesOf(entity);
      return data;
    }
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
