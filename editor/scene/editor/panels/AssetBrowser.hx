package scene.editor.panels;

import haxe.io.Path;
import imgui.ImGui;
import sys.FileSystem;

// `res` klasörünü gösterir. Modeller sahneye veya Inspector'daki asset alanına sürüklenir.
class AssetBrowser {
  public static inline var PAYLOAD = "ASSET";

  static inline var ROOT = "res";
  static inline var IMPORT_POPUP = "Model içe aktar";
  static inline var TILE = 92.;
  static inline var SCAN_SECONDS = 2.;
  static inline var IMPORT_WAIT_FRAMES = 3;
  static inline var TILE_COLOR = 0xFF3A3A40;
  static inline var FOLDER_COLOR = 0xFF5A4A34;
  static inline var PREFAB_COLOR = 0xFF2F5A86;
  static inline var LABEL_COLOR = 0xFFE0E0E0;
  static inline var FAILED_COLOR = 0xFFA03030;

  static var MODELS = ["fbx", "hmd"];
  static var IMAGES = ["png", "jpg", "jpeg", "tga", "dds"];
  static var SCENE_SUFFIX = ".scene.json";
  static var PREFAB_SUFFIX = ".prefab.json";

  var editor : Editor;
  var directory = ROOT;
  var folders : Array<String> = [];
  var files : Array<String> = [];
  var scanTimer = 0.;
  var payload = new hl.Bytes(1);
  var openImport = false;
  var pending : Array<String> = [];
  var importing : Null<String>;
  var importWait = 0;
  var images = new Map<String, h3d.mat.Texture>();

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function draw() {
    scanTimer -= hxd.Timer.dt;
    if (scanTimer <= 0) scan();
    drawToolbar();
    drawImport();
    ImGui.beginChild("##assets");
    drawTiles();
    ImGui.endChild();
  }

  function scan() {
    scanTimer = SCAN_SECONDS;
    folders = [];
    files = [];
    if (!FileSystem.exists(directory)) directory = ROOT;
    if (!FileSystem.exists(directory)) return;
    for (name in FileSystem.readDirectory(directory)) {
      if (StringTools.startsWith(name, ".")) continue;
      if (FileSystem.isDirectory('$directory/$name')) folders.push(name);
      else files.push(name);
    }
    folders.sort(Reflect.compare);
    files.sort(Reflect.compare);
  }

  function enter(path : String) {
    directory = path;
    scan();
  }

  function drawToolbar() {
    var parts = directory.split("/");
    for (i in 0...parts.length) {
      if (i > 0) ImGui.sameLine();
      if (ImGui.smallButton(parts[i] + "##" + i)) enter(parts.slice(0, i + 1).join("/"));
    }
    ImGui.sameLine();
    if (ImGui.smallButton("Model içe aktar")) {
      pending = editor.importer.pending();
      openImport = true;
    }
  }

  function drawImport() {
    if (openImport) {
      ImGui.openPopup(IMPORT_POPUP);
      openImport = false;
    }
    if (!ImGui.beginPopupModal(IMPORT_POPUP, null, ImGuiWindowFlags.AlwaysAutoResize)) return;
    // Büyük model saniyelerce sürer: yazı ekrana çıksın diye dönüştürme sonraki karelere kalır.
    if (importing != null) {
      ImGui.text('Dönüştürülüyor: $importing');
      ImGui.textDisabled("Büyük modellerde editör bir süre tepki vermez");
      if (--importWait <= 0) {
        var source = importing;
        importing = null;
        importModel(source);
      }
      ImGui.endPopup();
      return;
    }
    ImGui.text("assets klasöründe olup res klasörüne alınmamış modeller:");
    if (pending.length == 0) ImGui.textDisabled("Yeni model yok");
    for (source in pending.copy()) {
      ImGui.pushID(source);
      if (ImGui.smallButton("Al")) {
        importing = source;
        importWait = IMPORT_WAIT_FRAMES;
      }
      ImGui.sameLine();
      ImGui.text(source);
      ImGui.popID();
    }
    ImGui.separator();
    if (ImGui.button("Kapat")) ImGui.closeCurrentPopup();
    ImGui.endPopup();
  }

  function importModel(source : String) {
    var result = editor.importer.run(source);
    for (problem in result.problems) editor.report(problem);
    if (result.target == null) {
      editor.show("İçe aktarılamadı, ayrıntı Uyarılar panelinde", true);
      return;
    }
    pending.remove(source);
    enter(Path.directory(result.target));
    editor.show('İçe aktarıldı: ${result.target} (${result.triangles} üçgen, ${result.parts} parça)');
  }

  function drawTiles() {
    var size = TILE * editor.interfaceScale;
    var height = size + ImGui.getTextLineHeightWithSpacing();
    var spacing = ImGui.getStyle().ItemSpacing.x;
    var perRow = Std.int(Math.max(1, (ImGui.getContentRegionAvail().x + spacing) / (size + spacing)));
    var index = 0;
    function next() {
      if (index++ % perRow != 0) ImGui.sameLine();
    }

    for (name in folders) {
      next();
      if (tile(name, size, height)) enter('$directory/$name');
      fill(FOLDER_COLOR, size, name);
    }
    for (name in files) {
      next();
      var path = '$directory/$name';
      var resource = path.substr(ROOT.length + 1);
      var activated = tile(name, size, height);
      if (ImGui.isItemHovered()) ImGui.setTooltip(failure(resource) == null ? resource : '$resource: ${failure(resource)}');
      if (activated && isDocument(name)) editor.requestOpen(path);
      drawPreview(resource, name, size);
      if (isPlaceable(name) && ImGui.beginDragDropSource()) {
        editor.assetDrag = resource;
        ImGui.setDragDropPayload(PAYLOAD, payload, 1);
        ImGui.text(name);
        ImGui.endDragDropSource();
      }
    }
  }

  function tile(name : String, size : Float, height : Float) {
    ImGui.pushID(name);
    // hlimgui sabit değeri Ref sürümüne bağlar ve yerel kodda çöker: değer değişkenle verilir.
    var selected = false;
    var clicked = ImGui.selectable("##tile", selected, ImGuiSelectableFlags.AllowDoubleClick, {x: size, y: height});
    ImGui.popID();
    return clicked && ImGui.isMouseDoubleClicked(0);
  }

  function drawPreview(resource : String, name : String, size : Float) {
    var extension = Path.extension(name).toLowerCase();
    var texture = MODELS.indexOf(extension) >= 0 ? editor.previews.textureOf(resource) : IMAGES.indexOf(extension) >= 0 ? image(resource) : null;
    if (texture == null) {
      var color = failure(resource) != null ? FAILED_COLOR : StringTools.endsWith(name, PREFAB_SUFFIX) ? PREFAB_COLOR : TILE_COLOR;
      fill(color, size, name);
      return;
    }
    var at = tileOrigin();
    ImGui.getWindowDrawList().addImage(texture, at, {x: at.x + size, y: at.y + size});
    label(name, size);
  }

  function fill(color : Int, size : Float, name : String) {
    var at = tileOrigin();
    ImGui.getWindowDrawList().addRectFilled(at, {x: at.x + size, y: at.y + size}, color);
    label(name, size);
  }

  // Selectable kendi dikdörtgenini öğe aralığının yarısı kadar dışa taşırır.
  function tileOrigin() : ImVec2 {
    var min = ImGui.getItemRectMin(), spacing = ImGui.getStyle().ItemSpacing;
    return {x: min.x + spacing.x * 0.5, y: min.y + spacing.y * 0.5};
  }

  // Uzun ad karenin dışına taşmasın.
  function label(name : String, size : Float) {
    var text = name;
    while (text.length > 1 && ImGui.calcTextSize(text).x > size) text = text.substr(0, text.length - 1);
    var at = tileOrigin();
    ImGui.getWindowDrawList().addText({x: at.x, y: at.y + size}, LABEL_COLOR, text);
  }

  function image(resource : String) {
    if (images.exists(resource)) return images.get(resource);
    var texture = try hxd.Res.load(resource).toTexture() catch (e : Dynamic) null;
    images.set(resource, texture);
    return texture;
  }

  function failure(resource : String) {
    return editor.previews.failureOf(resource);
  }

  static function isDocument(name : String) {
    return StringTools.endsWith(name, SCENE_SUFFIX) || StringTools.endsWith(name, PREFAB_SUFFIX);
  }

  static function isPlaceable(name : String) {
    return MODELS.indexOf(Path.extension(name).toLowerCase()) >= 0 || StringTools.endsWith(name, PREFAB_SUFFIX);
  }
}
