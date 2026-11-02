package scene.editor;

import h3d.mat.Texture;
import hxd.Key;
import imgui.ImGui;
import imgui.types.ImFontAtlas.ImFontTexData;
import scene.FocusGuard;
import scene.HiDpi;
import scene.Marker;
import scene.Entity;
import scene.PlayFiles;
import scene.data.ThreeWay;
import scene.editor.agent.AgentServer;
import scene.editor.agent.ContextTools;
import scene.editor.agent.PlayTools;
import scene.editor.agent.EditTools;
import scene.editor.agent.ExamTools;
import scene.nav.NavWorld;
import scene.story.Dialog;
import scene.world.WorldData;
import scene.world.WorldState;
import scene.PlayOptions;
import scene.editor.panels.AssetBrowser;
import scene.editor.panels.HierarchyPanel;
import scene.editor.panels.InspectorPanel;
import scene.editor.panels.DataPanel;
import scene.editor.panels.DialogPanel;
import scene.editor.panels.WorldPanel;
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
  static inline var LAYOUT_VERSION = 5;
  static inline var FONT_PATH = "libs/scene-toolkit/editor/fonts/DejaVuSansMono.ttf";
  static inline var FONT_SIZE = 15;
  static inline var HIERARCHY = "Hierarchy";
  static inline var INSPECTOR = "Inspector";
  static inline var ASSETS = "Asset Browser";
  static inline var WARNINGS = "Uyarılar";
  static inline var WORLD = "Dünya";
  static inline var DATA = "Veri";
  static inline var DIALOGS = "Diyaloglar";
  static inline var AGENT = "Ajan";
  static inline var DIRTY_POPUP = "Kaydedilmemiş değişiklik";
  static inline var SAVE_AS_POPUP = "Farklı kaydet";
  static inline var RECOVERY_POPUP = "Otomatik yedek";
  static inline var PREFAB_POPUP = "Prefab yap";
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
  public var diskGuard(default, null) = new DiskGuard();
  public var data(default, null) = new DataStore();
  public var dialogs(default, null) = new DialogStore();
  public var previews(default, null) = new ModelPreview();
  public var trace(default, null) = new InputTrace();
  public var interfaceScale(default, null) = 1.;
  public var commandName(default, null) = Sys.systemName() == "Mac" ? "Cmd" : "Ctrl";
  public var centerX(default, null) = 0.;
  public var centerY(default, null) = 0.;
  public var dialogWorkspace(default, null) : DialogWorkspace;
  // Dış ajanların (Claude Code gibi) bağlandığı MCP sunucusu. Editör açılınca kendiliğinden başlar.
  public var agent(default, null) : AgentServer;
  var captureWaiters : Array<hxd.Pixels->Void> = [];
  var labelFrames = 0;
  var centerWidth = 0.;
  var centerHeight = 0.;
  // Asset Browser'dan sürüklenen dosya, `res` köküne göre.
  public var assetDrag : Null<String>;

  var inspector : InspectorPanel;
  var assets : AssetBrowser;
  var worldPanel : WorldPanel;
  var dataPanel : DataPanel;
  var dialogPanel : DialogPanel;
  var keyboardPanelFocused = false;
  var session = new PlaySession();
  // Tasarımcının menüden başlattığı görev testi: sonucu gelince Uyarılar paneline yazılır.
  var designerTest : Null<String>;
  // Claude Code hook'u okur: editör açık mı, hangi dosyalar kaydedilmemiş. Eskiyse editör kapalı sayılır.
  static inline var STATUS_FILE = ".editor/ajan-durum.json";
  static inline var STATUS_SECONDS = 2.;
  var statusTimer = STATUS_SECONDS;
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
  var openPrefabPopup = false;
  var prefabName = "";

  // Dünya verilirse `path` dünya dosyasını gösterir ve editör onunla açılır.
  public function new(scene : SceneInstance, path : String, ?world : WorldState) {
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
    validator.refExists = data.exists;
    validator.dialogExists = dialogs.exists;
    validator.rules.push(_ -> dialogIssues());
    validator.rules.push(_ -> storyIssues());
    if (world != null) scene.provide(NavWorld, new NavWorld(world));
    document = new SceneDocument(this, scene, path, world);
    validator.rules.push(_ -> document.prefabRootIssues());
    validator.isPartial = () -> document.world != null && !document.world.isComplete();
    if (document.prefs.layoutVersion != LAYOUT_VERSION) layoutPending = true;
    actions = new SceneActions(this);
    viewport = new Viewport(this, scene.root.getScene().camera);
    hierarchy = new HierarchyPanel(this);
    inspector = new InspectorPanel(this);
    assets = new AssetBrowser(this);
    worldPanel = new WorldPanel(this);
    dataPanel = new DataPanel(this);
    data.attach(this);
    dialogs.attach(this);
    dialogWorkspace = new DialogWorkspace(this);
    dialogPanel = new DialogPanel(this);
    if (WorldData.isWorldFile(path)) document.open(path);
    document.validate();
    for (type in document.prefs.hiddenMarkers) Marker.hiddenTypes.set(type, true);

    addPanel(HIERARCHY, hierarchy.draw);
    addPanel(INSPECTOR, inspector.draw);
    addPanel(ASSETS, assets.draw);
    addPanel(WARNINGS, drawWarnings);
    addPanel(WORLD, worldPanel.draw);
    addPanel(DATA, dataPanel.draw);
    addPanel(DIALOGS, dialogPanel.draw);

    agent = new AgentServer(AgentServer.PORT, ContextTools.INSTRUCTIONS);
    var agentPanel = new scene.editor.panels.AgentPanel(this);
    addPanel(AGENT, agentPanel.draw);
    new ContextTools(this, agent);
    new PlayTools(this, agent);
    new EditTools(this, agent);
    new ExamTools(this, agent);
    ContextTools.prompts(agent);
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

    agent.update(dt);
    pollDesignerTest();
    writeStatus(dt);
    readShortcuts();
    keyboardPanelFocused = false;
    drawMenu();
    drawDockSpace();
    for (panel in panels) {
      if (ImGui.begin(panel.title)) panel.draw();
      ImGui.end();
    }
    dialogWorkspace.draw();
    drawLabels();
    if (showAssets) {
      ImGui.setWindowFocus(ASSETS);
      ImGui.setWindowFocus(INSPECTOR);
    }
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

  public function askPrefabName() {
    var entity = selection.primary;
    prefabName = entity == null ? "" : SceneDocument.cleanName(entity.name);
    openPrefabPopup = true;
  }

  public function requestOpen(path : String) {
    guard(() -> document.open(path));
  }

  // Kaydedilmemiş iş kaybolacaksa önce sorulur.
  // Esc önce fırçayı bırakır, sonra seçimi kaldırır.
  function cancelTool() {
    var world = document.world;
    if (world != null && world.brush.isActive) world.brush.tool = null;
    else selection.clear();
  }

  // Kaydedilmemiş iş bu işlemle kaybolacaksa önce sorulur.
  public function guardIf(needed : Bool, action : Void->Void) {
    if (needed) guard(action);
    else action();
  }

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

  function writeStatus(dt : Float) {
    statusTimer += dt;
    if (statusTimer < STATUS_SECONDS) return;
    statusTimer = 0;
    try {
      if (!FileSystem.exists(".editor")) FileSystem.createDirectory(".editor");
      var status = {zaman: Math.floor(Date.now().getTime() / 1000), port: AgentServer.PORT, sunucu: agent.isListening(), kaydedilmemis: document.unsavedFiles()};
      sys.io.File.saveContent(STATUS_FILE, haxe.Json.stringify(status, null, " "));
    } catch (e : Dynamic) {}
  }

  public function isPlaying() {
    return session.isRunning;
  }

  // Görev testi ayrı oyun sürecinde oynar: dünya kayıtlı haliyle açılır, kamera verilmez.
  // Kaydedilmemiş değişiklikler teste girmez; save true ise önce kaydedilir.
  public function startPlayTest(test : Dynamic, save : Bool) : Null<String> {
    if (session.isRunning) return "Oyun zaten açık: kapanmasını bekle";
    if (save && commands.isDirty && !document.save()) return "Kaydedilemedi";
    PlayTests.prepare(test);
    session.start(new PlayOptions(document.resourcePath()));
    return null;
  }

  function runDesignerTest(name : String) {
    var test = PlayTests.load(name);
    if (test == null) {
      show('Görev testi okunamadı: $name', true);
      return;
    }
    var problem = startPlayTest(test, true);
    if (problem != null) show(problem, true);
    else {
      PlayTests.lastName = name;
      designerTest = name;
      show('Görev testi oynuyor: $name');
    }
  }

  function pollDesignerTest() {
    if (designerTest == null) return;
    var result = PlayTests.result();
    if (result == null) {
      if (!session.isRunning) {
        messages.push('Görev testi $designerTest: oyun sonuç yazmadan kapandı');
        designerTest = null;
      }
      return;
    }
    var passed = result.passed == true;
    messages.push('Görev testi $designerTest: ${passed ? "geçti" : "kaldı"}');
    var failures : Array<String> = result.failures == null ? [] : result.failures;
    for (failure in failures) messages.push('  $failure');
    show(passed ? 'Görev testi geçti: $designerTest' : 'Görev testi kaldı: $designerTest. Uyarılar paneline bak', !passed);
    designerTest = null;
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
      if (isPanelFocused() || dialogWorkspace.isOpen) return;
      if (Key.isPressed(Key.C)) actions.copy();
      if (Key.isPressed(Key.V)) actions.paste();
      if (Key.isPressed(Key.D)) actions.duplicate();
      return;
    }
    // Diyalog düzenleyici açıkken sahne kısayolları çalışmaz: Delete sahnedeki seçili nesneyi silmesin.
    if (dialogWorkspace.isOpen) {
      dialogWorkspace.readKeys();
      return;
    }
    if (io.WantCaptureKeyboard) return;
    if (Key.isPressed(Key.F5)) play();
    // Diyalog ve veri panelinde Delete düğümü veya satırı siler, sahnedeki nesneye dokunmaz.
    if (isPanelFocused()) return;
    if (Key.isPressed(Key.F2)) hierarchy.rename(selection.primary);
    if (Key.isPressed(Key.F)) actions.focus();
    if (Key.isPressed(Key.END)) actions.snapToGround();
    if (Key.isPressed(Key.L)) toggleLock();
    if (Key.isPressed(Key.ESCAPE)) cancelTool();
    if (Key.isPressed(Key.DELETE) || Key.isPressed(Key.BACKSPACE)) actions.remove();
    if (Key.isPressed(Key.NUMBER_1)) viewport.gizmo.tool = Move;
    if (Key.isPressed(Key.NUMBER_2)) viewport.gizmo.tool = Rotate;
    if (Key.isPressed(Key.NUMBER_3)) viewport.gizmo.tool = Scale;
  }

  // Yanlış yazılmış olay ve değişken adları oyunda sessizce hiçbir şey yapmaz.
  function storyIssues() : Array<Validator.Issue> {
    return [for (found in StoryIndex.issues(StoryIndex.build(this))) {
      entity: found.entry.entity == null || found.entry.loaded != true ? null : scene.find(found.entry.entity),
      message: found.message,
      dialog: found.entry.dialog,
      node: found.entry.node,
    }];
  }

  // Diyaloglarda boş bırakılan alanlar oyunda sessizce hiçbir şey yapmaz.
  function dialogIssues() : Array<Validator.Issue> {
    var issues : Array<Validator.Issue> = [];
    for (id in dialogs.ids()) {
      var dialog = dialogs.dialogs.get(id);
      for (node in dialog.nodes) {
        var problem = switch (node.type) {
          case Dialog.EVENT if (node.event == null || node.event == ""): "olay adı boş";
          case Dialog.CONDITION if (node.name == null || node.name == ""): "koşulun adı boş";
          case Dialog.CHOICES if (node.choices == null || Lambda.exists(node.choices, choice -> choice.text == "")): "boş seçenek var";
          case Dialog.LINE if (node.text == null || node.text == ""): "satır boş";
          default: null;
        };
        if (problem != null) issues.push({entity: null, message: 'Diyalog ${dialog.title}: $problem', dialog: id, node: node.id});
      }
    }
    return issues;
  }

  // Önceki karenin değeridir; paneller çizilmeden önce sıfırlanır, gizli panel kilitlemez.
  function isPanelFocused() {
    return keyboardPanelFocused;
  }

  // Claude Code'a yapıştırılacak kısa başvuru: ajan nesneyi kimliğiyle bulur.
  public function copyForAgent(entities : Array<Entity>) {
    if (entities.length == 0) return;
    var text = [for (entity in entities) 'yoa-editor nesnesi "${entity.name}" (kimlik ${entity.id})'].join("\n");
    ImGui.setClipboardText(text);
    show(entities.length == 1 ? 'Ajan için kopyalandı: ${entities[0].name}' : 'Ajan için kopyalandı: ${entities.length} nesne');
  }

  // Ajan için ekran görüntüsü: çizim bittikten sonra okunur. İstenirse önce nesne adları yazılır.
  public function requestCapture(labels : Bool, done : hxd.Pixels->Void) {
    captureWaiters.push(done);
    if (labels) labelFrames = 2;
  }

  // Oyunun App'i super.render'dan sonra çağırır: arka tampon panellerle birlikte tamamdır.
  public function afterRender(engine : h3d.Engine) {
    if (captureWaiters.length == 0 || labelFrames > 1) return;
    var pixels = hxd.Pixels.alloc(engine.width, engine.height, RGBA);
    #if hlsdl
    sdl.GL.readPixels(0, 0, engine.width, engine.height, 0x1908, 0x1401, (pixels.bytes : hl.Bytes));
    #end
    for (i in 0...engine.width * engine.height) pixels.bytes.set(i * 4 + 3, 255);
    pixels.flipY();
    var waiters = captureWaiters;
    captureWaiters = [];
    labelFrames = 0;
    for (done in waiters) done(pixels);
  }

  function drawLabels() {
    if (labelFrames == 0) return;
    labelFrames--;
    var list = ImGui.getForegroundDrawList();
    var camera = viewport.view;
    var engine = h3d.Engine.getCurrent();
    var area = centerArea();
    for (entity in scene.entities) {
      var isMarker = Lambda.exists(entity.components, component -> Std.isOfType(component, Marker));
      if (entity.parent != null && !selection.has(entity) && !isMarker || !entity.isShown()) continue;
      var at = entity.object.getAbsPos();
      var forward = camera.target.sub(camera.pos);
      if ((at.tx - camera.pos.x) * forward.x + (at.ty - camera.pos.y) * forward.y + (at.tz - camera.pos.z) * forward.z <= 0) continue;
      var screen = camera.project(at.tx, at.ty, at.tz, engine.width, engine.height);
      if (screen.x < area.x || screen.x > area.x + area.width || screen.y < area.y || screen.y > area.y + area.height) continue;
      var size = ImGui.calcTextSize(entity.name);
      list.addRectFilled({x: screen.x - 2, y: screen.y - 2}, {x: screen.x + size.x + 2, y: screen.y + size.y + 2}, 0xC0000000);
      list.addText({x: screen.x, y: screen.y}, selection.has(entity) ? 0xFF40D0FF : 0xFFFFFFFF, entity.name);
    }
  }

  // Ortadaki sahne alanı: diyalog düzenleyici burayı kaplar.
  public function centerArea() {
    return {x: centerX, y: centerY, width: centerWidth, height: centerHeight};
  }

  public function showInspector() {
    ImGui.setWindowFocus(INSPECTOR);
  }

  public function claimKeyboard() {
    if (ImGui.isWindowFocused(ImGuiFocusedFlags.RootAndChildWindows)) keyboardPanelFocused = true;
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
      if (ImGui.beginMenu("İşaretçi ekle")) {
        for (marker in actions.placeableMarkers()) if (ImGui.menuItem(marker.title())) actions.addMarker(marker.componentId());
        ImGui.endMenu();
      }
      if (ImGui.menuItem("Prefab yap", null, false, selection.items.length == 1)) askPrefabName();
      if (ImGui.menuItem("Zemine yapıştır", "End")) actions.snapToGround();
      if (ImGui.menuItem("Seçilene odaklan", "F")) actions.focus();
      ImGui.endMenu();
    }
    if (ImGui.beginMenu("Görünüm")) {
      if (ImGui.menuItem("Editörde gizlenenleri göster")) document.showAll();
      if (ImGui.menuItem("Panel düzenini sıfırla")) layoutPending = true;
      if (document.world != null) {
        var bounds = document.world.showBounds;
        if (ImGui.menuItem("Hücre sınırları", null, bounds)) document.world.showBounds = !document.world.showBounds;
      }
      if (ImGui.beginMenu("İşaretçiler")) {
        for (marker in actions.placeableMarkers()) drawMarkerFilter(marker.componentId(), marker.title());
        ImGui.endMenu();
      }
      ImGui.endMenu();
    }
    if (ImGui.beginMenu("Oyun")) {
      if (ImGui.menuItem("Buradan oyna", "F5", false, !session.isRunning)) play();
      if (ImGui.beginMenu("Görev testleri")) {
        var tests = PlayTests.list();
        if (tests.length == 0) ImGui.textDisabled('Test yok: ${PlayFiles.TESTS} altına .test.json yaz');
        for (name in tests) if (ImGui.menuItem(name, null, false, !session.isRunning)) runDesignerTest(name);
        ImGui.endMenu();
      }
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

  function drawMarkerFilter(type : String, title : String) {
    var shown = !Marker.hiddenTypes.exists(type);
    if (!ImGui.menuItem(title, null, shown)) return;
    // menuItem verilen değeri kendisi çevirir, durum Map'ten okunur.
    if (Marker.hiddenTypes.exists(type)) Marker.hiddenTypes.remove(type);
    else Marker.hiddenTypes.set(type, true);
    for (entity in scene.entities)
      for (component in entity.components) {
        var marker = Std.downcast(component, Marker);
        if (marker != null) marker.applyFilter();
      }
    document.prefs.setHiddenMarkers([for (hidden in Marker.hiddenTypes.keys()) hidden]);
  }

  function drawFileMenu() {
    if (!ImGui.beginMenu("Dosya")) return;
    if (ImGui.menuItem("Yeni sahne")) guard(document.newScene);
    if (ImGui.beginMenu("Aç")) {
      if (document.canOpenWorld() && ImGui.menuItem("Dünya")) requestOpen(document.worldPath());
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
    if (openPrefabPopup) ImGui.openPopup(PREFAB_POPUP);
    if (document.hasRecovery && !ImGui.isPopupOpen(RECOVERY_POPUP)) ImGui.openPopup(RECOVERY_POPUP);
    openDirtyPopup = false;
    openSaveAsPopup = false;
    openPrefabPopup = false;
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

    if (ImGui.beginPopupModal(PREFAB_POPUP, null, flags)) {
      if (ImGui.isWindowAppearing()) ImGui.setKeyboardFocusHere();
      var name = prefabName;
      if (ImGui.inputText("Prefab adı", name)) prefabName = name;
      if (ImGui.button("Oluştur") && actions.makePrefab(prefabName)) ImGui.closeCurrentPopup();
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
      centerWidth = center.Size.x;
      centerHeight = center.Size.y;
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
    ImGui.dockBuilderDockWindow(WORLD, right);
    ImGui.dockBuilderDockWindow(WARNINGS, bottom);
    ImGui.dockBuilderDockWindow(DATA, bottom);
    ImGui.dockBuilderDockWindow(DIALOGS, bottom);
    ImGui.dockBuilderDockWindow(AGENT, bottom);
    ImGui.dockBuilderDockWindow(ASSETS, bottom);
    ImGui.dockBuilderFinish(dock);
  }

  function drawWarnings() {
    drawFileConflicts();
    if (document.warningCount() == 0 && messages.length == 0) ImGui.textDisabled("Uyarı yok");
    for (i in 0...document.issues.length) {
      var issue = document.issues[i];
      if (!ImGui.selectable(issue.message + "##" + i)) continue;
      if (issue.dialog != null) dialogWorkspace.open(issue.dialog, issue.node == null ? 0 : issue.node);
      if (issue.entity == null || !scene.contains(issue.entity)) continue;
      selection.set([issue.entity]);
      hierarchy.reveal(issue.entity);
    }
    for (warning in scene.warnings) ImGui.textWrapped(warning);
    for (message in messages) ImGui.textWrapped(message);
    if (messages.length > 0 && ImGui.smallButton("Temizle")) messages = [];
  }

  // Dışarıda da değişen dosyalar: çakışmayan değişiklikler iki taraftan da kalır, çakışanda seçilen taraf.
  function drawFileConflicts() {
    for (conflict in diskGuard.conflicts.copy()) {
      ImGui.pushID(conflict.path);
      ImGui.textColored(ERROR_COLOR, '${conflict.path} kaydedilmedi: dışarıda da değişti. Çakışan: ${conflict.units.join(", ")}');
      if (ImGui.smallButton("Çakışanlarda benimki")) conflict.resolve(ThreeWay.MINE);
      ImGui.sameLine();
      if (ImGui.smallButton("Çakışanlarda diskteki")) conflict.resolve(ThreeWay.THEIRS);
      ImGui.sameLine();
      ImGui.textDisabled('İki hal de ${DiskGuard.BACKUP_DIRECTORY} altında yedeklendi');
      ImGui.popID();
    }
    for (path in diskGuard.pending.keys()) ImGui.textWrapped('$path dışarıda değişti, kaydedilmemiş değişikliğin var: kaydedince birleştirilecek');
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
