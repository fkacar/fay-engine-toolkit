package scene.editor;

import h3d.mat.Texture;
import hxd.Key;
import imgui.ImGui;
import imgui.types.ImFontAtlas.ImFontTexData;
import scene.FocusGuard;
import scene.HiDpi;
import scene.PlayOptions;
import scene.editor.panels.AssetBrowser;
import scene.editor.panels.HierarchyPanel;
import scene.editor.panels.InspectorPanel;
import sys.FileSystem;

typedef Panel = {
  var title : String;
  var draw : Void->Void;
}

// Unity düzenindeki editör kabuğu. Oyuna özel paneller addPanel, kurallar validator.rules,
// zemin ve asset türleri actions üzerinden eklenir.
class Editor {
  static inline var LAYOUT_FILE = "imgui.ini";
  // Düzen değişince artırılır: eski ölçülerle kaydedilmiş panel düzeni bir kez yenilenir.
  static inline var LAYOUT_VERSION = 2;
  static inline var FONT_PATH = "libs/scene-toolkit/editor/fonts/DejaVuSansMono.ttf";
  static inline var FONT_SIZE = 15;
  static inline var HIERARCHY = "Hierarchy";
  static inline var INSPECTOR = "Inspector";
  static inline var ASSETS = "Asset Browser";
  static inline var WARNINGS = "Uyarılar";
  static inline var DIRTY_POPUP = "Kaydedilmemiş değişiklik";
  static inline var SAVE_AS_POPUP = "Farklı kaydet";
  static inline var RECOVERY_POPUP = "Otomatik yedek";
  static inline var DOCK_SPACE_NODE = 1 << 10;
  static inline var NOTICE_SECONDS = 2.5;
  static inline var NOTICE_MARGIN = 12;

  // Çiftler halinde karakter aralıkları: Latin-1 ve Türkçe harfler, sonda 0.
  static var GLYPH_RANGES = [0x20, 0xFF, 0x11E, 0x11F, 0x130, 0x131, 0x15E, 0x15F, 0];

  static var SUCCESS_COLOR : ImVec4 = {x: 0.55, y: 0.85, z: 0.55, w: 1};
  static var WARNING_COLOR : ImVec4 = {x: 0.95, y: 0.75, z: 0.35, w: 1};
  static var ERROR_COLOR : ImVec4 = {x: 1, y: 0.45, z: 0.4, w: 1};

  public var scene(default, null) : SceneInstance;
  public var commands(default, null) = new CommandStack();
  public var selection(default, null) = new Selection();
  public var groups(default, null) = new LockGroups();
  public var validator(default, null) : Validator;
  public var document(default, null) : SceneDocument;
  public var actions(default, null) : SceneActions;
  public var viewport(default, null) : Viewport;
  public var hierarchy(default, null) : HierarchyPanel;
  public var importer(default, null) = new AssetImporter();
  public var previews(default, null) = new ModelPreview();
  public var trace(default, null) = new InputTrace();
  public var interfaceScale(default, null) = 1.;
  public var commandName(default, null) = Sys.systemName() == "Mac" ? "Cmd" : "Ctrl";
  public var centerX(default, null) = 0.;
  public var centerY(default, null) = 0.;
  // Asset Browser'dan sürüklenen dosya, `res` köküne göre.
  public var assetDrag : Null<String>;

  var inspector : InspectorPanel;
  var assets : AssetBrowser;
  var session = new PlaySession();
  var panels : Array<Panel> = [];
  var messages : Array<String> = [];
  var notice = "";
  var noticeIsError = false;
  var noticeTime = 0.;
  var layoutPending : Bool;
  var showAssets = false;
  var glyphRanges : hl.NativeArray<hl.UI16>;
  var fontTexture : Texture;
  var pendingAction : Null<Void->Void>;
  var openDirtyPopup = false;
  var openSaveAsPopup = false;
  var saveAsName = "";

  public function new(scene : SceneInstance, path : String) {
    this.scene = scene;
    layoutPending = !FileSystem.exists(LAYOUT_FILE);

    var io = ImGui.getIO();
    io.ConfigFlags |= ImGuiConfigFlags.DockingEnable;
    scaleInterface();
    var window = hxd.Window.getInstance();
    window.addResizeEvent(() -> if (HiDpi.density != interfaceScale) scaleInterface());
    window.onClose = onWindowClose;
    FocusGuard.install();
    window.addEventTarget(e -> if (e.kind == EFocusLost) trace.record("odak kaybi"));

    selection.expand = entities -> groups.expand(entities, scene);
    validator = new Validator(assetExists);
    document = new SceneDocument(this, scene, path);
    if (document.prefs.layoutVersion != LAYOUT_VERSION) layoutPending = true;
    actions = new SceneActions(this);
    viewport = new Viewport(this, scene.root.getScene().camera);
    hierarchy = new HierarchyPanel(this);
    inspector = new InspectorPanel(this);
    assets = new AssetBrowser(this);
    document.validate();

    addPanel(HIERARCHY, hierarchy.draw);
    addPanel(INSPECTOR, inspector.draw);
    addPanel(ASSETS, assets.draw);
    addPanel(WARNINGS, drawWarnings);
  }

  public function addPanel(title : String, draw : Void->Void) {
    panels.push({title: title, draw: draw});
  }

  public function draw() {
    var dt = hxd.Timer.dt;
    selection.purge(scene);
    document.update(dt);
    var failure = session.poll();
    if (failure != null) report(failure);

    readShortcuts();
    drawMenu();
    drawDockSpace();
    for (panel in panels) {
      if (ImGui.begin(panel.title)) panel.draw();
      ImGui.end();
    }
    if (showAssets) ImGui.setWindowFocus(ASSETS);
    showAssets = false;
    viewport.update(dt);
    drawNotice();
    drawPopups();
  }

  // Asset önizlemeleri ekrana değil dokuya çizilir, bu yüzden kare çizilirken çağrılır.
  public function render(engine : h3d.Engine) {
    previews.render(engine);
  }

  public function show(message : String, isError = false) {
    notice = message;
    noticeIsError = isError;
    noticeTime = NOTICE_SECONDS;
  }

  // Kalıcı sorunlar: içe aktarma ve oyun hataları Uyarılar panelinde kalır.
  public function report(message : String) {
    if (messages.indexOf(message) < 0) messages.push(message);
  }

  public function isCommandHeld() {
    return Key.isDown(Key.CTRL) || Key.isDown(Key.LEFT_WINDOW_KEY) || Key.isDown(Key.RIGHT_WINDOW_KEY);
  }

  // Tek nesne her zaman düzenlenir, birden çoğu için kilit gerekir.
  public function canEdit() {
    return selection.items.length < 2 || groups.isLocked(selection.items);
  }

  public function toggleLock() {
    var items = selection.items;
    if (items.length < 2) {
      show("Kilitlemek için birden çok nesne seç");
      return;
    }
    var locked = groups.isLocked(items);
    if (locked) groups.unlock(items);
    else groups.lock(items);
    document.rememberFlags();
    show(locked ? "Kilit açıldı" : '${items.length} nesne kilitlendi');
  }

  public function requestOpen(path : String) {
    guard(() -> document.open(path));
  }

  // Kaydedilmemiş iş kaybolacaksa önce sorulur.
  function guard(action : Void->Void) {
    if (!commands.isDirty) {
      action();
      return;
    }
    pendingAction = action;
    openDirtyPopup = true;
  }

  function onWindowClose() {
    if (!commands.isDirty) return true;
    guard(() -> hxd.System.exit());
    return false;
  }

  function assetExists(path : String) {
    AssetImporter.forgetMissingFiles();
    return hxd.Res.loader.exists(path);
  }

  function play() {
    if (session.isRunning) {
      show("Oyun zaten açık");
      return;
    }
    if ((commands.isDirty || !FileSystem.exists(document.path)) && !document.save()) return;
    var view = scene.root.getScene().camera;
    session.start(new PlayOptions(document.resourcePath(), [view.pos.x, view.pos.y, view.pos.z, view.target.x, view.target.y, view.target.z]));
    show("Oyun açılıyor");
  }

  function readShortcuts() {
    var io = ImGui.getIO();
    if (isCommandHeld()) {
      if (Key.isPressed(Key.S)) document.save();
      // Metin yazılırken Cmd+Z o alana aittir; açık alan geri alınan değeri de ezerdi.
      if (io.WantTextInput) return;
      if (Key.isPressed(Key.Z)) Key.isDown(Key.SHIFT) ? redo() : undo();
      if (Key.isPressed(Key.Y)) redo();
      if (Key.isPressed(Key.C)) actions.copy();
      if (Key.isPressed(Key.V)) actions.paste();
      if (Key.isPressed(Key.D)) actions.duplicate();
      return;
    }
    if (io.WantCaptureKeyboard) return;
    if (Key.isPressed(Key.F5)) play();
    if (Key.isPressed(Key.F2)) hierarchy.rename(selection.primary);
    if (Key.isPressed(Key.F)) actions.focus();
    if (Key.isPressed(Key.END)) actions.snapToGround();
    if (Key.isPressed(Key.L)) toggleLock();
    if (Key.isPressed(Key.ESCAPE)) selection.clear();
    if (Key.isPressed(Key.DELETE) || Key.isPressed(Key.BACKSPACE)) actions.remove();
    if (Key.isPressed(Key.NUMBER_1)) viewport.gizmo.tool = Move;
    if (Key.isPressed(Key.NUMBER_2)) viewport.gizmo.tool = Rotate;
    if (Key.isPressed(Key.NUMBER_3)) viewport.gizmo.tool = Scale;
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
    drawFileMenu();
    if (ImGui.beginMenu("Düzen")) {
      if (ImGui.menuItem("Geri al", commandName + "+Z", false, commands.canUndo)) undo();
      if (ImGui.menuItem("Yinele", commandName + "+Y", false, commands.canRedo)) redo();
      ImGui.separator();
      if (ImGui.menuItem("Kopyala", commandName + "+C")) actions.copy();
      if (ImGui.menuItem("Yapıştır", commandName + "+V")) actions.paste();
      if (ImGui.menuItem("Çoğalt", commandName + "+D")) actions.duplicate();
      if (ImGui.menuItem("Sil", "Del")) actions.remove();
      ImGui.separator();
      if (ImGui.menuItem("Boş nesne ekle")) actions.createEmpty();
      if (ImGui.menuItem("Zemine yapıştır", "End")) actions.snapToGround();
      if (ImGui.menuItem("Seçilene odaklan", "F")) actions.focus();
      ImGui.endMenu();
    }
    if (ImGui.beginMenu("Görünüm")) {
      if (ImGui.menuItem("Editörde gizlenenleri göster")) document.showAll();
      if (ImGui.menuItem("Panel düzenini sıfırla")) layoutPending = true;
      ImGui.endMenu();
    }
    if (ImGui.beginMenu("Oyun")) {
      if (ImGui.menuItem("Buradan oyna", "F5", false, !session.isRunning)) play();
      ImGui.endMenu();
    }
    if (ImGui.beginMenu("Yardım")) {
      if (ImGui.menuItem("Girdi kaydını dosyaya yaz")) show('Yazıldı: ${trace.write()}');
      ImGui.endMenu();
    }
    ImGui.textDisabled(document.path);
    if (commands.isDirty) ImGui.textColored(WARNING_COLOR, "Kaydedilmemiş değişiklik var");
    else if (document.lastSaved != "") ImGui.textDisabled('Son kayıt: ${document.lastSaved}');
    var warnings = document.warningCount() + messages.length;
    if (warnings > 0) ImGui.textColored(WARNING_COLOR, 'Uyarı: $warnings');
    if (session.isRunning) ImGui.textColored(SUCCESS_COLOR, "Oyun açık");
    ImGui.endMainMenuBar();
  }

  function drawFileMenu() {
    if (!ImGui.beginMenu("Dosya")) return;
    if (ImGui.menuItem("Yeni sahne")) guard(document.newScene);
    if (ImGui.beginMenu("Aç")) {
      for (path in document.sceneFiles()) if (ImGui.menuItem(path)) requestOpen(path);
      ImGui.endMenu();
    }
    if (ImGui.beginMenu("Son açılanlar", document.prefs.recent.length > 0)) {
      for (path in document.prefs.recent.copy()) if (ImGui.menuItem(path)) requestOpen(path);
      ImGui.endMenu();
    }
    ImGui.separator();
    if (ImGui.menuItem("Kaydet", commandName + "+S")) document.save();
    if (ImGui.menuItem("Farklı kaydet")) {
      saveAsName = "";
      openSaveAsPopup = true;
    }
    if (ImGui.menuItem("Diskten yeniden aç")) guard(document.reopen);
    ImGui.endMenu();
  }

  // Ekranın üstünde kısa süre görünür, odağı ve tıklamaları almaz.
  function drawNotice() {
    if (noticeTime <= 0) return;
    noticeTime -= hxd.Timer.dt;
    var window = hxd.Window.getInstance();
    ImGui.setNextWindowPos({x: window.width * 0.5, y: viewport.toolbarBottom + NOTICE_MARGIN * interfaceScale}, 0, {x: 0.5, y: 0});
    var flags = ImGuiWindowFlags.NoDecoration | ImGuiWindowFlags.AlwaysAutoResize | ImGuiWindowFlags.NoInputs
      | ImGuiWindowFlags.NoSavedSettings | ImGuiWindowFlags.NoFocusOnAppearing | ImGuiWindowFlags.NoDocking;
    if (ImGui.begin("##notice", null, flags)) ImGui.textColored(noticeIsError ? ERROR_COLOR : SUCCESS_COLOR, notice);
    ImGui.end();
  }

  function drawPopups() {
    if (openDirtyPopup) ImGui.openPopup(DIRTY_POPUP);
    if (openSaveAsPopup) ImGui.openPopup(SAVE_AS_POPUP);
    if (document.hasRecovery && !ImGui.isPopupOpen(RECOVERY_POPUP)) ImGui.openPopup(RECOVERY_POPUP);
    openDirtyPopup = false;
    openSaveAsPopup = false;
    var flags = ImGuiWindowFlags.AlwaysAutoResize;

    if (ImGui.beginPopupModal(DIRTY_POPUP, null, flags)) {
      ImGui.text('${document.path} kaydedilmedi.');
      if (ImGui.button("Kaydet ve devam et")) finishGuard(document.save());
      ImGui.sameLine();
      if (ImGui.button("Kaydetmeden devam et")) {
        document.removeAutosave();
        finishGuard(true);
      }
      ImGui.sameLine();
      if (ImGui.button("Vazgeç")) finishGuard(false);
      ImGui.endPopup();
    }

    if (ImGui.beginPopupModal(SAVE_AS_POPUP, null, flags)) {
      if (ImGui.isWindowAppearing()) ImGui.setKeyboardFocusHere();
      var name = saveAsName;
      if (ImGui.inputText("Sahne adı", name)) saveAsName = name;
      if (ImGui.button("Kaydet") && document.saveAs(saveAsName)) ImGui.closeCurrentPopup();
      ImGui.sameLine();
      if (ImGui.button("Vazgeç")) ImGui.closeCurrentPopup();
      ImGui.endPopup();
    }

    if (ImGui.beginPopupModal(RECOVERY_POPUP, null, flags)) {
      ImGui.text('${document.path} için kaydedilmemiş bir otomatik yedek bulundu.');
      if (ImGui.button("Yedeği aç")) {
        document.recover();
        ImGui.closeCurrentPopup();
      }
      ImGui.sameLine();
      if (ImGui.button("Yedeği sil")) {
        document.discardRecovery();
        ImGui.closeCurrentPopup();
      }
      ImGui.endPopup();
    }
  }

  function finishGuard(proceed : Bool) {
    var action = pendingAction;
    pendingAction = null;
    ImGui.closeCurrentPopup();
    if (proceed && action != null) action();
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
      showAssets = true;
      buildDefaultLayout(dock, width, height);
      document.prefs.setLayoutVersion(LAYOUT_VERSION);
    }
    ImGui.dockSpace(dock, null, ImGuiDockNodeFlags.PassthruCentralNode);
    var center = ImGui.dockBuilderGetCentralNode(dock);
    if (center != null) {
      centerX = center.Pos.x;
      centerY = center.Pos.y;
    }
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
    ImGui.dockBuilderDockWindow(WARNINGS, bottom);
    ImGui.dockBuilderDockWindow(ASSETS, bottom);
    ImGui.dockBuilderFinish(dock);
  }

  function drawWarnings() {
    if (document.warningCount() == 0 && messages.length == 0) ImGui.textDisabled("Uyarı yok");
    for (i in 0...document.issues.length) {
      var issue = document.issues[i];
      if (!ImGui.selectable(issue.message + "##" + i) || !scene.contains(issue.entity)) continue;
      selection.set([issue.entity]);
      hierarchy.reveal(issue.entity);
    }
    for (warning in scene.warnings) ImGui.textWrapped(warning);
    for (message in messages) ImGui.textWrapped(message);
    if (messages.length > 0 && ImGui.smallButton("Temizle")) messages = [];
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
}
