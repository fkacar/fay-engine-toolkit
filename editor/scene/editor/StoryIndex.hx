package scene.editor;

import scene.data.SceneFormat;
import scene.story.StoryLink;
import scene.story.StoryLink.StoryLinks;
import scene.world.WorldData;

typedef StoryEntry = {
  var link : StoryLink;
  var label : String;            // tasarımcının göreceği yer: "Muhtar kapısı (Tetikleyici)"
  var ?entity : String;          // nesne kimliği
  var ?loaded : Bool;
  var ?dialog : String;
  var ?node : Int;
}

// Dünyadaki bütün görev bağlantıları: yüklü nesneler bellekten, yüklü olmayan hücreler diskten,
// diyaloglar düğümlerinden. Yanlış yazılmış olay veya değişken adı burada eşsiz kalır.
class StoryIndex {
  static inline var CACHE_SECONDS = 2.;

  static var cache : Array<StoryEntry> = [];
  static var cacheRevision = -1;
  static var cacheTime = 0.;

  public static function build(editor : Editor) : Array<StoryEntry> {
    var now = haxe.Timer.stamp();
    if (editor.commands.revision == cacheRevision && now - cacheTime < CACHE_SECONDS) return cache;
    cacheRevision = editor.commands.revision;
    cacheTime = now;
    var entries : Array<StoryEntry> = [];
    for (entity in editor.scene.entities)
      for (component in entity.components)
        for (link in component.storyLinks())
          entries.push({link: link, label: '${entity.name} (${component.title()})', entity: entity.id, loaded: true});
    var world = editor.document.world;
    if (world != null)
      for (cell in world.data.cells()) {
        if (world.isLoaded(cell)) continue;
        var text = DiskGuard.read("res/" + world.data.path(cell, WorldData.OBJECTS_SUFFIX));
        if (text == null) continue;
        var data = try SceneFormat.read(text) catch (e : Dynamic) continue;
        for (item in data.entities)
          for (saved in item.components) {
            var sample = editor.scene.registry.create(saved.type);
            if (sample == null) continue;
            for (name => value in saved.fields) sample.writeField(name, value);
            for (link in sample.storyLinks())
              entries.push({link: link, label: '${item.name} (${sample.title()}, ${world.data.title(cell)}, yüklü değil)', entity: item.id, loaded: false});
          }
      }
    for (id in editor.dialogs.ids()) {
      var dialog = editor.dialogs.dialogs.get(id);
      for (node in dialog.nodes)
        for (link in StoryLinks.ofNode(node))
          entries.push({link: link, label: 'Diyalog ${dialog.title}', dialog: id, node: node.id});
    }
    cache = entries.filter(entry -> entry.link.name != null && entry.link.name != "");
    return cache;
  }

  // Bekleyeni olmayan olay, yayanı olmayan bekleme, ayarlayanı olmayan değişken. Oyunun kodu da olay
  // yayabilir veya değişken ayarlayabilir; uyarı bunu bilemez, mesaj bu yüzden "hiçbir diyalog veya bileşen" der.
  public static function issues(entries : Array<StoryEntry>) : Array<{message : String, entry : StoryEntry}> {
    function names(kind : String) return [for (entry in entries) if (entry.link.kind == kind) entry.link.name];
    var emitted = names(StoryLinks.EMITS), listened = names(StoryLinks.LISTENS), set = names(StoryLinks.SETS);
    var found = [];
    for (entry in entries) {
      var name = entry.link.name;
      var message = switch (entry.link.kind) {
        case StoryLinks.LISTENS if (emitted.indexOf(name) < 0): '${entry.label}: "$name" olayını bekliyor ama hiçbir diyalog veya bileşen bu olayı yaymıyor';
        case StoryLinks.EMITS if (listened.indexOf(name) < 0): '${entry.label}: "$name" olayını yayıyor ama bekleyen tetikleyici yok';
        case StoryLinks.READS if (set.indexOf(name) < 0): '${entry.label}: "$name" değişkenine bakıyor ama hiçbir eylem onu ayarlamıyor';
        default: null;
      };
      if (message != null) found.push({message: message, entry: entry});
    }
    return found;
  }
}
