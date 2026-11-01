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

// Birlikte düzenleme kilit ister. Kilitli grupta bileşen alanları hepsine uygulanır, yalnızca
// grubun tümünde o bileşen varsa görünür. Dönüşüm gizmodadır: grup tek parça gibi döner, burada
// tek bir değer yazmak nesnelerin düzenini bozardı.
class InspectorPanel {
  static inline var ADD_COMPONENT = "add-component";
  static inline var MIXED = "karışık";
  static inline var NUMBER = "%.6f";
  static inline var LABEL_SAMPLE = "Yükseklik ";
  static inline var LABEL_SHARE = 0.35;

  var editor : Editor;
  var nameStart = "";
  var transformStart : Transform;
  var fieldStarts : Array<Dynamic> = [];
  var removing : Null<Array<Component>>;

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function draw() {
    var entities = editor.selection.items;
    if (entities.length == 0) {
      ImGui.textDisabled("Bir nesne seç");
      return;
    }
    if (!editor.canEdit()) {
      ImGui.textWrapped('${entities.length} nesne seçili. Birlikte düzenlemek için araç çubuğundaki Kilitle düğmesine bas.');
      return;
    }
    var primary = entities[entities.length - 1];
    // Etiketler alanın sağındadır: dar panelde kesilmesin diye yer önce onlara ayrılır.
    ImGui.pushItemWidth(-Math.max(ImGui.calcTextSize(LABEL_SAMPLE).x, ImGui.getContentRegionAvail().x * LABEL_SHARE));
    var together = entities.length > 1;
    if (together) ImGui.textWrapped('${entities.length} nesne kilitli. Sahnede tek parça gibi taşınır, döner ve ölçeklenir.');
    else drawName(primary);
    drawVisibility(entities);
    if (!together && ImGui.collapsingHeader("Dönüşüm", ImGuiTreeNodeFlags.DefaultOpen)) drawTransform(primary);
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
    ImGui.popItemWidth();
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

  function drawTransform(entity : Entity) {
    drag(entity, "Konum X", entity.x, 0.1, v -> entity.setPosition(v, entity.y, entity.z));
    drag(entity, "Konum Y", entity.y, 0.1, v -> entity.setPosition(entity.x, v, entity.z));
    drag(entity, "Konum Z", entity.z, 0.1, v -> entity.setPosition(entity.x, entity.y, v));
    drag(entity, "Dönüş X", entity.rotX, 1, v -> entity.setRotation(v, entity.rotY, entity.rotZ));
    drag(entity, "Dönüş Y", entity.rotY, 1, v -> entity.setRotation(entity.rotX, v, entity.rotZ));
    drag(entity, "Dönüş Z", entity.rotZ, 1, v -> entity.setRotation(entity.rotX, entity.rotY, v));
    drag(entity, "Ölçek X", entity.scaleX, 0.01, v -> entity.setScale(v, entity.scaleY, entity.scaleZ));
    drag(entity, "Ölçek Y", entity.scaleY, 0.01, v -> entity.setScale(entity.scaleX, v, entity.scaleZ));
    drag(entity, "Ölçek Z", entity.scaleZ, 0.01, v -> entity.setScale(entity.scaleX, entity.scaleY, v));
  }

  function drag(entity : Entity, label : String, value : Float, speed : Float, apply : Float->Void) {
    var edited = ImGui.dragDouble(label, value, speed);
    if (ImGui.isItemActivated()) transformStart = SetTransformCommand.capture(entity);
    if (edited) apply(value);
    if (ImGui.isItemDeactivatedAfterEdit())
      editor.commands.execute(new SetTransformCommand(entity, transformStart, SetTransformCommand.capture(entity)));
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
