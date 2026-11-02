package scene.editor.panels;

import imgui.ImGui;
import scene.editor.commands.SetDialogCommand;

// Diyalog listesi. Ağaç burada değil, sahne görünümünün yerine açılan geniş düzenleyicide kurulur.
class DialogPanel {
  var editor : Editor;

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function draw() {
    var store = editor.dialogs;
    var workspace = editor.dialogWorkspace;
    workspace.newDialogButton();
    ImGui.sameLine();
    ImGui.textDisabled("Düzenlemek için çift tıkla veya Düzenle'ye bas");
    var ids = store.ids();
    if (ids.length == 0) {
      ImGui.textDisabled("Henüz diyalog yok");
      return;
    }
    var flags = ImGuiTableFlags.RowBg | ImGuiTableFlags.Borders | ImGuiTableFlags.Resizable | ImGuiTableFlags.ScrollY;
    if (!ImGui.beginTable("##diyaloglar", 4, flags)) return;
    var scale = editor.interfaceScale;
    ImGui.tableSetupColumn("Başlık", ImGuiTableColumnFlags.WidthStretch);
    ImGui.tableSetupColumn("Kimlik", ImGuiTableColumnFlags.WidthFixed, 140 * scale);
    ImGui.tableSetupColumn("Başlatan", ImGuiTableColumnFlags.WidthStretch);
    ImGui.tableSetupColumn("##islem", ImGuiTableColumnFlags.WidthFixed, 110 * scale);
    ImGui.tableHeadersRow();
    var removing : Null<String> = null;
    for (id in ids) {
      var dialog = store.dialogs.get(id);
      ImGui.tableNextRow();
      ImGui.pushID(id);
      ImGui.tableNextColumn();
      var chosen = workspace.isOpen && workspace.current == id;
      if (ImGui.selectable(dialog.title, chosen, ImGuiSelectableFlags.AllowDoubleClick) && ImGui.isMouseDoubleClicked(0)) workspace.open(id);
      ImGui.tableNextColumn();
      ImGui.textDisabled(id);
      ImGui.tableNextColumn();
      var starters = DataUsage.dialogStarters(editor, id);
      if (starters.length == 0) ImGui.textDisabled("yok");
      else ImGui.text(starters.length == 1 ? starters[0] : '${starters.length} yer');
      if (starters.length > 0 && ImGui.isItemHovered()) ImGui.setTooltip(starters.join("\n"));
      ImGui.tableNextColumn();
      if (ImGui.smallButton("Düzenle")) workspace.open(id);
      ImGui.sameLine();
      if (ImGui.smallButton("Sil")) removing = id;
      ImGui.popID();
    }
    ImGui.endTable();
    if (removing != null) remove(removing);
  }

  // Kullanılan diyalog silinmez: tetikleyici olmayan diyaloğu açmaya çalışırdı.
  function remove(id : String) {
    var used = DataUsage.findDialog(editor, id);
    if (used.length > 0) {
      editor.show('"$id" silinemez, kullanılıyor: ${DataUsage.describe(used)}', true);
      return;
    }
    if (editor.dialogWorkspace.current == id) editor.dialogWorkspace.close();
    editor.commands.execute(new SetDialogCommand("Diyalog sil", editor.dialogs, id, editor.dialogs.text(id), null));
  }
}
