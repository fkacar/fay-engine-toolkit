package scene.editor.panels;

import imgui.ImGui;
import scene.Component;
import scene.Entity;
import scene.FieldInfo;
import scene.editor.commands.AddComponentCommand;
import scene.editor.commands.RemoveComponentCommand;
import scene.editor.commands.SetActiveCommand;
import scene.editor.commands.SetFieldCommand;
import scene.editor.commands.SetNameCommand;
import scene.editor.commands.SetTransformCommand;
import scene.editor.commands.SetTransformCommand.Transform;

class InspectorPanel {
  static inline var ADD_COMPONENT = "add-component";

  var editor : Editor;
  var editStart : Dynamic;
  var transformStart : Transform;
  var removing : Null<Component>;

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function draw() {
    var selection = editor.selection;
    var entity = selection.primary;
    if (entity == null) {
      ImGui.textDisabled("Bir nesne seç");
      return;
    }
    if (selection.items.length > 1) ImGui.textDisabled('${selection.items.length} nesne seçili, biri gösteriliyor');
    drawName(entity);
    drawVisibility(entity);
    if (ImGui.collapsingHeader("Dönüşüm", ImGuiTreeNodeFlags.DefaultOpen)) drawTransform(entity);
    for (component in entity.components) drawComponent(component);
    if (removing != null) {
      editor.commands.execute(new RemoveComponentCommand(entity, removing));
      removing = null;
    }
    drawAddComponent(entity);
  }

  function drawName(entity : Entity) {
    var name = entity.name;
    var edited = ImGui.inputText("Ad", name);
    if (ImGui.isItemActivated()) editStart = entity.name;
    if (edited) entity.name = name;
    if (ImGui.isItemDeactivatedAfterEdit()) editor.commands.execute(new SetNameCommand(entity, editStart, name));
  }

  function drawVisibility(entity : Entity) {
    var seen = !entity.hiddenInEditor;
    if (ImGui.checkbox("Editörde görünür", seen)) {
      entity.hiddenInEditor = !seen;
      editor.document.rememberHidden();
    }
    var inGame = entity.active;
    if (ImGui.checkbox("Oyunda görünür", inGame)) editor.commands.execute(new SetActiveCommand(entity, inGame));
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

  function drawComponent(component : Component) {
    var name = component.componentId();
    ImGui.pushID(name);
    var open = ImGui.collapsingHeader(name, ImGuiTreeNodeFlags.DefaultOpen);
    if (ImGui.beginPopupContextItem()) {
      if (ImGui.menuItem("Bileşeni kaldır")) removing = component;
      ImGui.endPopup();
    }
    if (open) for (field in component.describeFields()) drawField(component, field);
    ImGui.popID();
  }

  function drawAddComponent(entity : Entity) {
    ImGui.separator();
    if (ImGui.button("Bileşen ekle")) ImGui.openPopup(ADD_COMPONENT);
    if (!ImGui.beginPopup(ADD_COMPONENT)) return;
    var registry = editor.scene.registry;
    for (type in registry.currentTypes())
      if (ImGui.selectable(type)) editor.commands.execute(new AddComponentCommand(entity, registry.create(type)));
    ImGui.endPopup();
  }

  public function drawField(component : Component, field : FieldInfo) {
    var label = field.label + "##" + field.name;
    var before : Dynamic = component.readField(field.name);
    switch (field.kind) {
      case KFloat:
        var value : Float = before;
        var low : Float = field.min == null ? 0 : field.min;
        var high : Float = field.max == null ? 0 : field.max;
        var edited = ImGui.dragDouble(label, value, 0.1, low, high);
        trackEdit(component, field, before, value, edited);
      case KInt:
        var value : Int = before;
        var edited = ImGui.inputInt(label, value);
        trackEdit(component, field, before, value, edited);
      case KString if (field.hint == HEntity):
        drawEntityField(component, field, label, before);
      case KString:
        var value : String = before;
        var edited = ImGui.inputText(label, value);
        trackEdit(component, field, before, value, edited);
        if (field.hint == HAsset) acceptAsset(component, field, before);
      case KBool:
        var value : Bool = before;
        if (ImGui.checkbox(label, value)) set(component, field, before, value);
    }
  }

  function acceptAsset(component : Component, field : FieldInfo, before : Dynamic) {
    if (!ImGui.beginDragDropTarget()) return;
    if (ImGui.acceptDragDropPayload(AssetBrowser.PAYLOAD) != null) set(component, field, before, editor.assetDrag);
    ImGui.endDragDropTarget();
  }

  function drawEntityField(component : Component, field : FieldInfo, label : String, before : String) {
    var scene = editor.scene;
    var current = before == "" ? null : scene.find(before);
    var preview = before == "" ? "(yok)" : current == null ? "(bulunamadı)" : current.name;
    if (!ImGui.beginCombo(label, preview)) return;
    // hlimgui sabit değeri Ref sürümüne bağlar ve yerel kodda çöker: değer değişkenle verilir.
    var empty = before == "";
    if (ImGui.selectable("(yok)", empty)) set(component, field, before, "");
    for (entity in scene.entities) {
      var chosen = entity == current;
      if (ImGui.selectable(entity.name + "##" + entity.id, chosen)) set(component, field, before, entity.id);
    }
    ImGui.endCombo();
  }

  function set(component : Component, field : FieldInfo, before : Dynamic, value : Dynamic) {
    editor.commands.execute(new SetFieldCommand(component, field.name, before, value, field.label));
  }

  // Sürükleme boyunca değer canlı uygulanır, undo'ya tek adım olarak bırakınca girer.
  function trackEdit(component : Component, field : FieldInfo, before : Dynamic, value : Dynamic, edited : Bool) {
    if (ImGui.isItemActivated()) editStart = before;
    if (edited) {
      component.writeField(field.name, value);
      component.refresh();
    }
    if (ImGui.isItemDeactivatedAfterEdit()) set(component, field, editStart, value);
  }
}
