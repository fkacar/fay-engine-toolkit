package scene.data;

import scene.data.SceneData;

typedef ExpandedEntity = {
  var data : EntityData;     // farklar uygulanmış hali
  var base : EntityData;     // prefab'daki hali, kayıtta farklar buna göre bulunur
  var relative : String;     // instance köküne göre kimlik, kök için boş
}

// Prefab dosyası tek köklü küçük bir sahnedir. Instance açılınca nesneler `kök/kimlik`
// biçiminde kalıcı kimlik alır, böylece aynı prefab sahnede birden çok kez durabilir.
class Prefabs {
  public static inline var SEPARATOR = "/";
  public static inline var COMPONENT_FIELD = "component:";

  // Plan: tek seviye iç içe. Prefab'ın kendisini içermesi de burada biter.
  static inline var MAX_DEPTH = 1;

  public static function expand(instance : EntityData, load : String->SceneData, warn : String->Void, depth = 0) : Array<ExpandedEntity> {
    var prefab = load(instance.prefab);
    var root = rootOf(prefab);
    if (root == null) throw '${instance.prefab}: prefab tek köklü olmalı';

    var ids = new Map<String, String>();
    for (item in prefab.entities) ids.set(item.id, item == root ? instance.id : instance.id + SEPARATOR + item.id);

    var entries : Array<ExpandedEntity> = [];
    for (item in prefab.entities) {
      var copy = item.clone();
      copy.id = ids.get(item.id);
      copy.parent = item == root ? instance.parent : ids.get(item.parent);
      remapReferences(copy, ids);
      if (item == root) {
        copy.name = instance.name;
        copy.active = instance.active;
        copy.position = instance.position.copy();
        copy.rotation = instance.rotation.copy();
        copy.scale = instance.scale.copy();
      }
      var relative = item == root ? "" : item.id;
      if (item.prefab == null || depth >= MAX_DEPTH) {
        if (item.prefab != null) warn('${instance.name}: ${item.name} üç seviye iç içe prefab, açılmadı');
        copy.prefab = null;
        entries.push({data: copy, base: copy.clone(), relative: relative});
        continue;
      }
      for (entry in expand(copy, load, warn, depth + 1))
        entries.push({
          data: entry.data,
          base: entry.data.clone(),
          relative: entry.relative == "" ? relative : relative == "" ? entry.relative : relative + SEPARATOR + entry.relative,
        });
    }

    for (change in instance.overrides) {
      var entry = Lambda.find(entries, candidate -> candidate.relative == change.target);
      if (entry == null) warn('${instance.name}: prefab\'da olmayan nesne için fark atlandı (${change.target})');
      else if (!applyOverride(entry.data, change)) warn('${instance.name}: uygulanamayan fark atlandı (${change.field})');
    }
    return entries;
  }

  public static function rootOf(prefab : SceneData) : Null<EntityData> {
    var roots = prefab.entities.filter(item -> item.parent == null);
    return roots.length == 1 ? roots[0] : null;
  }

  public static function applyOverride(data : EntityData, change : OverrideData) : Bool {
    switch (change.field) {
      case "name": data.name = change.value;
      case "active": data.active = change.value;
      case "position": data.position = change.value;
      case "rotation": data.rotation = change.value;
      case "scale": data.scale = change.value;
      default:
        var parts = componentField(change.field);
        if (parts == null) return false;
        var component = Lambda.find(data.components, item -> item.type == parts.type);
        if (component == null) return false;
        component.fields.set(parts.name, change.value);
    }
    return true;
  }

  public static function componentField(field : String) : Null<{type : String, name : String}> {
    if (!StringTools.startsWith(field, COMPONENT_FIELD)) return null;
    var parts = field.split(":");
    return parts.length == 3 ? {type: parts[1], name: parts[2]} : null;
  }

  // Instance'taki farkları prefab dosyasına işler. Kök dönüşümü instance'a aittir, prefab'a gitmez.
  public static function applyToPrefab(prefab : SceneData, overrides : Array<OverrideData>) {
    var root = rootOf(prefab);
    for (change in overrides) {
      var pieces = change.target.split(SEPARATOR);
      var item = change.target == "" ? root : Lambda.find(prefab.entities, entity -> entity.id == pieces[0]);
      if (item == null) continue;
      if (pieces.length > 1 || item.prefab != null && componentField(change.field) != null) {
        var rest = pieces.slice(1).join(SEPARATOR);
        item.overrides = item.overrides.filter(old -> old.target != rest || old.field != change.field);
        item.overrides.push(new OverrideData(rest, change.field, change.value));
        sort(item.overrides);
      } else {
        applyOverride(item, change);
      }
    }
  }

  public static function sort(overrides : Array<OverrideData>) {
    overrides.sort((a, b) -> {
      var left = a.target + "\n" + a.field, right = b.target + "\n" + b.field;
      return left < right ? -1 : left > right ? 1 : 0;
    });
  }

  // Prefab içi nesne referansları da yeni kimliği göstermeli.
  static function remapReferences(item : EntityData, ids : Map<String, String>) {
    for (component in item.components)
      for (name => value in component.fields)
        if (Std.isOfType(value, String) && ids.exists(value)) component.fields.set(name, ids.get(value));
  }
}
