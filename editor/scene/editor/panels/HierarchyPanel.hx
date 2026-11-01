package scene.editor.panels;

import hxd.Key;
import imgui.ImGui;
import scene.Entity;
import scene.editor.commands.SetActiveCommand;
import scene.editor.commands.SetNameCommand;

class HierarchyPanel {
  static inline var PAYLOAD = "ENTITY";
  static inline var RENAME_WAIT_FRAMES = 4;
  static inline var EDITOR_TIP = "Editörde görünür. Yalnızca bu bilgisayarı etkiler, sahneye yazılmaz.";
  static inline var GAME_TIP = "Oyunda görünür. Sahneye kaydedilir, editörde görünmeye devam eder.";
  static inline var LOCK_TIP = "Kilitli: sahnede tıklanamaz, buradan seçilebilir. Yalnızca bu bilgisayarı etkiler.";

  var editor : Editor;
  var renaming : Null<Entity>;
  var renameText = "";
  var renameFocus = false;
  var renameWait = 0;
  var dragged : Array<Entity> = [];
  var pressed : Null<Entity>;
  var opening = new Map<Entity, Bool>();
  var deferred : Array<Void->Void> = [];
  var payload = new hl.Bytes(1);
  var togglesAt = 0.;
  var toggleStep = 0.;

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function draw() {
    drawHeader();
    for (entity in editor.scene.entities) if (entity.parent == null) drawEntity(entity);
    drawEmptyArea();
    // Ağaç çizilirken sahne değişmemeli, işler çizimden sonra yapılır.
    for (action in deferred) action();
    deferred = [];
    // Hedefe bırakılmayan sürükleme sonraki tıklamayı etkilemesin.
    if (ImGui.isMouseReleased(0)) {
      pressed = null;
      dragged = [];
    }
  }

  public function rename(entity : Null<Entity>) {
    if (entity == null) return;
    reveal(entity);
    renaming = entity;
    renameText = entity.name;
    renameFocus = true;
    renameWait = RENAME_WAIT_FRAMES;
  }

  // Sahnede seçilen nesne kapalı bir dalın içindeyse dal açılır.
  public function reveal(entity : Entity) {
    var parent = entity.parent;
    while (parent != null) {
      opening.set(parent, true);
      parent = parent.parent;
    }
  }

  // İşaretler sağda sabit sütundadır: girintiye göre kaymaz, satırlar göz yormaz.
  function drawHeader() {
    toggleStep = ImGui.getTextLineHeightWithSpacing();
    var width = ImGui.getWindowSize().x - ImGui.getStyle().ScrollbarSize;
    togglesAt = width - toggleStep * 3.5;
    drawColumnTitle("E", 0, EDITOR_TIP);
    drawColumnTitle("O", 1, GAME_TIP);
    drawColumnTitle("K", 2, LOCK_TIP);
  }

  function drawColumnTitle(title : String, column : Int, tip : String) {
    ImGui.sameLine(togglesAt + toggleStep * column);
    ImGui.textDisabled(title);
    if (ImGui.isItemHovered()) ImGui.setTooltip(tip);
  }

  function drawEntity(entity : Entity) {
    if (opening.remove(entity)) ImGui.setNextItemOpen(true);
    var selection = editor.selection;
    var flags = ImGuiTreeNodeFlags.OpenOnArrow | ImGuiTreeNodeFlags.SpanAvailWidth | ImGuiTreeNodeFlags.AllowItemOverlap;
    if (selection.has(entity)) flags |= ImGuiTreeNodeFlags.Selected;
    if (entity.children.length == 0) flags |= ImGuiTreeNodeFlags.Leaf;

    var dim = !entity.active || entity.hiddenInEditor;
    // getColorU32 renk kimliğini değer sanar ve saydam döner, bu yüzden Vec4 sürümü kullanılır.
    if (dim) ImGui.pushStyleColor(ImGuiCol.Text, ImGui.getStyleColorVec4(ImGuiCol.TextDisabled));
    var label = renaming == entity ? "" : entity.active ? entity.name : entity.name + " (oyunda kapalı)";
    var open = ImGui.treeNodeEx(entity.id, flags, label);
    if (dim) ImGui.popStyleColor();

    readClick(entity);
    drawMenu(entity);
    drawDrag(entity);
    if (renaming == entity) drawRename(entity);
    drawToggles(entity);

    if (!open) return;
    for (child in entity.children) drawEntity(child);
    ImGui.treePop();
  }

  // Görünürlük kutuları satırın üstünde durur: oradaki tıklama satıra sayılmaz.
  function isOverLabel() {
    return ImGui.getMousePos().x - ImGui.getWindowPos().x < togglesAt;
  }

  function readClick(entity : Entity) {
    var selection = editor.selection;
    var onLabel = isOverLabel();
    if (onLabel && ImGui.isItemClicked() && !ImGui.isItemToggledOpen()) {
      if (Key.isDown(Key.SHIFT) || editor.isCommandHeld()) selection.toggle(entity);
      else if (selection.has(entity)) pressed = entity;
      else selection.set([entity]);
    }
    // Çoklu seçimde sürükleme başlayabilir, tek seçime ancak bırakınca düşülür.
    if (pressed == entity && ImGui.isMouseReleased(0) && dragged.length == 0) selection.set([entity]);
    if (onLabel && ImGui.isItemHovered() && ImGui.isMouseDoubleClicked(0)) rename(entity);
  }

  function drawMenu(entity : Entity) {
    if (!ImGui.beginPopupContextItem()) return;
    var actions = editor.actions;
    if (!editor.selection.has(entity)) editor.selection.set([entity]);
    if (ImGui.menuItem("Yeniden adlandır", "F2")) rename(entity);
    if (ImGui.menuItem("Alt nesne ekle")) deferred.push(() -> actions.createEmpty(entity));
    if (ImGui.menuItem("Çoğalt", editor.commandName + "+D")) deferred.push(actions.duplicate);
    if (ImGui.menuItem("Sil", "Del")) deferred.push(actions.remove);
    ImGui.endPopup();
  }

  function drawDrag(entity : Entity) {
    if (ImGui.beginDragDropSource()) {
      if (!editor.selection.has(entity)) editor.selection.set([entity]);
      dragged = editor.selection.roots();
      ImGui.setDragDropPayload(PAYLOAD, payload, 1);
      ImGui.text(dragged.length == 1 ? entity.name : '${dragged.length} nesne');
      ImGui.endDragDropSource();
    }
    if (ImGui.beginDragDropTarget()) {
      if (ImGui.acceptDragDropPayload(PAYLOAD) != null) moveDragged(entity);
      ImGui.endDragDropTarget();
    }
  }

  function moveDragged(parent : Null<Entity>) {
    var moved = dragged;
    dragged = [];
    deferred.push(() -> editor.actions.reparent(moved, parent));
  }

  function drawRename(entity : Entity) {
    ImGui.sameLine();
    ImGui.setNextItemWidth(Math.max(togglesAt - ImGui.getCursorPosX(), 40));
    if (renameFocus) {
      ImGui.setKeyboardFocusHere();
      renameFocus = false;
    }
    var name = renameText;
    if (ImGui.inputText("##rename", name)) renameText = name;
    if (ImGui.isItemActive()) renameWait = 0;
    else if (renameWait > 0 && --renameWait == 0) renaming = null;  // Odak alınamadı: satır takılı kalmasın.
    if (!ImGui.isItemDeactivated()) return;
    var text = StringTools.trim(renameText);
    var cancelled = Key.isDown(Key.ESCAPE) || text == "" || text == entity.name;
    renaming = null;
    if (!cancelled) deferred.push(() -> editor.commands.execute(new SetNameCommand(entity, entity.name, text)));
  }

  function drawToggles(entity : Entity) {
    ImGui.pushStyleVar(ImGuiStyleVar.FramePadding, {x: 0, y: 0});
    ImGui.sameLine(togglesAt);
    var seen = !entity.hiddenInEditor;
    if (ImGui.checkbox('##editor-${entity.id}', seen)) {
      entity.hiddenInEditor = !seen;
      editor.document.rememberFlags();
    }
    if (ImGui.isItemHovered()) ImGui.setTooltip(EDITOR_TIP);
    ImGui.sameLine(togglesAt + toggleStep);
    var inGame = entity.active;
    if (ImGui.checkbox('##game-${entity.id}', inGame)) editor.commands.execute(new SetActiveCommand(entity, inGame));
    if (ImGui.isItemHovered()) ImGui.setTooltip(GAME_TIP);
    ImGui.sameLine(togglesAt + toggleStep * 2);
    var locked = entity.lockedInEditor;
    if (ImGui.checkbox('##lock-${entity.id}', locked)) {
      entity.lockedInEditor = locked;
      editor.document.rememberFlags();
    }
    if (ImGui.isItemHovered()) ImGui.setTooltip(LOCK_TIP);
    ImGui.popStyleVar();
  }

  // Boş alana tıklamak seçimi kaldırır, buraya bırakılan nesne en üst seviyeye çıkar.
  function drawEmptyArea() {
    var free = ImGui.getContentRegionAvail();
    if (free.y < 1 || free.x < 1) return;
    ImGui.invisibleButton("##empty", {x: free.x, y: free.y});
    if (ImGui.isItemClicked() && !Key.isDown(Key.SHIFT) && !editor.isCommandHeld()) editor.selection.clear();
    if (ImGui.beginDragDropTarget()) {
      if (ImGui.acceptDragDropPayload(PAYLOAD) != null) moveDragged(null);
      ImGui.endDragDropTarget();
    }
    if (ImGui.beginPopupContextItem()) {
      if (ImGui.menuItem("Boş nesne ekle")) deferred.push(() -> editor.actions.createEmpty());
      ImGui.endPopup();
    }
  }
}
