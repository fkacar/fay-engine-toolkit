package scene.editor;

import imgui.ImGui;
import imgui.NodeEditor;
import scene.Marker;
import scene.data.SceneData.ComponentData;
import scene.editor.commands.SetDialogCommand;
import scene.story.Dialog;
import scene.story.Dialog.DialogNode;
import scene.story.DialogLayout;
import scene.story.DialogLayout.*;
import scene.story.TriggerAction;

// Konumlar dosyada ekran netliğinden bağımsız birimdedir (DialogLayout); tuvale netlikle çarpılarak
// verilir. Böylece Retina Mac ile Windows'ta aynı diyalog aynı dizilir, git farkı doğmaz.
//
// Diyalog düzenleyici. Açılınca sahne görünümünün yerini alır: alt paneldeki dar tuvalde düğümler
// üst üste biniyor, metin kesiliyordu. Düğüm yalnızca özet gösterir; seçilen düğümün ayrıntısı
// Inspector'da, çok satırlı kutuyla düzenlenir. Her değişiklik Cmd+Z ile geri alınır.
class DialogWorkspace {
  public static inline var NEW_POPUP = "Yeni diyalog";
  static inline var OVERLAP = "Üst üste binen düğümler var";
  static inline var NODE_POPUP = "dugum-ekle";
  static inline var PREVIEW_HEIGHT = 130.;
  static inline var TEXT_LINES = 6;
  static inline var PIN_STRIDE = 100;
  static inline var INPUT = 1;
  static inline var NEXT = 2;
  static inline var YES = 3;
  static inline var NO = 4;
  static inline var CHOICE = 10;
  static inline var LINK_OFFSET = 10000000;
  static inline var STYLE_COUNT = 6;
  static inline var HINT = "Sağ tık: düğüm ekle  ·  Çıkışı (>) boşluğa sürükle veya + bas: bağlı düğüm  ·  Düğüme tıkla: Inspector'da düzenle  ·  Delete: sil  ·  F: tümünü göster  ·  Esc: sahneye dön";

  public static var TITLES = [
    Dialog.START => "Başlangıç", Dialog.LINE => "Satır", Dialog.CHOICES => "Seçenekler",
    Dialog.CONDITION => "Koşul", Dialog.EVENT => "Olay", Dialog.END => "Bitiş",
  ];
  static var HELP = [
    Dialog.START => "Konuşma buradan başlar. Silinemez.",
    Dialog.LINE => "Bir kişinin söylediği. Oyuncu boşluk veya tıkla geçer.",
    Dialog.CHOICES => "Oyuncunun cevapları. Her seçeneğin düğümde kendi çıkışı vardır.",
    Dialog.CONDITION => "Oyuncu görmez. Değer en az yazılan kadarsa Evet, değilse Hayır yolundan gider. Hiç ayarlanmamış değişken 0'dır.",
    Dialog.EVENT => "Oyuncu görmez. Adlı olay yayar: Ne zaman'ı \"olayda\" olan ve aynı olay adını bekleyen tetikleyicinin eylemleri çalışır.",
    Dialog.END => "Konuşmayı kapatır.",
  ];
  static var ADDABLE = [Dialog.LINE, Dialog.CHOICES, Dialog.CONDITION, Dialog.EVENT, Dialog.END];
  static var COLORS : Map<String, ImVec4> = [
    Dialog.START => {x: 0.55, y: 0.85, z: 0.55, w: 1}, Dialog.LINE => {x: 0.55, y: 0.75, z: 1, w: 1},
    Dialog.CHOICES => {x: 1, y: 0.75, z: 0.35, w: 1}, Dialog.CONDITION => {x: 0.8, y: 0.6, z: 1, w: 1},
    Dialog.EVENT => {x: 1, y: 0.5, z: 0.5, w: 1}, Dialog.END => {x: 0.65, y: 0.65, z: 0.65, w: 1},
  ];

  static var WARNING_COLOR : ImVec4 = {x: 1, y: 0.8, z: 0.35, w: 1};

  public var isOpen(default, null) = false;
  public var current(default, null) = "";
  public var selected(default, null) : Array<Int> = [];

  var editor : Editor;
  var context : Null<EditorContext>;
  var shown = "";
  var editStart : Null<String>;
  var newTitle = "";
  var openNew = false;
  var openMenu = false;
  var menuAtMouse = false;
  var menuX = 0.;
  var menuY = 0.;
  var pendingFrom = 0;    // yeni düğüm bu çıkışa bağlanır, 0 ise bağlanmaz
  var selectAfter = 0;
  var navigateFrames = 0;
  var focusText = false;
  var previewNode = 0;    // 0 oynatılmıyor, -1 konuşma bitti
  var arrangeNext = false;
  var hasOverlap = false;
  var sceneSelection : Array<Entity> = [];

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function open(id : String, node = 0) {
    if (!editor.dialogs.exists(id)) return;
    if (current != id) previewNode = 0;
    isOpen = true;
    current = id;
    shown = "";
    selected = [];
    selectAfter = node;
    sceneSelection = editor.selection.items.copy();
  }

  public function close() {
    isOpen = false;
    previewNode = 0;
    editStart = null;
  }

  // Sahne kısayolları açıkken çalışmaz: Delete sahnede seçili nesneyi değil düğümü siler.
  public function readKeys() {
    if (ImGui.getIO().WantTextInput || ImGui.isPopupOpen("", ImGuiPopupFlags.AnyPopupId)) return;
    if (hxd.Key.isPressed(hxd.Key.ESCAPE)) close();
    else if (hxd.Key.isPressed(hxd.Key.F)) navigateFrames = 1;
  }

  public function draw() {
    if (!isOpen) return;
    var dialog = editor.dialogs.dialogs.get(current);
    // Sahnede başka nesne seçmek sahneye dönmek demektir.
    if (dialog == null || !sameSelection()) {
      close();
      return;
    }
    var area = editor.centerArea();
    ImGui.setNextWindowPos({x: area.x, y: area.y});
    ImGui.setNextWindowSize({x: area.width, y: area.height});
    var flags = ImGuiWindowFlags.NoDecoration | ImGuiWindowFlags.NoMove | ImGuiWindowFlags.NoResize | ImGuiWindowFlags.NoDocking
      | ImGuiWindowFlags.NoSavedSettings | ImGuiWindowFlags.NoScrollbar | ImGuiWindowFlags.NoScrollWithMouse
      | ImGuiWindowFlags.NoBringToFrontOnFocus;
    if (ImGui.begin("##diyalog-alani", null, flags)) {
      editor.claimKeyboard();
      drawToolbar(dialog);
      var space = ImGui.getContentRegionAvail();
      var height = previewNode != 0 ? space.y - PREVIEW_HEIGHT * editor.interfaceScale : space.y;
      drawCanvas(dialog, {x: space.x, y: height});
      if (previewNode != 0) drawPreview(dialog);
    }
    ImGui.end();
  }

  function sameSelection() {
    var items = editor.selection.items;
    if (items.length != sceneSelection.length) return false;
    for (i in 0...items.length) if (items[i] != sceneSelection[i]) return false;
    return true;
  }

  function drawToolbar(dialog : Dialog) {
    if (ImGui.button("< Sahneye dön")) close();
    if (ImGui.isItemHovered()) ImGui.setTooltip("Esc");
    ImGui.sameLine();
    ImGui.setNextItemWidth(180 * editor.interfaceScale);
    if (ImGui.beginCombo("##diyalog", dialog.title)) {
      for (id in editor.dialogs.ids()) {
        var chosen = id == current;
        if (ImGui.selectable(editor.dialogs.dialogs.get(id).title + "##" + id, chosen)) open(id);
      }
      ImGui.endCombo();
    }
    nextInRow("Yeni diyalog");
    newDialogButton();
    nextInRow("Tümünü göster");
    if (ImGui.button("Tümünü göster")) navigateFrames = 1;
    if (ImGui.isItemHovered()) ImGui.setTooltip("F");
    nextInRow("Yerleştir");
    if (ImGui.button("Yerleştir")) arrangeNext = true;
    if (ImGui.isItemHovered()) ImGui.setTooltip("Düğümleri konuşmanın akışına göre soldan sağa dizer");
    // Kendiliğinden dizilmez: yalnızca bakmak dosyayı değiştirmesin.
    if (hasOverlap) {
      nextInRow(OVERLAP, false);
      ImGui.textColored(WARNING_COLOR, OVERLAP);
    }
    var play = previewNode == 0 ? "Oynat" : "Oynatmayı bitir";
    nextInRow(play);
    if (ImGui.button(play)) previewNode == 0 ? restartPreview(dialog) : previewNode = 0;
    if (ImGui.isItemHovered()) ImGui.setTooltip("Konuşmayı burada adım adım dene");
    var starter = starterTypes();
    if (starter != null) {
      nextInRow("Tetikleyici ekle");
      if (ImGui.button("Tetikleyici ekle")) addStarter(starter);
      if (ImGui.isItemHovered()) ImGui.setTooltip("Bu diyaloğu başlatan tetikleyiciyi sahneye koyar: ekip içine girince açılır");
    }
    ImGui.pushTextWrapPos(0);
    ImGui.textDisabled(HINT);
    ImGui.popTextWrapPos();
  }

  // Dar ekranda sığmayan düğme alt satıra geçer.
  function nextInRow(label : String, isButton = true) {
    var style = ImGui.getStyle();
    var width = ImGui.calcTextSize(label).x + (isButton ? style.FramePadding.x * 2 : 0);
    var right = ImGui.getWindowPos().x + ImGui.getWindowContentRegionMax().x;
    if (ImGui.getItemRectMax().x + style.ItemSpacing.x + width <= right) ImGui.sameLine();
  }

  // Alt paneldeki listede ve araç çubuğunda aynı düğme: oluşturulan diyalog hemen açılır.
  public function newDialogButton() {
    if (ImGui.button("Yeni diyalog")) {
      openNew = true;
      newTitle = "";
    }
    if (openNew) {
      ImGui.openPopup(NEW_POPUP);
      openNew = false;
    }
    if (!ImGui.beginPopup(NEW_POPUP)) return;
    var title = newTitle;
    if (ImGui.isWindowAppearing()) ImGui.setKeyboardFocusHere();
    if (ImGui.inputText("Başlık", title)) newTitle = title;
    var id = SceneDocument.cleanName(newTitle);
    ImGui.textDisabled('Kimlik: $id');
    if (ImGui.button("Oluştur") || ImGui.isKeyPressed(ImGuiKey.Enter)) {
      if (id == "" || editor.dialogs.exists(id)) editor.show(id == "" ? "Başlık yaz" : 'Bu adda diyalog var: $id', true);
      else {
        createDialog(id, newTitle);
        ImGui.closeCurrentPopup();
      }
    }
    ImGui.endPopup();
  }

  // Başlangıç, bir satır ve bitiş hazır gelir; satır seçili, metni yazılmaya hazır.
  function createDialog(id : String, title : String) {
    var created = Dialog.create(id, title);
    // Düğümler eşit genişlikte: yan yana, aralarında boşlukla.
    for (k in 0...created.nodes.length) created.nodes[k].x = k * COLUMN_STEP;
    editor.commands.execute(new SetDialogCommand("Yeni diyalog", editor.dialogs, id, null, created.write()));
    open(id, 2);
    focusText = true;
  }

  function drawCanvas(dialog : Dialog, size : ImVec2) {
    if (context == null) context = NodeEditor.createEditor();
    NodeEditor.setCurrentEditor(context);
    if (arrangeNext) {
      arrangeNext = false;
      arrange(dialog);
    }
    var origin = ImGui.getCursorScreenPos();
    pushScaledStyle();
    NodeEditor.begin("##agac", size);
    for (node in dialog.nodes) drawNode(node);
    for (node in dialog.nodes) drawLinks(node);
    handleCreate();
    handleDelete(dialog);
    readSelection(dialog);
    NodeEditor.suspend();
    if (NodeEditor.showBackgroundContextMenu()) {
      openMenu = true;
      menuAtMouse = true;
      pendingFrom = 0;
    }
    if (openMenu) {
      openMenu = false;
      if (menuAtMouse) {
        var at = NodeEditor.screenToCanvas(ImGui.getMousePos());
        menuX = at.x / unit();
        menuY = at.y / unit();
      }
      ImGui.openPopup(NODE_POPUP);
    }
    drawNodeMenu(dialog);
    NodeEditor.resume();
    if (shown != current) {
      shown = current;
      for (node in dialog.nodes) NodeEditor.setNodePosition(node.id, toCanvas(node.x, node.y));
      // Düğüm boyları ilk karede bilinmez, ikinci karede de sığdırılır.
      navigateFrames = 2;
    }
    if (selectAfter != 0 && dialog.node(selectAfter) != null) {
      NodeEditor.clearSelection();
      NodeEditor.selectNode(selectAfter);
      selected = [selectAfter];
      if (!isVisible(selectAfter, origin, size)) NodeEditor.navigateToSelection(false, 0.25);
      selectAfter = 0;
      if (focusText) editor.showInspector();
    }
    if (navigateFrames > 0) {
      navigateFrames--;
      NodeEditor.navigateToContent(0);
    }
    NodeEditor.end();
    NodeEditor.popStyleVar(STYLE_COUNT);
    hasOverlap = overlaps(dialog);
    syncPositions(dialog);
    NodeEditor.setCurrentEditor(null);
  }

  function overlaps(dialog : Dialog) {
    var boxes = [for (node in dialog.nodes) {node: node, size: NodeEditor.getNodeSize(node.id)}];
    var u = unit();
    for (a in boxes) for (b in boxes) {
      if (a.node.id >= b.node.id || a.size == null || b.size == null) continue;
      var aw = a.size.x / u, ah = a.size.y / u, bw = b.size.x / u, bh = b.size.y / u;
      if (a.node.x < b.node.x + bw && b.node.x < a.node.x + aw && a.node.y < b.node.y + bh && b.node.y < a.node.y + ah) return true;
    }
    return false;
  }

  function isVisible(node : Int, origin : ImVec2, size : ImVec2) {
    var at = NodeEditor.getNodePosition(node), extent = NodeEditor.getNodeSize(node);
    if (at == null || extent == null) return true;
    var low = NodeEditor.canvasToScreen(at), high = NodeEditor.canvasToScreen({x: at.x + extent.x, y: at.y + extent.y});
    return low.x >= origin.x && low.y >= origin.y && high.x <= origin.x + size.x && high.y <= origin.y + size.y;
  }

  function readSelection(dialog : Dialog) {
    var nodes = NodeEditor.getSelectedNodes();
    selected = nodes == null ? [] : [for (i in 0...nodes.length) nodes[i].toInt()];
    selected = selected.filter(id -> dialog.node(id) != null);
    if (NodeEditor.getDoubleClickedNode().toInt() > 0) {
      focusText = true;
      editor.showInspector();
    }
  }

  function drawNode(node : DialogNode) {
    var color = COLORS.get(node.type);
    NodeEditor.pushStyleColor(StyleColor.NodeBorder, color);
    NodeEditor.beginNode(node.id);
    ImGui.pushID('${node.id}');
    var left = ImGui.getCursorPosX();
    if (node.type != Dialog.START) {
      NodeEditor.beginPin(pin(node.id, INPUT), PinKind.Input);
      ImGui.textColored(color, ">");
      NodeEditor.endPin();
      ImGui.sameLine();
    }
    ImGui.textColored(color, TITLES.get(node.type));
    var width = nodeWidth();
    switch (node.type) {
      case Dialog.LINE:
        if (!blank(node.speaker)) ImGui.text(node.speaker + ":");
        ImGui.pushTextWrapPos(left + width);
        if (blank(node.text)) ImGui.textDisabled(EMPTY_LINE);
        else ImGui.textWrapped(shorten(node.text, SHORT_TEXT));
        ImGui.popTextWrapPos();
        output(node, NEXT, "Sonra", left);
      case Dialog.CHOICES:
        var choices = node.choices == null ? [] : node.choices;
        if (choices.length == 0) ImGui.textDisabled("Seçenek yok");
        for (k in 0...choices.length) {
          var text = blank(choices[k].text) ? "(boş)" : shorten(choices[k].text, SHORT_CHOICE);
          output(node, CHOICE + k, '${k + 1}. $text', left);
        }
      case Dialog.CONDITION:
        ImGui.text(conditionText(node));
        output(node, YES, "Evet", left);
        output(node, NO, "Hayır", left);
      case Dialog.EVENT:
        if (blank(node.event)) ImGui.textDisabled("Olay adı yok");
        else ImGui.text('Olay: ${node.event}');
        output(node, NEXT, "Sonra", left);
      case Dialog.START:
        output(node, NEXT, "Başla", left);
      default:
        ImGui.textDisabled("Konuşma biter");
    }
    // Düğümler aynı genişlikte durur, kısa metinli düğüm de çıkışlarını aynı hizada gösterir.
    ImGui.setCursorPosX(left);
    ImGui.dummy({x: width, y: 1});
    ImGui.popID();
    NodeEditor.endNode();
    NodeEditor.popStyleColor(1);
  }

  // Bağlı olmayan çıkışın yanında + düğmesi: tıklayınca bağlı yeni düğüm eklenir.
  function output(node : DialogNode, slot : Int, label : String, left : Float) {
    var target = targetOf(node, slot);
    if (target == 0) {
      if (ImGui.smallButton('+##$slot')) {
        var branch = slot == NO ? 1 : slot >= CHOICE ? slot - CHOICE : 0;
        menuX = node.x + COLUMN_STEP;
        menuY = node.y + branch * BRANCH_GAP;
        menuAtMouse = false;
        pendingFrom = pin(node.id, slot);
        openMenu = true;
      }
      if (ImGui.isItemHovered()) ImGui.setTooltip("Buraya bağlı yeni düğüm ekle");
      ImGui.sameLine();
    }
    ImGui.text(label);
    ImGui.sameLine();
    var arrow = ImGui.calcTextSize(">").x;
    ImGui.setCursorPosX(Math.max(ImGui.getCursorPosX(), left + nodeWidth() - arrow));
    NodeEditor.beginPin(pin(node.id, slot), PinKind.Output);
    ImGui.text(">");
    NodeEditor.endPin();
  }

  function drawLinks(node : DialogNode) {
    for (slot in slots(node)) {
      var target = targetOf(node, slot);
      if (target <= 0) continue;
      var from = pin(node.id, slot);
      NodeEditor.link(from + LINK_OFFSET, from, pin(target, INPUT));
    }
  }

  // Çıkış yalnızca girişe bağlanır, düğüm kendine bağlanmaz. Çıkışı boşluğa bırakmak bağlı düğüm ekler.
  function handleCreate() {
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
      var from : NodeId = 0;
      if (NodeEditor.queryNewNode(from)) {
        if (from.toInt() % PIN_STRIDE == INPUT) NodeEditor.rejectNewItem();
        else if (NodeEditor.acceptNewItem()) {
          pendingFrom = from.toInt();
          menuAtMouse = true;
          openMenu = true;
        }
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

  function drawNodeMenu(dialog : Dialog) {
    if (!ImGui.beginPopup(NODE_POPUP)) return;
    ImGui.textDisabled(pendingFrom == 0 ? "Düğüm ekle" : "Bağlı düğüm ekle");
    for (type in ADDABLE) {
      if (!ImGui.menuItem(TITLES.get(type))) continue;
      var id = dialog.freeId(), from = pendingFrom, x = menuX, y = menuY;
      change(TITLES.get(type) + " ekle", d -> {
        d.nodes.push(newNode(id, type, x, y));
        if (from != 0) connect(d, from, id);
      });
      selectAfter = id;
      focusText = type != Dialog.END;
      pendingFrom = 0;
    }
    ImGui.endPopup();
  }

  // İçerikten hesaplanır, ekranda ölçülen boydan değil: her makinede aynı sonuç.
  function arrange(dialog : Dialog) {
    var copy = dialog.clone();
    for (id => at in DialogLayout.arrange(dialog)) {
      copy.node(id).x = at.x;
      copy.node(id).y = at.y;
    }
    commitCopy("Yerleştir", copy);
    // Yeni konumlar düğüm editörüne bir sonraki karede geçer, sığdırma ondan sonra.
    navigateFrames = 3;
  }

  // Oynatma oyun durumunu bilmez: koşulda hangi yoldan gidileceğini tasarımcı seçer.
  function drawPreview(dialog : Dialog) {
    ImGui.separator();
    var node = previewNode > 0 ? dialog.node(previewNode) : null;
    if (node == null || node.type == Dialog.END) {
      ImGui.text("Konuşma bitti.");
      if (ImGui.button("Baştan")) restartPreview(dialog);
    } else switch (node.type) {
      case Dialog.LINE:
        ImGui.textColored(COLORS.get(Dialog.LINE), blank(node.speaker) ? "(konuşan yok)" : node.speaker);
        ImGui.textWrapped(blank(node.text) ? "(boş satır)" : node.text);
        if (ImGui.button("Devam")) step(node.next);
      case Dialog.CHOICES:
        var choices = node.choices == null ? [] : node.choices;
        for (k in 0...choices.length) if (ImGui.button('${k + 1}. ${blank(choices[k].text) ? "(boş)" : choices[k].text}##$k')) step(choices[k].next);
      case Dialog.CONDITION:
        ImGui.text('Koşul: ${conditionText(node)}. Oyunda duruma göre seçilir, burada sen seç:');
        if (ImGui.button("Evet")) step(node.yes);
        ImGui.sameLine();
        if (ImGui.button("Hayır")) step(node.no);
      case Dialog.EVENT:
        ImGui.text('Olay yayılır: ${blank(node.event) ? "(adsız)" : node.event}. Bu olayı bekleyen tetikleyicinin eylemleri çalışır.');
        if (ImGui.button("Devam")) step(node.next);
      default:
        step(node.next);
    }
    ImGui.sameLine();
    if (ImGui.button("Kapat")) previewNode = 0;
  }

  function restartPreview(dialog : Dialog) {
    var start = dialog.start();
    step(start == null ? 0 : start.next);
  }

  function step(target : Null<Int>) {
    previewNode = target == null || target <= 0 ? -1 : target;
    if (previewNode > 0) selectAfter = previewNode;
  }

  // Inspector, diyalog açıkken sahne nesnesi yerine seçili düğümü gösterir.
  public function drawProperties() {
    var dialog = editor.dialogs.dialogs.get(current);
    if (dialog == null) return;
    ImGui.textDisabled('Diyalog: ${dialog.title} (${dialog.id})');
    var node = selected.length == 1 ? dialog.node(selected[0]) : null;
    if (node == null) {
      drawDialogProperties(dialog);
      return;
    }
    ImGui.separator();
    ImGui.textColored(COLORS.get(node.type), TITLES.get(node.type));
    ImGui.textWrapped(HELP.get(node.type));
    ImGui.spacing();
    ImGui.pushID('${node.id}');
    switch (node.type) {
      case Dialog.LINE:
        drawSpeaker(node);
        ImGui.text("Söylediği");
        var text = node.text == null ? "" : node.text;
        focusField();
        var lines = ImGui.getTextLineHeight() * TEXT_LINES + ImGui.getStyle().FramePadding.y * 2;
        if (ImGui.inputTextMultiline("##metin", text, {x: -1, y: lines})) node.text = text;
        track("Satır");
        // Bu ImGui sürümünde çok satırlı kutu satır kaydırmaz; oyun kaydırır. Sığmayan metin burada tam görünür.
        var box = ImGui.getItemRectSize().x - ImGui.getStyle().FramePadding.x * 2;
        if (Lambda.exists(text.split("\n"), part -> ImGui.calcTextSize(part).x > box)) {
          ImGui.textDisabled("Tamamı:");
          ImGui.pushTextWrapPos(0);
          ImGui.text(text);
          ImGui.popTextWrapPos();
        }
      case Dialog.CHOICES:
        drawChoices(node);
      case Dialog.CONDITION:
        drawCondition(node);
      case Dialog.EVENT:
        var event = node.event == null ? "" : node.event;
        focusField();
        if (ImGui.inputText("Olay adı", event)) node.event = event;
        track("Olay");
      default:
    }
    focusText = false;
    if (node.type != Dialog.START) {
      ImGui.separator();
      if (ImGui.button("Düğümü sil")) {
        var id = node.id;
        change("Sil", d -> d.remove(id));
      }
    }
    ImGui.popID();
  }

  function drawDialogProperties(dialog : Dialog) {
    var title = dialog.title;
    if (ImGui.inputText("Başlık", title)) dialog.title = title;
    track("Diyalog adı");
    ImGui.spacing();
    if (selected.length > 1) ImGui.text('${selected.length} düğüm seçili. Delete ile silinir.');
    else ImGui.textWrapped("Bir düğüme tıkla: ayrıntısı burada düzenlenir.");
    ImGui.spacing();
    var starters = DataUsage.dialogStarters(editor, current);
    ImGui.text("Başlatan");
    if (starters.length == 0) ImGui.textDisabled("Henüz hiçbir tetikleyici başlatmıyor");
    for (name in starters) ImGui.bulletText(name);
  }

  function drawSpeaker(node : DialogNode) {
    var speaker = node.speaker == null ? "" : node.speaker;
    if (ImGui.inputText("Konuşan", speaker)) node.speaker = speaker;
    track("Konuşan");
    var names = speakers();
    if (names.length == 0) return;
    ImGui.sameLine();
    if (!ImGui.beginCombo("##konusanlar", "", ImGuiComboFlags.NoPreview)) return;
    for (name in names) if (ImGui.selectable(name)) {
      var id = node.id;
      change("Konuşan", d -> d.node(id).speaker = name);
    }
    ImGui.endCombo();
  }

  function drawChoices(node : DialogNode) {
    var choices = node.choices == null ? [] : node.choices;
    var id = node.id;
    for (k in 0...choices.length) {
      ImGui.pushID('secenek$k');
      ImGui.text('${k + 1}.');
      ImGui.sameLine();
      if (k == 0) focusField();
      ImGui.setNextItemWidth(-ImGui.calcTextSize("Sil").x - ImGui.getStyle().FramePadding.x * 4);
      var text = choices[k].text;
      if (ImGui.inputText("##secenek", text)) choices[k].text = text;
      track("Seçenek");
      ImGui.sameLine();
      if (ImGui.smallButton("Sil")) change("Seçenek sil", d -> d.node(id).choices.splice(k, 1));
      ImGui.popID();
    }
    if (ImGui.button("+ Seçenek")) change("Seçenek ekle", d -> {
      var target = d.node(id);
      if (target.choices == null) target.choices = [];
      target.choices.push({text: "", next: 0});
    });
  }

  function drawCondition(node : DialogNode) {
    var id = node.id;
    var isItem = node.kind == Dialog.ITEM, isStanding = node.kind == Dialog.STANDING;
    if (ImGui.radioButton("Değişken", !isItem && !isStanding)) change("Koşul türü", d -> d.node(id).kind = Dialog.FLAG);
    ImGui.sameLine();
    if (ImGui.radioButton("Eşya", isItem)) change("Koşul türü", d -> d.node(id).kind = Dialog.ITEM);
    ImGui.sameLine();
    if (ImGui.radioButton("İlişki", isStanding)) change("Koşul türü", d -> d.node(id).kind = Dialog.STANDING);
    var name = node.name == null ? "" : node.name;
    var tableName = isItem ? editor.dialogs.itemTable : isStanding ? editor.dialogs.factionTable : null;
    var items = tableName == null ? null : editor.data.tables.get(tableName);
    if ((isItem || isStanding) && items != null) {
      var preview = name == "" ? "(seç)" : items.find(name) == null ? '$name (bulunamadı)' : items.label(name);
      if (ImGui.beginCombo(isItem ? "Eşya" : "Fraksiyon", preview)) {
        for (row in items.ids()) {
          var chosen = row == name;
          if (ImGui.selectable(items.label(row), chosen)) change("Koşul", d -> d.node(id).name = row);
        }
        ImGui.endCombo();
      }
    } else {
      focusField();
      if (ImGui.inputText(isItem ? "Eşya kimliği" : isStanding ? "Fraksiyon kimliği" : "Değişken adı", name)) node.name = name;
      track("Koşul");
    }
    var value : Int = node.value == null ? 1 : node.value;
    if (ImGui.inputInt("En az", value)) node.value = value;
    track("Koşul");
  }

  function focusField() {
    if (focusText) ImGui.setKeyboardFocusHere();
    focusText = false;
  }

  function speakers() : Array<String> {
    var names = [];
    for (id in editor.dialogs.ids())
      for (node in editor.dialogs.dialogs.get(id).nodes)
        if (!blank(node.speaker) && names.indexOf(node.speaker) < 0) names.push(node.speaker);
    names.sort(Reflect.compare);
    return names;
  }

  // Tetikleyici işaretçisi ve diyalog başlatan eylem oyunun kodundadır; kayıtlı bileşenlerden bulunur.
  function starterTypes() : Null<{marker : String, action : String, field : String}> {
    var registry = editor.scene.registry;
    var marker = null, action = null, field = null;
    for (type in registry.currentTypes()) {
      var sample = registry.create(type);
      var placed = Std.downcast(sample, Marker);
      if (marker == null && placed != null && placed.isPlaceable() && sample.addable().indexOf(TriggerAction.CATEGORY) >= 0) marker = type;
      if (action == null && Std.isOfType(sample, TriggerAction))
        for (info in sample.describeFields()) switch (info.hint) {
          case HDialog:
            action = type;
            field = info.name;
          default:
        }
    }
    return marker == null || action == null ? null : {marker: marker, action: action, field: field};
  }

  function addStarter(starter : {marker : String, action : String, field : String}) {
    var data = new ComponentData(starter.action);
    data.fields.set(starter.field, current);
    var title = editor.dialogs.dialogs.get(current).title;
    close();
    editor.actions.addMarker(starter.marker, [data], 'Tetikleyici: $title');
    editor.show("Tetikleyici eklendi. Ekibin geçeceği yere taşı.");
  }

  function newNode(id : Int, type : String, x : Float, y : Float) : DialogNode {
    var node : DialogNode = {id: id, type: type, x: x, y: y};
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

  function connect(dialog : Dialog, from : Int, target : Int) {
    var node = dialog.node(Std.int(from / PIN_STRIDE));
    if (node == null) return;
    var slot = from % PIN_STRIDE;
    if (slot == NEXT) node.next = target;
    else if (slot == YES) node.yes = target;
    else if (slot == NO) node.no = target;
    else if (slot >= CHOICE && node.choices != null && slot - CHOICE < node.choices.length) node.choices[slot - CHOICE].next = target;
  }

  // Tuval birimi ekran pikselidir: Retina'da yazı iki kat, düğüm ve konumlar da iki kat çizilir.
  inline function unit() {
    return editor.interfaceScale;
  }

  function nodeWidth() {
    return NODE_WIDTH * unit();
  }

  function toCanvas(x : Float, y : Float) : ImVec2 {
    return {x: x * unit(), y: y * unit()};
  }

  // Düğüm editörünün kendi ölçüleri ImGui ile büyümez: boşluk ve çizgiler de netlikle çarpılır.
  function pushScaledStyle() {
    var u = unit();
    NodeEditor.pushStyleVar3(StyleVar.NodePadding, {x: NODE_PADDING * u, y: NODE_PADDING * u, z: NODE_PADDING * u, w: NODE_PADDING * u});
    NodeEditor.pushStyleVar(StyleVar.NodeRounding, 6 * u);
    NodeEditor.pushStyleVar(StyleVar.NodeBorderWidth, 1.5 * u);
    NodeEditor.pushStyleVar(StyleVar.HoveredNodeBorderWidth, 3 * u);
    NodeEditor.pushStyleVar(StyleVar.SelectedNodeBorderWidth, 3 * u);
    NodeEditor.pushStyleVar(StyleVar.LinkStrength, 100 * u);
  }

  static function slots(node : DialogNode) : Array<Int> {
    return switch (node.type) {
      case Dialog.CONDITION: [YES, NO];
      case Dialog.CHOICES: [for (k in 0...(node.choices == null ? 0 : node.choices.length)) CHOICE + k];
      case Dialog.END: [];
      default: [NEXT];
    };
  }

  static function targetOf(node : DialogNode, slot : Int) : Int {
    var target : Null<Int> = slot == NEXT ? node.next : slot == YES ? node.yes : slot == NO ? node.no
      : node.choices != null && slot - CHOICE < node.choices.length ? node.choices[slot - CHOICE].next : 0;
    return target == null ? 0 : target;
  }

  static function conditionText(node : DialogNode) {
    var name = blank(node.name) ? "(adsız)" : node.name;
    var value = node.value == null ? 1 : node.value;
    return node.kind == Dialog.ITEM ? 'Eşya $name en az $value' : node.kind == Dialog.STANDING ? 'İlişki $name en az $value' : '$name en az $value';
  }


  // Sürükleme bitince yer değişikliği tek adım olur; geri alınınca düğüm eski yerine döner.
  function syncPositions(dialog : Dialog) {
    if (ImGui.isMouseDown(0)) return;
    var moved = dialog.clone();
    var hasMoved = false;
    for (node in dialog.nodes) {
      var at = NodeEditor.getNodePosition(node.id);
      if (at == null) continue;
      var stored = toCanvas(node.x, node.y);
      // Dosyadaki tam sayı konum tuvalde netlik kadar kayabilir: bir birimden azı taşıma sayılmaz.
      if (Math.abs(at.x - stored.x) < unit() && Math.abs(at.y - stored.y) < unit()) continue;
      if (ImGui.isMouseReleased(0)) {
        moved.node(node.id).x = at.x / unit();
        moved.node(node.id).y = at.y / unit();
        hasMoved = true;
      } else {
        NodeEditor.setNodePosition(node.id, stored);
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
