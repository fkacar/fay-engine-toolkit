package scene.editor.panels;

import imgui.ImGui;
import scene.editor.TranslationStatus;
import scene.story.Dialog;

// Çeviriler paneli (docs/DIL_PLANI.md, D8): kaynak dil dışındaki her dilin eksik, eskimiş ve fazla çevirileri, tablo ve
// diyalog başına sayılarla. Bir hücreye tıklanınca Veri panelinde o tablo o dille açılır ve satır gösterilir; diyalogda
// diyalog çalışma alanı o dille o düğümde açılır. Sayım ajanın list_translations aracıyla aynı yoldan (TranslationStatus).
class TranslationPanel {
  // Durum yeniden hesaplanır: geçmiş değişince ya da en geç bu kadar saniyede bir (diskten gelen değişiklikler).
  static inline var REFRESH = 2.;

  var editor : Editor;
  var reports : Array<TranslationReport> = [];
  var revision = -1;
  var age = 0.;
  // Çizilen kare sayısı (sınama panelin gerçekten çizildiğini görür).
  public var frames(default, null) = 0;

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function current() : Array<TranslationReport> {
    refresh(0);
    return reports;
  }

  function refresh(dt : Float) {
    age += dt;
    if (revision == editor.commands.revision && age < REFRESH) return;
    revision = editor.commands.revision;
    age = 0;
    reports = TranslationStatus.report(editor);
  }

  // Dil başına toplam: eksik, eskimiş, fazla.
  public static function totals(reports : Array<TranslationReport>, language : String) : {missing : Int, stale : Int, extra : Int} {
    var total = {missing: 0, stale: 0, extra: 0};
    for (report in reports) if (report.language == language) {
      total.missing += report.missing.length;
      total.stale += report.stale.length;
      total.extra += report.extra.length;
    }
    return total;
  }

  public function draw() {
    frames++;
    var languages = TranslationStatus.others(editor);
    if (languages.length == 0) {
      ImGui.textDisabled("Oyun dil bildirmiyor: çeviri yok");
      return;
    }
    refresh(hxd.Timer.dt);
    ImGui.textDisabled('Kaynak dil: ${editor.sourceLanguage}. Bir hücreye tıkla: Veri panelinde ya da diyalogda o dille açılır.');
    for (language in languages) {
      var total = totals(reports, language);
      var label = total.missing + total.stale + total.extra == 0 ? '$language: tam'
        : '$language: ${total.missing} eksik, ${total.stale} eskimiş' + (total.extra > 0 ? ', ${total.extra} fazla' : '');
      if (!ImGui.collapsingHeader('$label###dil_$language', ImGuiTreeNodeFlags.DefaultOpen)) continue;
      for (report in reports) if (report.language == language) drawReport(report);
    }
  }

  function drawReport(report : TranslationReport) {
    var count = report.missing.length + report.stale.length + report.extra.length;
    if (count == 0) return;
    var title = '${report.title} (${report.table}): ${report.missing.length} eksik, ${report.stale.length} eskimiş'
      + (report.extra.length > 0 ? ', ${report.extra.length} fazla' : '');
    if (!ImGui.treeNode('$title###${report.language}_${report.table}')) return;
    var source = TranslationStatus.source(editor, report.table);
    for (state in [{keys: report.missing, name: "eksik"}, {keys: report.stale, name: "eskimiş"}]) for (key in state.keys) {
      var cell = TranslationStatus.split(key);
      var row = source == null ? null : source.find(cell.row);
      var text : String = row == null || row.get(cell.column) == null ? "" : row.get(cell.column);
      if (ImGui.selectable('$key  [${state.name}]  $text###${report.language}_${report.table}_$key')) jump(report.language, report.table, key);
      if (ImGui.isItemHovered()) ImGui.setTooltip(state.name == "eksik" ? "Çevirisi yok: oyunda kaynak metin görünür. Tıkla, çevirisini yaz."
        : "Kaynak metin çeviriden sonra değişti. Tıkla, gözden geçir; hâlâ doğruysa Doğru.");
    }
    for (key in report.extra) ImGui.textDisabled('$key  [fazla: kaynakta yok]');
    ImGui.treePop();
  }

  // Hücrenin düzenlendiği yer: tabloda Veri paneli, diyalogda diyalog çalışma alanı; ikisi de o dille.
  public function jump(language : String, table : String, key : String) {
    var cell = TranslationStatus.split(key);
    if (StringTools.startsWith(table, Dialog.TEXT_TABLE_PREFIX)) {
      var node = Std.parseInt(cell.row.split(".")[0]);
      editor.dialogWorkspace.openIn(table.substr(Dialog.TEXT_TABLE_PREFIX.length), node == null ? 0 : node, language);
      return;
    }
    editor.revealData(table, cell.row, language);
  }
}
