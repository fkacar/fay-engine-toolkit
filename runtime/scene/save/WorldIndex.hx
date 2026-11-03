package scene.save;

import scene.data.Prefabs;
import scene.data.SceneData;
import scene.data.SceneFormat;
import scene.world.WorldData;

typedef IndexedEntity = {id : String, name : String, cell : Int, types : Array<String>};

// Dünyadaki bütün tasarlanmış nesneler (hücre dosyalarından, prefab içleri açılmış): yükleme raporu kayıttaki
// farklardan hangilerinin artık dünyada olmadığını (yetim) ve yerine geçebilecek nesneyi buradan bulur.
class WorldIndex {
  public var entities(default, null) = new Map<String, IndexedEntity>();

  public function new() {}

  public static function build(world : WorldData, read : String->Null<String>, prefabs : String->SceneData) : WorldIndex {
    var index = new WorldIndex();
    for (cell in [WorldData.GLOBAL].concat(world.cells())) {
      var text = read(world.path(cell, WorldData.OBJECTS_SUFFIX));
      if (text != null) index.addScene(SceneFormat.read(text), cell, prefabs);
    }
    return index;
  }

  public function addScene(data : SceneData, cell : Int, prefabs : String->SceneData) {
    for (item in data.entities) {
      var parts = item.prefab == null ? [item] : try [for (part in Prefabs.expand(item, prefabs, _ -> {})) part.data] catch (e : Dynamic) [item];
      for (part in parts)
        entities.set(part.id, {id: part.id, name: part.name, cell: cell, types: [for (component in part.components) component.type]});
    }
  }

  public function exists(id : String) : Bool {
    return entities.exists(id);
  }

  // Yerine geçebilecekler: aynı hücrede, verilen türden bileşeni olanlar.
  public function candidates(cell : Int, type : String) : Array<IndexedEntity> {
    return [for (entity in entities) if (entity.cell == cell && entity.types.indexOf(type) >= 0) entity];
  }
}
