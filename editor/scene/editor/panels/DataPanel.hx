package scene.editor.panels;

import haxe.DynamicAccess;
import imgui.ImGui;
import scene.data.DataTable;
import scene.data.Translations;
import scene.editor.commands.SetTableCommand;

// Oyun verisi tabloları: fraksiyonlar, eşyalar. Hücreler doğrudan düzenlenir, her değişiklik
// Cmd+Z ile geri alınır ve sahneyle birlikte kaydedilir.
// Dil: oyun dillerini bildirirse (Editor.languages) üstte düzenleme dili seçilir. Kaynak dilde tablo düzenlenir; öbür
// dilde çevrilir sütunların hücreleri çeviriyi düzenler (res/ceviri/<dil>/, Editor.translations), öbür hücreler kilitlidir.
class DataPanel {
  static var STALE_COLOR : ImVec4 = {x: 0.45, y: 0.33, z: 0.05, w: 1};
  public static inline var CONFIRM_TIP = "Kaynak değişti ama çeviri hâlâ doğru (ör. yazım düzeltmesi): metin aynı kalır, eskimiş işareti kalkar. Cmd + Z ile geri alınır.";

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
  // Düzenleme dili; boş ya da kaynak dil: tablonun kendisi.
  var language = "";
  // Yazılmakta olan çeviri hücreleri (satır|sütun → metin): bırakınca tek geri alma adımı olur.
  var typing = new Map<String, String>();
  // Gösterilecek satır (Çeviriler panelinden atlama): bir kez kaydırılır, kısa süre vurgulanır.
  var focusRow : Null<String>;
  var focusScroll = false;
  var focusUntil = 0.;
  static inline var FOCUS_SECONDS = 1.5;
  static var FOCUS_COLOR = 0x5530A0E0;

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
    drawLanguage();
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

  // Tablo, satır ve dil seçilir; satır bir sonraki çizimde görünür yere kaydırılır ve vurgulanır.
  public function reveal(table : String, row : String, code : String) {
    if (!editor.data.tables.exists(table)) return;
    current = table;
    language = code;
    focusRow = row;
    focusScroll = true;
    focusUntil = haxe.Timer.stamp() + FOCUS_SECONDS;
  }

  public function shown() : {table : String, language : String, row : Null<String>} {
    return {table: current, language: language, row: focusRow};
  }

  function translating() : Bool {
    return language != "" && language != editor.sourceLanguage && editor.languages.indexOf(language) >= 0;
  }

  function drawLanguage() {
    if (editor.languages.length < 2) {
      language = "";
      return;
    }
    if (language == "" || editor.languages.indexOf(language) < 0) language = editor.sourceLanguage;
    ImGui.sameLine();
    ImGui.setNextItemWidth(130 * editor.interfaceScale);
    if (ImGui.beginCombo("Dil", language == editor.sourceLanguage ? '$language (kaynak)' : language)) {
      for (code in editor.languages)
        if (ImGui.selectable(code == editor.sourceLanguage ? '$code (kaynak)' : code, code == language)) language = code;
      ImGui.endCombo();
    }
    if (ImGui.isItemHovered()) ImGui.setTooltip("Kaynak dilde tablo düzenlenir. Öbür dilde yalnızca çevrilir sütunların çevirisi düzenlenir (res/ceviri/<dil>/); çevirisi olmayan hücrede kaynak metin soluk görünür, kaynağı değişen çeviri sarıdır.");
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
      if (focusRow != null && row.get("id") == focusRow) {
        if (focusScroll) ImGui.setScrollHereY(0.5);
        focusScroll = false;
        if (haxe.Timer.stamp() < focusUntil) ImGui.tableSetBGColor(ImGuiTableBgTarget.RowBg1, FOCUS_COLOR);
      }
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
    commit("Kimlik", old == clean ? null : [old => clean]);
  }

  function drawCell(table : DataTable, row : DynamicAccess<Dynamic>, column : DataColumn) {
    if (translating()) {
      if (column.translatable == true) drawTranslation(table, row, column);
      else {
        ImGui.beginDisabled();
        drawSourceCell(table, row, column);
        ImGui.endDisabled();
      }
      return;
    }
    drawSourceCell(table, row, column);
  }

  // Seçili dildeki çeviri: boşsa kaynak metin ipucu, kaynağı değişmişse sarı. Yazı bitince Translations.put ile tek adım.
  function drawTranslation(table : DataTable, row : DynamicAccess<Dynamic>, column : DataColumn) {
    var id : String = row.get("id");
    var key = '$language/$current', cell = '$id|${column.name}';
    var layer = editor.translations.tables.get(key);
    var stored = layer == null ? null : layer.find(id);
    var saved : String = stored == null || stored.get(column.name) == null ? "" : stored.get(column.name);
    var source : String = row.get(column.name) == null ? "" : row.get(column.name);
    var stale = saved != "" && source != "" && stored.get(column.name + Translations.SOURCE_SUFFIX) != Translations.digest(source);
    var text = typing.exists(cell) ? typing.get(cell) : saved;
    ImGui.setNextItemWidth(stale ? -ImGui.calcTextSize("Doğru").x - ImGui.getStyle().FramePadding.x * 4 : -1);
    if (stale) ImGui.pushStyleColor(ImGuiCol.FrameBg, STALE_COLOR);
    if (ImGui.inputTextWithHint("##ceviri", source, text)) typing.set(cell, text);
    if (stale) ImGui.popStyleColor();
    var hovered = ImGui.isItemHovered(), finished = ImGui.isItemDeactivatedAfterEdit();
    if (stale) {
      ImGui.sameLine();
      if (ImGui.smallButton("Doğru")) confirm(id, column.name);
      if (ImGui.isItemHovered()) ImGui.setTooltip(CONFIRM_TIP);
    }
    if (hovered)
      ImGui.setTooltip('Kaynak (${editor.sourceLanguage}): $source' + (stale ? "\nKaynak değişti: çeviri eskimiş. Gözden geçir; hâlâ doğruysa Doğru." : saved == "" ? "\nÇeviri yok: oyunda kaynak metin görünür." : ""));
    if (finished && typing.exists(cell)) {
      translate(id, column.name, typing.get(cell));
      typing.remove(cell);
    }
  }

  // Bir çeviri hücresini yazar (ajanın set_translation aracıyla aynı yol): komutla, geri alınabilir.
  function translate(id : String, column : String, text : String) {
    var key = '$language/$current';
    var before = editor.translations.text(key);
    var layer = editor.translations.tables.get(key);
    var result = Translations.put(layer == null ? null : layer.clone(), editor.data.tables.get(current), id, column, text);
    var after = result.table.write();
    if (result.ok && after != before) editor.commands.execute(new SetTableCommand('Çeviri ($language)', editor.translations, key, before, after));
  }

  // Çeviri hâlâ doğru: metin aynı, kaynak özeti bugünkü metinden (ajanın set_translation confirm'üyle aynı yol).
  function confirm(id : String, column : String) {
    var key = '$language/$current';
    var before = editor.translations.text(key), layer = editor.translations.tables.get(key);
    var result = Translations.confirm(layer == null ? null : layer.clone(), editor.data.tables.get(current), id, column);
    if (!result.ok) return;
    var after = result.table.write();
    if (after != before) editor.commands.execute(new SetTableCommand('Çeviri doğru ($language)', editor.translations, key, before, after));
  }

  function drawSourceCell(table : DataTable, row : DynamicAccess<Dynamic>, column : DataColumn) {
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
      if (column.type == DataTable.TEXT) {
        var on = column.translatable == true;
        var name = column.name;
        if (ImGui.checkbox("Çevrilir", on)) change("Çevrilir", data -> data.column(name).translatable = on);
        if (ImGui.isItemHovered()) ImGui.setTooltip("Oyuncuya görünen metin: dil başına çevrilir (res/ceviri/<dil>/).");
        ImGui.sameLine();
      }
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
    if (after != before) execute(label, before, after, copy);
  }

  // Tablo komutu ve çevirilerin uyumu tek adım (TranslationSync).
  function execute(label : String, before : Null<String>, after : String, table : DataTable, ?renamed : Map<String, String>) {
    var command = new SetTableCommand(label, editor.data, current, before, after);
    var follow = TranslationSync.commands(editor, current, table, renamed);
    editor.commands.execute(follow.length == 0 ? command : new scene.editor.commands.GroupCommand(label, [(command : scene.editor.Command)].concat(follow)));
  }

  // Sürükleme ve yazma boyunca değer canlı değişir, bırakınca tek adım olur.
  function track(label : String) {
    if (ImGui.isItemActivated()) editStart = editor.data.text(current);
    if (ImGui.isItemDeactivatedAfterEdit()) commit(label);
  }

  function commit(label : String, ?renamed : Map<String, String>) {
    var after = editor.data.text(current);
    if (editStart != null && after != editStart) execute(label, editStart, after, editor.data.tables.get(current), renamed);
    editStart = null;
  }
}
