package scene.editor;

import h3d.mat.Texture;
import hxd.Key;
import imgui.ImGui;
import imgui.types.ImFontAtlas.ImFontTexData;
import scene.FieldInfo;
import scene.HiDpi;
import scene.data.SceneData;
import scene.data.SceneFormat;
import scene.editor.commands.SetFieldCommand;
import scene.editor.commands.SetNameCommand;
import scene.editor.commands.SetTransformCommand;
import scene.editor.commands.SetTransformCommand.Transform;
import sys.FileSystem;
import sys.io.File;

typedef Panel = {
  var title : String;
  var draw : Void->Void;
}

// Unity düzenindeki editör kabuğu. Oyuna özel paneller addPanel ile eklenir.
class Editor {
  static inline var LAYOUT_FILE = "imgui.ini";
  static inline var NEW_SCENE_PATH = "res/scenes/yeni.scene.json";
  static inline var FONT_PATH = "libs/scene-toolkit/editor/fonts/DejaVuSansMono.ttf";
  static inline var FONT_SIZE = 15;
  static inline var HIERARCHY = "Hierarchy";
  static inline var INSPECTOR = "Inspector";
  static inline var ASSETS = "Asset Browser";
  static inline var WARNINGS = "Uyarılar";
  static inline var DOCK_SPACE_NODE = 1 << 10;
  static inline var NOTICE_SECONDS = 2.5;
  static inline var NOTICE_MARGIN = 12;

  // Çiftler halinde karakter aralıkları: Latin-1 ve Türkçe harfler, sonda 0.
  static var GLYPH_RANGES = [0x20, 0xFF, 0x11E, 0x11F, 0x130, 0x131, 0x15E, 0x15F, 0];

  static var SUCCESS_COLOR : ImVec4 = {x: 0.55, y: 0.85, z: 0.55, w: 1};
  static var WARNING_COLOR : ImVec4 = {x: 0.95, y: 0.75, z: 0.35, w: 1};
  static var ERROR_COLOR : ImVec4 = {x: 1, y: 0.45, z: 0.4, w: 1};

  public var commands(default, null) = new CommandStack();
  // Doluyken oyun tuşları (kamera gibi) dinlenmemeli: metin yazılıyor veya kısayol basılıyor.
  public var wantsKeyboard(get, never) : Bool;

  var scene : SceneInstance;
  var path : String;
  var selected : Null<Entity>;
  var panels : Array<Panel> = [];
  var lastSaved = "";
  var notice = "";
  var noticeIsError = false;
  var noticeTime = 0.;
  var commandName = Sys.systemName() == "Mac" ? "Cmd" : "Ctrl";
  var layoutPending : Bool;
  var editStart : Dynamic;
  var transformStart : Transform;
  var glyphRanges : hl.NativeArray<hl.UI16>;
  var fontTexture : Texture;
  var interfaceScale = 1.;

  public function new(scene : SceneInstance, path : String) {
    this.scene = scene;
    this.path = path;
    layoutPending = !FileSystem.exists(LAYOUT_FILE);

    var io = ImGui.getIO();
    io.ConfigFlags |= ImGuiConfigFlags.DockingEnable;
    scaleInterface();
    hxd.Window.getInstance().addResizeEvent(() -> if (HiDpi.density != interfaceScale) scaleInterface());

    addPanel(HIERARCHY, drawHierarchy);
    addPanel(INSPECTOR, drawInspector);
    addPanel(ASSETS, () -> ImGui.textDisabled("Faz 1"));
    addPanel(WARNINGS, drawWarnings);
  }

  public function addPanel(title : String, draw : Void->Void) {
    panels.push({title: title, draw: draw});
  }

  public function draw() {
    readShortcuts();
    drawMenu();
    drawDockSpace();
    for (panel in panels) {
      if (ImGui.begin(panel.title)) panel.draw();
      ImGui.end();
    }
    drawNotice();
  }

  public function save() {
    try {
      File.saveContent(path, SceneFormat.write(scene.toData()));
    } catch (e : Dynamic) {
      show('Kaydedilemedi: $e', true);
      return;
    }
    commands.markSaved();
    lastSaved = DateTools.format(Date.now(), "%H:%M:%S");
    show('Kaydedildi: $path');
  }

  public function reopen() {
    try {
      scene.load(SceneFormat.read(File.getContent(path)));
    } catch (e : Dynamic) {
      show('Açılamadı: $e', true);
      return;
    }
    afterLoad("Açıldı: " + path);
  }

  public function newScene() {
    scene.load(new SceneData(SceneFormat.VERSION));
    path = NEW_SCENE_PATH;
    afterLoad("Yeni sahne: " + path);
  }

  function afterLoad(message : String) {
    selected = null;
    commands.clear();
    lastSaved = "";
    show(message);
  }

  function show(message : String, isError = false) {
    notice = message;
    noticeIsError = isError;
    noticeTime = NOTICE_SECONDS;
  }

  function isCommandHeld() {
    return Key.isDown(Key.CTRL) || Key.isDown(Key.LEFT_WINDOW_KEY) || Key.isDown(Key.RIGHT_WINDOW_KEY);
  }

  function readShortcuts() {
    if (!isCommandHeld()) return;
    if (Key.isPressed(Key.S)) save();
    // Metin yazılırken Cmd+Z o alana aittir; açık alan geri alınan değeri de ezerdi.
    if (ImGui.getIO().WantTextInput) return;
    if (Key.isPressed(Key.Z)) Key.isDown(Key.SHIFT) ? redo() : undo();
    if (Key.isPressed(Key.Y)) redo();
  }

  function undo() {
    if (!commands.canUndo) {
      show("Geri alınacak değişiklik yok");
      return;
    }
    var label = commands.nextUndoLabel;
    commands.undo();
    show('Geri alındı: $label (${commands.undoCount} adım kaldı)');
  }

  function redo() {
    if (!commands.canRedo) {
      show("Yinelenecek değişiklik yok");
      return;
    }
    var label = commands.nextRedoLabel;
    commands.redo();
    show('Yinelendi: $label (${commands.redoCount} adım kaldı)');
  }

  function drawMenu() {
    if (!ImGui.beginMainMenuBar()) return;
    if (ImGui.beginMenu("Dosya")) {
      if (ImGui.menuItem("Yeni sahne")) newScene();
      if (ImGui.menuItem("Kaydet", commandName + "+S")) save();
      if (ImGui.menuItem("Diskten yeniden aç")) reopen();
      ImGui.endMenu();
    }
    if (ImGui.beginMenu("Düzen")) {
      if (ImGui.menuItem("Geri al", commandName + "+Z", false, commands.canUndo)) undo();
      if (ImGui.menuItem("Yinele", commandName + "+Y", false, commands.canRedo)) redo();
      ImGui.endMenu();
    }
    ImGui.textDisabled(path);
    if (commands.isDirty) ImGui.textColored(WARNING_COLOR, "Kaydedilmemiş değişiklik var");
    else if (lastSaved != "") ImGui.textDisabled('Son kayıt: $lastSaved');
    if (scene.warnings.length > 0) ImGui.textColored(WARNING_COLOR, 'Uyarı: ${scene.warnings.length}');
    ImGui.endMainMenuBar();
  }

  // Ekranın üstünde kısa süre görünür, odağı ve tıklamaları almaz.
  function drawNotice() {
    if (noticeTime <= 0) return;
    noticeTime -= hxd.Timer.dt;
    var window = hxd.Window.getInstance();
    ImGui.setNextWindowPos({x: window.width * 0.5, y: ImGui.getFrameHeight() + NOTICE_MARGIN * interfaceScale}, 0, {x: 0.5, y: 0});
    var flags = ImGuiWindowFlags.NoDecoration | ImGuiWindowFlags.AlwaysAutoResize | ImGuiWindowFlags.NoInputs
      | ImGuiWindowFlags.NoSavedSettings | ImGuiWindowFlags.NoFocusOnAppearing | ImGuiWindowFlags.NoDocking;
    if (ImGui.begin("##notice", null, flags)) ImGui.textColored(noticeIsError ? ERROR_COLOR : SUCCESS_COLOR, notice);
    ImGui.end();
  }

  function drawDockSpace() {
    var window = hxd.Window.getInstance();
    var top = ImGui.getFrameHeight();
    var width = window.width, height = window.height - top;
    ImGui.setNextWindowPos({x: 0, y: top});
    ImGui.setNextWindowSize({x: width, y: height});
    var flags = ImGuiWindowFlags.NoTitleBar | ImGuiWindowFlags.NoResize | ImGuiWindowFlags.NoMove
      | ImGuiWindowFlags.NoCollapse | ImGuiWindowFlags.NoBringToFrontOnFocus | ImGuiWindowFlags.NoNavFocus
      | ImGuiWindowFlags.NoDocking | ImGuiWindowFlags.NoBackground;
    ImGui.begin("##dock-host", null, flags);
    var dock = ImGui.getID("main-dock");
    if (layoutPending) {
      layoutPending = false;
      buildDefaultLayout(dock, width, height);
    }
    ImGui.dockSpace(dock, null, ImGuiDockNodeFlags.PassthruCentralNode);
    ImGui.end();
  }

  function buildDefaultLayout(dock : ImGuiID, width : Float, height : Float) {
    ImGui.dockBuilderRemoveNode(dock);
    ImGui.dockBuilderAddNode(dock, DOCK_SPACE_NODE);
    ImGui.dockBuilderSetNodeSize(dock, {x: width, y: height});
    var center = dock, left = 0, right = 0, bottom = 0;
    ImGui.dockBuilderSplitNode(center, ImGuiDir.Left, 0.2, left, center);
    ImGui.dockBuilderSplitNode(center, ImGuiDir.Right, 0.28, right, center);
    ImGui.dockBuilderSplitNode(center, ImGuiDir.Down, 0.25, bottom, center);
    ImGui.dockBuilderDockWindow(HIERARCHY, left);
    ImGui.dockBuilderDockWindow(INSPECTOR, right);
    ImGui.dockBuilderDockWindow(ASSETS, bottom);
    ImGui.dockBuilderDockWindow(WARNINGS, bottom);
    ImGui.dockBuilderFinish(dock);
  }

  function drawWarnings() {
    if (scene.warnings.length == 0) ImGui.textDisabled("Uyarı yok");
    for (warning in scene.warnings) ImGui.text(warning);
  }

  function drawHierarchy() {
    for (entity in scene.entities) if (entity.parent == null) drawEntity(entity);
  }

  function drawEntity(entity : Entity) {
    var flags = ImGuiTreeNodeFlags.OpenOnArrow | ImGuiTreeNodeFlags.SpanAvailWidth;
    if (entity == selected) flags |= ImGuiTreeNodeFlags.Selected;
    if (entity.children.length == 0) flags |= ImGuiTreeNodeFlags.Leaf;
    var open = ImGui.treeNodeEx(entity.id, flags, entity.name);
    if (ImGui.isItemClicked()) selected = entity;
    if (!open) return;
    for (child in entity.children) drawEntity(child);
    ImGui.treePop();
  }

  function drawInspector() {
    if (selected == null) {
      ImGui.textDisabled("Bir nesne seç");
      return;
    }
    var entity = selected;
    drawName(entity);
    if (ImGui.collapsingHeader("Dönüşüm", ImGuiTreeNodeFlags.DefaultOpen)) drawTransform(entity);
    for (component in entity.components) {
      var name = component.componentId();
      if (!ImGui.collapsingHeader(name, ImGuiTreeNodeFlags.DefaultOpen)) continue;
      ImGui.pushID(name);
      for (field in component.describeFields()) drawField(component, field);
      ImGui.popID();
    }
  }

  function drawName(entity : Entity) {
    var name = entity.name;
    var edited = ImGui.inputText("Ad", name);
    if (ImGui.isItemActivated()) editStart = entity.name;
    if (edited) entity.name = name;
    if (ImGui.isItemDeactivatedAfterEdit()) commands.execute(new SetNameCommand(entity, editStart, name));
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
      commands.execute(new SetTransformCommand(entity, transformStart, SetTransformCommand.capture(entity)));
  }

  function drawField(component : Component, field : FieldInfo) {
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
      case KString:
        var value : String = before;
        var edited = ImGui.inputText(label, value);
        trackEdit(component, field, before, value, edited);
      case KBool:
        var value : Bool = before;
        if (ImGui.checkbox(label, value))
          commands.execute(new SetFieldCommand(component, field.name, before, value, field.label));
    }
  }

  // Sürükleme boyunca değer canlı uygulanır, undo'ya tek adım olarak bırakınca girer.
  function trackEdit(component : Component, field : FieldInfo, before : Dynamic, value : Dynamic, edited : Bool) {
    if (ImGui.isItemActivated()) editStart = before;
    if (edited) {
      component.writeField(field.name, value);
      component.refresh();
    }
    if (ImGui.isItemDeactivatedAfterEdit())
      commands.execute(new SetFieldCommand(component, field.name, editStart, value, field.label));
  }

  // ImGui kırpmayı ham pikselle yapar, bu yüzden 2D sahneler gibi yakınlaştırılamaz: font ve boşluklar büyür.
  function scaleInterface() {
    ImGui.getStyle().scaleAllSizes(HiDpi.density / interfaceScale);
    interfaceScale = HiDpi.density;
    loadFont();
  }

  function loadFont() {
    glyphRanges = new hl.NativeArray(GLYPH_RANGES.length);
    for (i in 0...GLYPH_RANGES.length) glyphRanges[i] = GLYPH_RANGES[i];

    var fonts = ImGui.getIO().Fonts;
    fonts.clear();
    fonts.addFontFromFileTTF(FONT_PATH, FONT_SIZE * interfaceScale, null, glyphRanges);
    var data = new ImFontTexData();
    fonts.getTexDataAsRGBA32(data);
    var bytes = data.buffer.toBytes(data.width * data.height * 4);
    if (fontTexture != null) fontTexture.dispose();
    fontTexture = Texture.fromPixels(new hxd.Pixels(data.width, data.height, bytes, hxd.PixelFormat.RGBA));
    fonts.setTexId(fontTexture);
    fonts.clearTexData();
  }

  function get_wantsKeyboard() {
    return ImGui.getIO().WantCaptureKeyboard || isCommandHeld();
  }
}
