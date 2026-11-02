package scene.editor.panels;

import imgui.ImGui;
import imgui.NodeEditor;
import scene.editor.commands.SetDialogCommand;
import scene.story.Dialog;

// Diyalog ağacı. Boş yere sağ tıklayınca düğüm eklenir, çıkıştan girişe sürükleyince bağlanır,
// seçili düğüm veya bağlantı Delete ile silinir. Her değişiklik Cmd+Z ile geri alınır.
class DialogPanel {
  static inline var NEW_POPUP = "Yeni diyalog";
  static inline var NODE_POPUP = "Düğüm ekle";
  static inline var FIELD_WIDTH = 200.;
  static inline var TEXT_WIDTH = 320.;
  static inline var PIN_STRIDE = 100;
  static inline var INPUT = 1;
  static inline var NEXT = 2;
  static inline var YES = 3;
  static inline var NO = 4;
  static inline var CHOICE = 10;
  static inline var LINK_OFFSET = 10000000;
  static inline var MOVE_THRESHOLD = 0.5;

  static var TITLES = [
    Dialog.START => "Başlangıç", Dialog.LINE => "Satır", Dialog.CHOICES => "Seçenekler",
    Dialog.CONDITION => "Koşul", Dialog.EVENT => "Olay", Dialog.END => "Bitiş",
  ];
  static var ADDABLE = [Dialog.LINE, Dialog.CHOICES, Dialog.CONDITION, Dialog.EVENT, Dialog.END];

  var editor : Editor;
  var context : Null<EditorContext>;
  var current = "";
  var shown = "";
  var editStart : Null<String>;
  var newTitle = "";
  var openNew = false;
  var menuX = 0.;
  var menuY = 0.;

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function draw() {
    editor.claimKeyboard();
    var store = editor.dialogs;
    var ids = store.ids();
    if (!store.exists(current)) current = ids.length > 0 ? ids[0] : "";
    if (ImGui.beginCombo("Diyalog", current == "" ? "(yok)" : store.dialogs.get(current).title)) {
      for (id in ids) {
        var chosen = id == current;
        if (ImGui.selectable(store.dialogs.get(id).title + "##" + id, chosen)) current = id;
      }
      ImGui.endCombo();
    }
    ImGui.sameLine();
    if (ImGui.smallButton("Yeni diyalog")) openNew = true;
    drawNewPopup();
    if (current == "") {
      ImGui.textDisabled("Henüz diyalog yok");
      return;
    }
    ImGui.sameLine();
    ImGui.textDisabled('Kimlik: $current. Boş yere sağ tıkla: düğüm ekle');
    drawCanvas(store.dialogs.get(current));
  }

  // Koşul ve olay düğümleri oyuncuya görünmez: koşul dalı seçer, olay tetikleyicileri çalıştırır.
  function drawCanvas(dialog : Dialog) {
    if (context == null) context = NodeEditor.createEditor();
    NodeEditor.setCurrentEditor(context);
    NodeEditor.begin("##agac");
    for (node in dialog.nodes) drawNode(node);
    for (node in dialog.nodes) drawLinks(node);
    handleCreate(dialog);
    handleDelete(dialog);
    NodeEditor.suspend();
    if (NodeEditor.showBackgroundContextMenu()) {
      var at = NodeEditor.screenToCanvas(ImGui.getMousePos());
      menuX = at.x;
      menuY = at.y;
      ImGui.openPopup(NODE_POPUP);
    }
    drawNodeMenu();
    NodeEditor.resume();
    if (shown != current) {
      shown = current;
      for (node in dialog.nodes) NodeEditor.setNodePosition(node.id, {x: node.x, y: node.y});
      NodeEditor.navigateToContent(0);
    }
    NodeEditor.end();
    syncPositions(dialog);
    NodeEditor.setCurrentEditor(null);
  }

  function drawNode(node : scene.story.Dialog.DialogNode) {
    NodeEditor.beginNode(node.id);
    ImGui.pushID('${node.id}');
    if (node.type != Dialog.START) {
      NodeEditor.beginPin(pin(node.id, INPUT), PinKind.Input);
      ImGui.text(">");
      NodeEditor.endPin();
      ImGui.sameLine();
    }
    ImGui.text(TITLES.get(node.type));
    ImGui.pushItemWidth(FIELD_WIDTH);
    switch (node.type) {
      case Dialog.LINE:
        var speaker = node.speaker == null ? "" : node.speaker;
        if (ImGui.inputText("Konuşan", speaker)) node.speaker = speaker;
        track("Konuşan");
        // Düğüm editörü düğüm içinde alt pencereyi desteklemez, çok satırlı kutu yanlış yere çizilir.
        var text = node.text == null ? "" : node.text;
        ImGui.setNextItemWidth(TEXT_WIDTH);
        if (ImGui.inputText("##metin", text)) node.text = text;
        if (ImGui.isItemHovered() && text != "") ImGui.setTooltip(text);
        track("Satır");
        output(node.id, NEXT, "Sonra");
      case Dialog.CHOICES:
        var choices = node.choices == null ? [] : node.choices;
        for (k in 0...choices.length) {
          ImGui.pushID('secenek$k');
          var text = choices[k].text;
          if (ImGui.inputText("##secenek", text)) choices[k].text = text;
          track("Seçenek");
          ImGui.sameLine();
          output(node.id, CHOICE + k, '${k + 1}');
          ImGui.popID();
        }
        if (ImGui.smallButton("+ Seçenek")) change("Seçenek ekle", d -> {
          var target = d.node(node.id);
          if (target.choices == null) target.choices = [];
          target.choices.push({text: "", next: 0});
        });
        if (choices.length > 0) {
          ImGui.sameLine();
          if (ImGui.smallButton("- Seçenek")) change("Seçenek sil", d -> d.node(node.id).choices.pop());
        }
      case Dialog.CONDITION:
        var isItem = node.kind == Dialog.ITEM;
        if (ImGui.radioButton("Değişken", !isItem)) change("Koşul türü", d -> d.node(node.id).kind = Dialog.FLAG);
        ImGui.sameLine();
        if (ImGui.radioButton("Eşya", isItem)) change("Koşul türü", d -> d.node(node.id).kind = Dialog.ITEM);
        var name = node.name == null ? "" : node.name;
        if (ImGui.inputText(isItem ? "Eşya kimliği" : "Değişken", name)) node.name = name;
        track("Koşul");
        var value : Int = node.value == null ? 1 : node.value;
        if (ImGui.inputInt("En az", value)) node.value = value;
        track("Koşul");
        output(node.id, YES, "Evet");
        output(node.id, NO, "Hayır");
      case Dialog.EVENT:
        var event = node.event == null ? "" : node.event;
        if (ImGui.inputText("Olay adı", event)) node.event = event;
        track("Olay");
        output(node.id, NEXT, "Sonra");
      case Dialog.START:
        output(node.id, NEXT, "Başla");
      default:
    }
    ImGui.popItemWidth();
    ImGui.popID();
    NodeEditor.endNode();
  }

  function output(node : Int, slot : Int, label : String) {
    NodeEditor.beginPin(pin(node, slot), PinKind.Output);
    ImGui.text('$label >');
    NodeEditor.endPin();
  }

  function drawLinks(node : scene.story.Dialog.DialogNode) {
    function link(slot : Int, target : Null<Int>) {
      if (target == null || target <= 0) return;
      var from = pin(node.id, slot);
      NodeEditor.link(from + LINK_OFFSET, from, pin(target, INPUT));
    }
    link(NEXT, node.next);
    link(YES, node.yes);
    link(NO, node.no);
    if (node.choices != null) for (k in 0...node.choices.length) link(CHOICE + k, node.choices[k].next);
  }

  // Çıkış yalnızca girişe bağlanır, düğüm kendine bağlanmaz.
  function handleCreate(dialog : Dialog) {
    if (NodeEditor.beginCreate()) {
      var a : PinId = 0, b : PinId = 0;
      if (NodeEditor.queryNewLink(a, b)) {
        var start = a.toInt(), end = b.toInt();
        if (start % PIN_STRIDE == INPUT) {
          var swap = start;
          start = end;
          end = swap;
        }
        var valid = end % PIN_STRIDE == INPUT && start % PIN_STRIDE != INPUT && Std.int(start / PIN_STRIDE) != Std.int(end / PIN_STRIDE);
        if (!valid) NodeEditor.rejectNewItem();
        else if (NodeEditor.acceptNewItem()) change("Bağla", d -> connect(d, start, Std.int(end / PIN_STRIDE)));
      }
    }
    NodeEditor.endCreate();
  }

  function handleDelete(dialog : Dialog) {
    var copy = dialog.clone();
    var changed = false;
    if (NodeEditor.beginDelete()) {
      var link : LinkId = 0, from : PinId = 0, to : PinId = 0;
      while (NodeEditor.queryDeletedLink(link, from, to)) {
        if (!NodeEditor.acceptDeletedItem()) continue;
        connect(copy, link.toInt() - LINK_OFFSET, 0);
        changed = true;
      }
      var node : NodeId = 0;
      while (NodeEditor.queryDeletedNode(node)) {
        var target = copy.node(node.toInt());
        if (target == null || target.type == Dialog.START) {
          NodeEditor.rejectDeletedItem();
          continue;
        }
        if (!NodeEditor.acceptDeletedItem()) continue;
        copy.remove(target.id);
        changed = true;
      }
    }
    NodeEditor.endDelete();
    if (changed) commitCopy("Sil", copy);
  }

  function connect(dialog : Dialog, from : Int, target : Int) {
    var node = dialog.node(Std.int(from / PIN_STRIDE));
    if (node == null) return;
    var slot = from % PIN_STRIDE;
    if (slot == NEXT) node.next = target;
    else if (slot == YES) node.yes = target;
    else if (slot == NO) node.no = target;
    else if (slot >= CHOICE && node.choices != null && slot - CHOICE < node.choices.length) node.choices[slot - CHOICE].next = target;
  }

  function drawNodeMenu() {
    if (!ImGui.beginPopup(NODE_POPUP)) return;
    for (type in ADDABLE) {
      if (!ImGui.menuItem(TITLES.get(type))) continue;
      var x = menuX, y = menuY;
      change(TITLES.get(type) + " ekle", d -> d.nodes.push(newNode(d.freeId(), type, x, y)));
    }
    ImGui.endPopup();
  }

  function newNode(id : Int, type : String, x : Float, y : Float) : scene.story.Dialog.DialogNode {
    var node : scene.story.Dialog.DialogNode = {id: id, type: type, x: x, y: y};
    switch (type) {
      case Dialog.LINE:
        node.speaker = "";
        node.text = "";
        node.next = 0;
      case Dialog.CHOICES:
        node.choices = [{text: "", next: 0}, {text: "", next: 0}];
      case Dialog.CONDITION:
        node.kind = Dialog.FLAG;
        node.name = "";
        node.value = 1;
        node.yes = 0;
        node.no = 0;
      case Dialog.EVENT:
        node.event = "";
        node.next = 0;
      default:
    }
    return node;
  }

  function drawNewPopup() {
    if (openNew) {
      ImGui.openPopup(NEW_POPUP);
      openNew = false;
      newTitle = "";
    }
    if (!ImGui.beginPopup(NEW_POPUP)) return;
    var title = newTitle;
    if (ImGui.inputText("Başlık", title)) newTitle = title;
    var id = SceneDocument.cleanName(newTitle);
    ImGui.textDisabled('Kimlik: $id');
    if (ImGui.button("Oluştur")) {
      if (id == "" || editor.dialogs.exists(id)) editor.show(id == "" ? "Başlık yaz" : 'Bu adda diyalog var: $id', true);
      else {
        editor.commands.execute(new SetDialogCommand("Yeni diyalog", editor.dialogs, id, null, Dialog.create(id, newTitle).write()));
        current = id;
        ImGui.closeCurrentPopup();
      }
    }
    ImGui.endPopup();
  }

  // Sürükleme bitince yer değişikliği tek adım olur; geri alınınca düğüm eski yerine döner.
  function syncPositions(dialog : Dialog) {
    if (ImGui.isMouseDown(0)) return;
    var moved = dialog.clone();
    var hasMoved = false;
    for (node in dialog.nodes) {
      var at = NodeEditor.getNodePosition(node.id);
      if (at == null) continue;
      if (Math.abs(at.x - node.x) < MOVE_THRESHOLD && Math.abs(at.y - node.y) < MOVE_THRESHOLD) continue;
      if (ImGui.isMouseReleased(0)) {
        moved.node(node.id).x = at.x;
        moved.node(node.id).y = at.y;
        hasMoved = true;
      } else {
        NodeEditor.setNodePosition(node.id, {x: node.x, y: node.y});
      }
    }
    if (hasMoved) commitCopy("Düğüm taşı", moved);
  }

  function change(label : String, mutate : Dialog->Void) {
    var copy = editor.dialogs.dialogs.get(current).clone();
    mutate(copy);
    commitCopy(label, copy);
  }

  function commitCopy(label : String, copy : Dialog) {
    var before = editor.dialogs.text(current), after = copy.write();
    if (before != after) editor.commands.execute(new SetDialogCommand(label, editor.dialogs, current, before, after));
  }

  function track(label : String) {
    if (ImGui.isItemActivated()) editStart = editor.dialogs.text(current);
    if (!ImGui.isItemDeactivatedAfterEdit()) return;
    var after = editor.dialogs.text(current);
    if (editStart != null && after != editStart) editor.commands.execute(new SetDialogCommand(label, editor.dialogs, current, editStart, after));
    editStart = null;
  }

  static inline function pin(node : Int, slot : Int) {
    return node * PIN_STRIDE + slot;
  }
}
