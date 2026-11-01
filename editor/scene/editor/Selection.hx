package scene.editor;

import scene.Entity;
import scene.SceneInstance;

class Selection {
  public var items(default, null) : Array<Entity> = [];
  public var primary(get, never) : Null<Entity>;

  public function new() {}

  public function set(entities : Array<Entity>) {
    items = entities.copy();
  }

  public function clear() {
    items = [];
  }

  public function has(entity : Entity) {
    return items.indexOf(entity) >= 0;
  }

  public function add(entity : Entity) {
    if (!has(entity)) items.push(entity);
  }

  public function toggle(entity : Entity) {
    if (!items.remove(entity)) items.push(entity);
  }

  // Geri alma nesneyi sahneden çıkarmış olabilir.
  public function purge(scene : SceneInstance) {
    items = items.filter(entity -> scene.contains(entity));
  }

  // Üst nesnesi de seçili olanlar elenir: taşıma ve silme onları zaten etkiler.
  public function roots() : Array<Entity> {
    return items.filter(entity -> {
      var parent = entity.parent;
      while (parent != null) {
        if (has(parent)) return false;
        parent = parent.parent;
      }
      return true;
    });
  }

  function get_primary() {
    return items.length == 0 ? null : items[items.length - 1];
  }
}
