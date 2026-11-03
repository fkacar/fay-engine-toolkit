package scene.editor.panels;

import haxe.DynamicAccess;
import imgui.ImGui;
import scene.data.DataTable;
import scene.editor.commands.SetTableCommand;

// Oyun verisi tabloları: fraksiyonlar, eşyalar. Hücreler doğrudan düzenlenir, her değişiklik
// Cmd+Z ile geri alınır ve sahneyle birlikte kaydedilir.
class DataPanel {
  static inline var TABLE_POPUP = "Yeni tablo";
  static inline var COLUMN_POPUP = "Yeni sütun";
  static inline var ID_TIP = "Satırın oyundaki adı. Bir sahne kullanıyorsa değiştirilemez, adı istediğin gibi değiştirebilirsin.";

  static inline var ID_WIDTH = 120.;
  static inline var DELETE_WIDTH = 34.;

  static var TYPE_TITLES = ["Metin", "Sayı", "Tam sayı", "Evet/Hayır", "Seçim", "Tablo bağlantısı", "Renk", "Varlık (dosya)"];

  var editor : Editor;
  var current = "";
  var editStart : Null<String>;
  var tableName = "";
  var tableTitle = "";
  var columnTitle = "";
  var columnType = 0;
  var columnOptions = "";
  var columnTable = "";
  var openTable = false;
  var openColumn = false;

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function draw() {
    editor.claimKeyboard();
    var store = editor.data;
    var names = store.names();
    if (!store.tables.exists(current)) current = names.length > 0 ? names[0] : "";
    if (ImGui.beginCombo("Tablo", current == "" ? "(yok)" : store.tables.get(current).title)) {
      for (name in names) {
        var chosen = name == current;
        if (ImGui.selectable(store.tables.get(name).title + "##" + name, chosen)) current = name;
      }
      ImGui.endCombo();
    }
    ImGui.sameLine();
    if (ImGui.smallButton("Yeni tablo")) openTable = true;
    drawTablePopup();
    if (current == "") {
      ImGui.textDisabled("Henüz tablo yok");
      return;
    }
    var table = store.tables.get(current);
    if (ImGui.smallButton("Satır ekle")) change("Satır ekle", data -> data.addRow(data.freeId("yeni")));
    ImGui.sameLine();
    if (ImGui.smallButton("Sütun ekle")) openColumn = true;
    drawColumnPopup();
    drawRows(table);
    if (ImGui.collapsingHeader("Sütunlar")) drawColumns(table);
  }

  function drawRows(table : DataTable) {
    var flags = ImGuiTableFlags.Resizable | ImGuiTableFlags.RowBg | ImGuiTableFlags.Borders | ImGuiTableFlags.ScrollX;
    if (!ImGui.beginTable("##satirlar", table.columns.length + 2, flags)) return;
    var scale = editor.interfaceScale;
    ImGui.tableSetupColumn("Kimlik", ImGuiTableColumnFlags.WidthFixed, ID_WIDTH * scale);
    for (column in table.columns) ImGui.tableSetupColumn(column.title, ImGuiTableColumnFlags.WidthFixed, widthOf(column.type) * scale);
    ImGui.tableSetupColumn("##sil", ImGuiTableColumnFlags.WidthFixed, DELETE_WIDTH * scale);
    ImGui.tableHeadersRow();
    var removing = -1;
    for (i in 0...table.rows.length) {
      var row = table.rows[i];
      ImGui.tableNextRow();
      ImGui.pushID('$i');
      ImGui.tableNextColumn();
      drawId(table, row);
      for (column in table.columns) {
        ImGui.tableNextColumn();
        ImGui.pushID(column.name);
        drawCell(table, row, column);
        ImGui.popID();
      }
      ImGui.tableNextColumn();
      if (ImGui.smallButton("Sil")) removing = i;
      ImGui.popID();
    }
    ImGui.endTable();
    if (removing >= 0) {
      var id : String = table.rows[removing].get("id");
      var used = DataUsage.find(editor, table.name, id);
      if (used.length > 0) editor.show('"$id" silinemez, kullanılıyor: ${DataUsage.describe(used)}', true);
      else change("Satır sil", data -> data.rows.splice(removing, 1));
    }
  }

  static function widthOf(type : String) : Float {
    return switch (type) {
      case DataTable.FLAG: 48;
      case DataTable.COLOR: 60;
      case DataTable.INTEGER, DataTable.NUMBER: 90;
      case DataTable.CHOICE: 120;
      default: 170;
    };
  }

  function drawId(table : DataTable, row : DynamicAccess<Dynamic>) {
    var id : String = row.get("id");
    ImGui.setNextItemWidth(-1);
    if (ImGui.inputText("##kimlik", id)) row.set("id", id);
    if (ImGui.isItemHovered()) ImGui.setTooltip(ID_TIP);
    if (ImGui.isItemActivated()) editStart = editor.data.text(current);
    if (!ImGui.isItemDeactivatedAfterEdit()) return;
    var clean = SceneDocument.cleanName(row.get("id"));
    var duplicate = Lambda.count(table.rows, other -> other.get("id") == clean) > 1;
    var before = editStart == null ? null : DataTable.read(current, editStart).rows[table.rows.indexOf(row)];
    var old : String = before == null ? clean : before.get("id");
    var used = old == clean ? [] : DataUsage.find(editor, table.name, old);
    if (clean == "" || duplicate || used.length > 0) {
      if (editStart != null) editor.data.apply(current, editStart);
      editStart = null;
      editor.show(clean == "" ? "Kimlik boş olamaz" : duplicate ? 'Bu kimlik zaten var: $clean'
        : '"$old" kimliği değişemez, kullanılıyor: ${DataUsage.describe(used)}', true);
      return;
    }
    row.set("id", clean);
    commit("Kimlik");
  }

  function drawCell(table : DataTable, row : DynamicAccess<Dynamic>, column : DataColumn) {
    var value : Dynamic = row.exists(column.name) ? row.get(column.name) : DataTable.defaultValue(column);
    ImGui.setNextItemWidth(-1);
    switch (column.type) {
      case DataTable.FLAG:
        var on : Bool = value;
        if (ImGui.checkbox("##deger", on)) change(column.title, data -> data.find(row.get("id")).set(column.name, on));
      case DataTable.CHOICE:
        var options = column.options == null ? [] : column.options;
        choose(row, column, value, options, option -> option);
      case DataTable.REFERENCE:
        var target = editor.data.tables.get(column.table);
        choose(row, column, value, target == null ? [] : [""].concat(target.ids()), id -> id == "" ? "(yok)" : target.label(id));
      case DataTable.NUMBER:
        var number : Float = value;
        if (ImGui.dragDouble("##deger", number, 0.1)) row.set(column.name, number);
        track(column.title);
      case DataTable.INTEGER:
        var number : Int = value;
        if (ImGui.inputInt("##deger", number, 0, 0)) row.set(column.name, number);
        track(column.title);
      case DataTable.ASSET:
        // Asset Browser'dan sürüklenen dosya bırakılır, yol elle de yazılabilir.
        var text : String = value;
        if (ImGui.inputText("##deger", text)) row.set(column.name, text);
        track(column.title);
        if (ImGui.beginDragDropTarget()) {
          if (ImGui.acceptDragDropPayload(AssetBrowser.PAYLOAD) != null && editor.assetDrag != null) {
            var dropped = editor.assetDrag, id = row.get("id");
            change(column.title, data -> data.find(id).set(column.name, dropped));
          }
          ImGui.endDragDropTarget();
        }
        if (text != "" && !hxd.Res.loader.exists(text) && ImGui.isItemHovered()) ImGui.setTooltip('Dosya yok: res/$text');
      case DataTable.COLOR:
        var color : Int = value;
        var rgb = new hl.NativeArray<Single>(3);
        rgb[0] = (color >> 16 & 255) / 255;
        rgb[1] = (color >> 8 & 255) / 255;
        rgb[2] = (color & 255) / 255;
        if (ImGui.colorEdit3("##deger", rgb, ImGuiColorEditFlags.NoInputs))
          row.set(column.name, Math.round(rgb[0] * 255) << 16 | Math.round(rgb[1] * 255) << 8 | Math.round(rgb[2] * 255));
        track(column.title);
      default:
        var text : String = value;
        if (ImGui.inputText("##deger", text)) row.set(column.name, text);
        track(column.title);
    }
  }

  function choose(row : DynamicAccess<Dynamic>, column : DataColumn, value : String, options : Array<String>, label : String->String) {
    if (!ImGui.beginCombo("##deger", label(value))) return;
    for (option in options) {
      var chosen = option == value;
      if (ImGui.selectable(label(option), chosen)) change(column.title, data -> data.find(row.get("id")).set(column.name, option));
    }
    ImGui.endCombo();
  }

  function drawColumns(table : DataTable) {
    for (column in table.columns) {
      ImGui.pushID(column.name);
      ImGui.text(column.title);
      ImGui.sameLine();
      ImGui.textDisabled(TYPE_TITLES[DataTable.TYPES.indexOf(column.type)] + (column.table == null ? "" : ': ${column.table}'));
      ImGui.sameLine();
      if (ImGui.smallButton("Sil")) {
        var name = column.name;
        change("Sütun sil", data -> {
          data.columns = data.columns.filter(item -> item.name != name);
          for (row in data.rows) row.remove(name);
        });
      }
      ImGui.popID();
    }
  }

  function drawTablePopup() {
    if (openTable) {
      ImGui.openPopup(TABLE_POPUP);
      openTable = false;
      tableName = "";
      tableTitle = "";
    }
    if (!ImGui.beginPopup(TABLE_POPUP)) return;
    var title = tableTitle;
    if (ImGui.inputText("Başlık", title)) tableTitle = title;
    var name = SceneDocument.cleanName(tableTitle);
    ImGui.textDisabled('Dosya: ${DataStore.DIRECTORY}/$name${DataTable.SUFFIX}');
    if (ImGui.button("Oluştur")) {
      if (name == "" || editor.data.tables.exists(name)) editor.show(name == "" ? "Başlık yaz" : 'Bu adda tablo var: $name', true);
      else {
        var table = new DataTable(name, tableTitle);
        table.columns.push({name: "ad", title: "Ad", type: DataTable.TEXT});
        editor.commands.execute(new SetTableCommand("Yeni tablo", editor.data, name, null, table.write()));
        current = name;
        ImGui.closeCurrentPopup();
      }
    }
    ImGui.endPopup();
  }

  function drawColumnPopup() {
    if (openColumn) {
      ImGui.openPopup(COLUMN_POPUP);
      openColumn = false;
      columnTitle = "";
      columnOptions = "";
    }
    if (!ImGui.beginPopup(COLUMN_POPUP)) return;
    var title = columnTitle;
    if (ImGui.inputText("Başlık", title)) columnTitle = title;
    if (ImGui.beginCombo("Tür", TYPE_TITLES[columnType])) {
      for (i in 0...TYPE_TITLES.length) {
        var chosen = i == columnType;
        if (ImGui.selectable(TYPE_TITLES[i], chosen)) columnType = i;
      }
      ImGui.endCombo();
    }
    var type = DataTable.TYPES[columnType];
    if (type == DataTable.CHOICE) {
      var options = columnOptions;
      if (ImGui.inputText("Seçenekler", options)) columnOptions = options;
      ImGui.textDisabled("Virgülle ayır: kolay, orta, zor");
    }
    if (type == DataTable.REFERENCE && ImGui.beginCombo("Tablo##hedef", columnTable == "" ? "(seç)" : columnTable)) {
      for (name in editor.data.names()) {
        var chosen = name == columnTable;
        if (ImGui.selectable(name, chosen)) columnTable = name;
      }
      ImGui.endCombo();
    }
    if (ImGui.button("Ekle")) {
      var name = SceneDocument.cleanName(columnTitle);
      var table = editor.data.tables.get(current);
      if (name == "" || name == "id" || table.column(name) != null) editor.show(name == "" ? "Başlık yaz" : 'Bu adda sütun var: $name', true);
      else if (type == DataTable.REFERENCE && columnTable == "") editor.show("Bağlanacak tabloyu seç", true);
      else {
        var column : DataColumn = {name: name, title: columnTitle, type: type};
        if (type == DataTable.CHOICE) column.options = [for (option in columnOptions.split(",")) if (StringTools.trim(option) != "") StringTools.trim(option)];
        if (type == DataTable.REFERENCE) column.table = columnTable;
        change("Sütun ekle", data -> data.columns.push(column));
        ImGui.closeCurrentPopup();
      }
    }
    ImGui.endPopup();
  }

  // Anında biten değişiklik: kopya üzerinde yapılır, komutla uygulanır.
  function change(label : String, mutate : DataTable->Void) {
    var before = editor.data.text(current);
    var copy = editor.data.tables.get(current).clone();
    mutate(copy);
    var after = copy.write();
    if (after != before) editor.commands.execute(new SetTableCommand(label, editor.data, current, before, after));
  }

  // Sürükleme ve yazma boyunca değer canlı değişir, bırakınca tek adım olur.
  function track(label : String) {
    if (ImGui.isItemActivated()) editStart = editor.data.text(current);
    if (ImGui.isItemDeactivatedAfterEdit()) commit(label);
  }

  function commit(label : String) {
    var after = editor.data.text(current);
    if (editStart != null && after != editStart) editor.commands.execute(new SetTableCommand(label, editor.data, current, editStart, after));
    editStart = null;
  }
}
