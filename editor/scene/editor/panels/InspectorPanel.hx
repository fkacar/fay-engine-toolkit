package scene.editor.panels;

import imgui.ImGui;
import scene.Component;
import scene.Entity;
import scene.FieldInfo;
import scene.editor.commands.AddComponentCommand;
import scene.editor.commands.GroupCommand;
import scene.editor.commands.RemoveComponentCommand;
import scene.editor.commands.SetActiveCommand;
import scene.editor.commands.SetFieldCommand;
import scene.editor.commands.SetNameCommand;
import scene.editor.commands.SetTransformCommand;
import scene.editor.commands.SetTransformCommand.Transform;

// Birden çok nesne seçiliyse değişiklik hepsine uygulanır. Bileşen alanları yalnızca
// seçilenlerin tümünde o bileşen varsa görünür.
class InspectorPanel {
  static inline var ADD_COMPONENT = "add-component";
  static inline var PIN_TIP = "Seçim değişse de Inspector bu nesnelerde kalır.";
  static inline var MIXED = "karışık";
  static inline var NUMBER = "%.6f";

  var editor : Editor;
  var pinned : Array<Entity> = [];
  var nameStart = "";
  var transformStarts : Array<Transform> = [];
  var fieldStarts : Array<Dynamic> = [];
  var removing : Null<Array<Component>>;

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function draw() {
    var entities = targets();
    if (entities.length == 0) {
      ImGui.textDisabled("Bir nesne seç");
      return;
    }
    var primary = entities[entities.length - 1];
    drawPin(entities);
    if (entities.length > 1) ImGui.textDisabled('${entities.length} nesne birlikte düzenleniyor');
    else drawName(primary);
    drawVisibility(entities);
    if (ImGui.collapsingHeader("Dönüşüm", ImGuiTreeNodeFlags.DefaultOpen)) drawTransform(entities);
    for (component in primary.components) {
      var peers = peersOf(component, entities);
      if (peers != null) drawComponent(peers);
    }
    if (removing != null) {
      var commands : Array<Command> = [for (component in removing) new RemoveComponentCommand(component.entity, component)];
      editor.commands.execute(new GroupCommand("Bileşeni kaldır", commands));
      removing = null;
    }
    drawAddComponent(entities);
  }

  function targets() {
    pinned = pinned.filter(entity -> editor.scene.contains(entity));
    return pinned.length > 0 ? pinned : editor.selection.items;
  }

  function drawPin(entities : Array<Entity>) {
    var locked = pinned.length > 0;
    if (ImGui.checkbox("Kilitle", locked)) pinned = locked ? entities.copy() : [];
    if (ImGui.isItemHovered()) ImGui.setTooltip(PIN_TIP);
  }

  function drawName(entity : Entity) {
    var name = entity.name;
    var edited = ImGui.inputText("Ad", name);
    if (ImGui.isItemActivated()) nameStart = entity.name;
    if (edited) entity.name = name;
    if (ImGui.isItemDeactivatedAfterEdit()) editor.commands.execute(new SetNameCommand(entity, nameStart, name));
  }

  function drawVisibility(entities : Array<Entity>) {
    var primary = entities[entities.length - 1];
    var seen = !primary.hiddenInEditor;
    if (ImGui.checkbox("Editörde görünür", seen)) {
      for (entity in entities) entity.hiddenInEditor = !seen;
      editor.document.rememberFlags();
    }
    var inGame = primary.active;
    if (ImGui.checkbox("Oyunda görünür", inGame)) {
      var commands : Array<Command> = [for (entity in entities) new SetActiveCommand(entity, inGame)];
      editor.commands.execute(new GroupCommand("Oyunda göster/gizle", commands));
    }
  }

  function drawTransform(entities : Array<Entity>) {
    drag(entities, "Konum X", e -> e.x, 0.1, (e, v) -> e.setPosition(v, e.y, e.z));
    drag(entities, "Konum Y", e -> e.y, 0.1, (e, v) -> e.setPosition(e.x, v, e.z));
    drag(entities, "Konum Z", e -> e.z, 0.1, (e, v) -> e.setPosition(e.x, e.y, v));
    drag(entities, "Dönüş X", e -> e.rotX, 1, (e, v) -> e.setRotation(v, e.rotY, e.rotZ));
    drag(entities, "Dönüş Y", e -> e.rotY, 1, (e, v) -> e.setRotation(e.rotX, v, e.rotZ));
    drag(entities, "Dönüş Z", e -> e.rotZ, 1, (e, v) -> e.setRotation(e.rotX, e.rotY, v));
    drag(entities, "Ölçek X", e -> e.scaleX, 0.01, (e, v) -> e.setScale(v, e.scaleY, e.scaleZ));
    drag(entities, "Ölçek Y", e -> e.scaleY, 0.01, (e, v) -> e.setScale(e.scaleX, v, e.scaleZ));
    drag(entities, "Ölçek Z", e -> e.scaleZ, 0.01, (e, v) -> e.setScale(e.scaleX, e.scaleY, v));
  }

  function drag(entities : Array<Entity>, label : String, read : Entity->Float, speed : Float, apply : (Entity, Float)->Void) {
    var value = read(entities[entities.length - 1]);
    var mixed = Lambda.exists(entities, entity -> read(entity) != value);
    var edited = ImGui.dragDouble(label, value, speed, 0, 0, mixed ? MIXED : NUMBER);
    if (ImGui.isItemActivated()) transformStarts = [for (entity in entities) SetTransformCommand.capture(entity)];
    if (edited) for (entity in entities) apply(entity, value);
    if (!ImGui.isItemDeactivatedAfterEdit()) return;
    var commands : Array<Command> = [
      for (i in 0...entities.length) new SetTransformCommand(entities[i], transformStarts[i], SetTransformCommand.capture(entities[i]))
    ];
    editor.commands.execute(new GroupCommand("Dönüşüm", commands));
  }

  // Sona asıl bileşen konur: alanlar ondan okunur.
  function peersOf(component : Component, entities : Array<Entity>) : Null<Array<Component>> {
    var id = component.componentId();
    var peers = [];
    for (entity in entities) {
      if (entity == component.entity) continue;
      var match = Lambda.find(entity.components, other -> other.componentId() == id);
      if (match == null) return null;
      peers.push(match);
    }
    peers.push(component);
    return peers;
  }

  function drawComponent(peers : Array<Component>) {
    var component = peers[peers.length - 1];
    var name = component.componentId();
    ImGui.pushID(name);
    var open = ImGui.collapsingHeader(name, ImGuiTreeNodeFlags.DefaultOpen);
    if (ImGui.beginPopupContextItem()) {
      if (ImGui.menuItem("Bileşeni kaldır")) removing = peers;
      ImGui.endPopup();
    }
    if (open) for (field in component.describeFields()) drawField(peers, field);
    ImGui.popID();
  }

  function drawAddComponent(entities : Array<Entity>) {
    ImGui.separator();
    if (ImGui.button("Bileşen ekle")) ImGui.openPopup(ADD_COMPONENT);
    if (!ImGui.beginPopup(ADD_COMPONENT)) return;
    var registry = editor.scene.registry;
    for (type in registry.currentTypes()) {
      if (!ImGui.selectable(type)) continue;
      var commands : Array<Command> = [for (entity in entities) new AddComponentCommand(entity, registry.create(type))];
      editor.commands.execute(new GroupCommand("Bileşen ekle", commands));
    }
    ImGui.endPopup();
  }

  function drawField(peers : Array<Component>, field : FieldInfo) {
    var label = field.label + "##" + field.name;
    var component = peers[peers.length - 1];
    var before : Dynamic = component.readField(field.name);
    switch (field.kind) {
      case KFloat:
        var value : Float = before;
        var low : Float = field.min == null ? 0 : field.min;
        var high : Float = field.max == null ? 0 : field.max;
        var mixed = Lambda.exists(peers, other -> other.readField(field.name) != before);
        var edited = ImGui.dragDouble(label, value, 0.1, low, high, mixed ? MIXED : NUMBER);
        trackEdit(peers, field, value, edited);
      case KInt:
        var value : Int = before;
        var edited = ImGui.inputInt(label, value);
        trackEdit(peers, field, value, edited);
      case KString if (field.hint == HEntity):
        drawEntityField(peers, field, label, before);
      case KString:
        var value : String = before;
        var edited = ImGui.inputText(label, value);
        trackEdit(peers, field, value, edited);
        if (field.hint == HAsset) acceptAsset(peers, field);
      case KBool:
        var value : Bool = before;
        if (ImGui.checkbox(label, value)) set(peers, field, value);
    }
  }

  function acceptAsset(peers : Array<Component>, field : FieldInfo) {
    if (!ImGui.beginDragDropTarget()) return;
    if (ImGui.acceptDragDropPayload(AssetBrowser.PAYLOAD) != null) set(peers, field, editor.assetDrag);
    ImGui.endDragDropTarget();
  }

  function drawEntityField(peers : Array<Component>, field : FieldInfo, label : String, before : String) {
    var scene = editor.scene;
    var current = before == "" ? null : scene.find(before);
    var preview = before == "" ? "(yok)" : current == null ? "(bulunamadı)" : current.name;
    if (!ImGui.beginCombo(label, preview)) return;
    // hlimgui sabit değeri Ref sürümüne bağlar ve yerel kodda çöker: değer değişkenle verilir.
    var empty = before == "";
    if (ImGui.selectable("(yok)", empty)) set(peers, field, "");
    for (entity in scene.entities) {
      var chosen = entity == current;
      if (ImGui.selectable(entity.name + "##" + entity.id, chosen)) set(peers, field, entity.id);
    }
    ImGui.endCombo();
  }

  function set(peers : Array<Component>, field : FieldInfo, value : Dynamic) {
    commit(peers, field, [for (component in peers) component.readField(field.name)], value);
  }

  function commit(peers : Array<Component>, field : FieldInfo, starts : Array<Dynamic>, value : Dynamic) {
    var commands : Array<Command> = [
      for (i in 0...peers.length) new SetFieldCommand(peers[i], field.name, starts[i], value, field.label)
    ];
    editor.commands.execute(new GroupCommand(field.label, commands));
  }

  // Sürükleme boyunca değer canlı uygulanır, undo'ya tek adım olarak bırakınca girer.
  function trackEdit(peers : Array<Component>, field : FieldInfo, value : Dynamic, edited : Bool) {
    if (ImGui.isItemActivated()) fieldStarts = [for (component in peers) component.readField(field.name)];
    if (edited) {
      for (component in peers) {
        component.writeField(field.name, value);
        component.refresh();
      }
    }
    if (ImGui.isItemDeactivatedAfterEdit()) commit(peers, field, fieldStarts, value);
  }
}
