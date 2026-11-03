package scene.editor.panels;

import imgui.ImGui;
import scene.editor.SaveInspector;

// Oyun > Kayıttan oyna…: hata ayıklama klasöründeki kayıtlar ve seçilenin salt okunur raporu. "Bu kayıttan oyna"
// oyunu o kayıtla açar (kayıt bir hata ayıklama seferine kopyalanır, asıl dosyaya yazılmaz).
class SavesWindow {
  public static inline var TITLE = "Kayıtlar";

  public var visible = false;

  var editor : Editor;
  var listings : Array<SaveListing> = [];
  var selected : Null<String>;
  var report : Null<SaveInspection>;
  var problem : Null<String>;

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function open() {
    visible = true;
    refresh();
  }

  public function refresh() {
    var inspector = editor.saveInspector;
    listings = inspector == null ? [] : inspector.list();
    if (selected != null && !Lambda.exists(listings, item -> item.path == selected)) selected = null;
    if (selected != null) select(selected);
  }

  public function select(path : String) {
    selected = path;
    problem = null;
    report = try editor.saveInspector.inspect(path) catch (e : Dynamic) {
      problem = 'Kayıt okunamadı: $e';
      null;
    };
  }

  public function draw() {
    if (!visible || editor.saveInspector == null) return;
    var scale = editor.interfaceScale;
    ImGui.setNextWindowSize({x: 760 * scale, y: 620 * scale}, 4);
    if (ImGui.begin('$TITLE##kayit-penceresi')) {
      if (ImGui.button("Yenile")) refresh();
      ImGui.sameLine();
      var canPlay = selected != null && !editor.isPlaying();
      if (ImGui.button("Bu kayıttan oyna") && canPlay) editor.playFromSave(selected);
      ImGui.sameLine();
      if (ImGui.button("Kapat")) visible = false;
      ImGui.textDisabled('Oyuncudan gelen kayıtları ${editor.saveInspector.folder}/ altına koy');
      ImGui.separator();
      if (listings.length == 0) ImGui.textDisabled("Kayıt yok");
      ImGui.beginChild("##kayit-listesi", {x: 0, y: 150 * scale}, true);
      for (item in listings)
        if (ImGui.selectable('${item.title}   ${item.detail}##${item.path}', item.path == selected)) select(item.path);
      ImGui.endChild();
      if (problem != null) ImGui.textColored({x: 1, y: 0.45, z: 0.35, w: 1}, problem);
      if (report != null) drawReport(report);
    }
    ImGui.end();
  }

  function drawReport(report : SaveInspection) {
    ImGui.beginChild("##kayit-raporu");
    for (s in 0...report.sections.length) {
      var section = report.sections[s];
      if (!ImGui.collapsingHeader('${section.title} (${section.lines.length})##rapor$s', s < 3 ? imgui.ImGui.ImGuiTreeNodeFlags.DefaultOpen : 0)) continue;
      for (l in 0...section.lines.length) {
        var line = section.lines[l];
        if (line.action != null) {
          if (ImGui.smallButton('${line.action.label}##eylem$s-$l')) {
            line.action.run();
            // Eylem yeni dosya yazmış olabilir (Sıfırla): liste ve rapor tazelenir.
            refresh();
            return endReport();
          }
          ImGui.sameLine();
        }
        if (line.entity == null) ImGui.textWrapped(line.text);
        else if (ImGui.selectable('${line.text}##satir$s-$l')) goTo(line.entity, line.cell);
      }
    }
    endReport();
  }

  function endReport() {
    ImGui.endChild();
  }

  // Rapordaki nesne: hücresi yüklü değilse yüklenir, seçilir, kamera ona gider.
  public function goTo(id : String, ?cell : Int) {
    var world = editor.document.world;
    if (editor.scene.find(id) == null && world != null && cell != null && cell != scene.world.WorldData.GLOBAL) world.load(cell);
    var entity = editor.scene.find(id);
    if (entity == null) {
      editor.show('Nesne dünyada yok: $id', true);
      return;
    }
    editor.selection.set([entity]);
    editor.actions.focus();
  }
}
