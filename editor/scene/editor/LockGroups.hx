package scene.editor;

import scene.Entity;
import scene.SceneInstance;

// Birbirine kilitlenen nesneler birlikte seçilir ve sahnede tek parça gibi düzenlenir.
// Kilitsiz çoklu seçimde toplu düzenleme yoktur.
class LockGroups {
  var groups : Array<Array<Entity>> = [];

  public function new() {}

  public function lock(entities : Array<Entity>) {
    if (entities.length < 2) return;
    unlock(entities);
    groups.push(entities.copy());
  }

  public function unlock(entities : Array<Entity>) {
    groups = groups.filter(group -> !Lambda.exists(group, entity -> entities.indexOf(entity) >= 0));
  }

  public function groupOf(entity : Entity) : Null<Array<Entity>> {
    return Lambda.find(groups, group -> group.indexOf(entity) >= 0);
  }

  public function isLocked(entities : Array<Entity>) {
    if (entities.length < 2) return false;
    var group = groupOf(entities[0]);
    return group != null && Lambda.foreach(entities, entity -> group.indexOf(entity) >= 0);
  }

  // Silinen üye gruptan düşmez: silme geri alınınca kilit de geri gelir.
  public function expand(entities : Array<Entity>, scene : SceneInstance) : Array<Entity> {
    var result = [];
    for (entity in entities) {
      var group = groupOf(entity);
      var members = group == null ? [entity] : group;
      for (member in members) if (result.indexOf(member) < 0 && scene.contains(member)) result.push(member);
    }
    return result;
  }

  public function toIds() : Array<Array<String>> {
    return [for (group in groups) [for (entity in group) entity.id]];
  }

  public function load(saved : Array<Array<String>>, scene : SceneInstance) {
    groups = [];
    for (ids in saved) {
      var group = [for (id in ids) if (scene.find(id) != null) scene.find(id)];
      if (group.length >= 2) groups.push(group);
    }
  }
}
