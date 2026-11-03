package scene.editor.panels;

import haxe.io.Path;
import imgui.ImGui;
import scene.editor.ImportSettings;
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
  var sources : Array<String> = [];
  // Ayarları açık olan kaynak ve düzenlenen ayarlar; Kaydet'e kadar dosyaya yazılmaz.
  var trimSource : Null<String>;
  var settings = new ImportSettings();
  var joints : Array<String> = [];
  var importedDefaults : Array<ImportSettings.SocketSpec> = [];
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
      sources = editor.importer.sources();
      trimSource = null;
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
    ImGui.text("assets klasöründeki modeller:");
    if (sources.length == 0) ImGui.textDisabled("Model yok");
    for (source in sources) {
      ImGui.pushID(source);
      var fresh = pending.indexOf(source) >= 0;
      if (ImGui.smallButton(fresh ? "Al" : "Yeniden al")) {
        importing = source;
        importWait = IMPORT_WAIT_FRAMES;
      }
      ImGui.sameLine();
      if (fresh) ImGui.text(source) else ImGui.textDisabled(source);
      ImGui.sameLine();
      var saved = try ImportSettings.read(source) catch (e : Dynamic) null;
      var summary = saved == null ? "Ayarlar (bozuk)" : saved.trim.length + saved.clips.length + saved.sockets.length == 0 ? "Ayarlar" : 'Ayarlar (${saved.trim.length} kutu, ${saved.clips.length} klip, ${saved.sockets.length} nokta)';
      if (ImGui.smallButton(summary)) {
        if (trimSource == source) trimSource = null;
        else {
          trimSource = source;
          settings = saved == null ? new ImportSettings() : saved;
          joints = importedJoints(source);
          importedDefaults = importedSockets(source);
        }
      }
      // Ayarlar uzayabilir (kutular, klipler, takma noktaları): kaydırılan bir alanda, pencere ekrandan taşmasın.
      if (trimSource == source) {
        var height = h3d.Engine.getCurrent().height * 0.45;
        ImGui.beginChild("##ayarlar", {x: 1000 * editor.interfaceScale, y: height}, true);
        drawSettings(source);
        ImGui.endChild();
      }
      ImGui.popID();
    }
    ImGui.separator();
    if (ImGui.button("Kapat")) ImGui.closeCurrentPopup();
    ImGui.endPopup();
  }

  // Kırpma: modelin kendi birimleriyle, Z yukarı; kutuyu ajan model_info'nun taban haritasından da önerebilir.
  // Klipler: başka FBX'lerden alınıp bu modele eklenir (aynı iskelet). Karakter durma, yurume, kosma arar.
  function drawSettings(source : String) {
    ImGui.indent();
    ImGui.text("Kırpma");
    ImGui.textDisabled("Kutuların içinde kalan üçgenler içe aktarırken atılır. Birimler modelin kendisinin, Z yukarı.");
    var trimBoxes = settings.trim;
    var width = 64 * editor.interfaceScale;
    var removed = -1;
    for (i in 0...trimBoxes.length) {
      var box = trimBoxes[i];
      ImGui.pushID('kutu$i');
      ImGui.text('Kutu ${i + 1}');
      if (box.note != null && box.note != "") {
        ImGui.sameLine();
        ImGui.textDisabled(box.note);
      }
      ImGui.sameLine();
      if (ImGui.smallButton("Sil")) removed = i;
      for (row in 0...2) {
        var values = row == 0 ? box.min : box.max;
        ImGui.text(row == 0 ? "En az" : "En çok");
        for (axis in 0...3) {
          ImGui.sameLine();
          ImGui.pushItemWidth(width);
          var edited = values[axis];
          if (ImGui.inputDouble('${["x", "y", "z"][axis]}##$row', edited, 0, 0, "%.1f")) values[axis] = edited;
          ImGui.popItemWidth();
        }
      }
      ImGui.popID();
    }
    if (removed >= 0) trimBoxes.splice(removed, 1);
    if (ImGui.smallButton("+ Kutu")) trimBoxes.push({min: [0., 0., 0.], max: [0., 0., 0.]});
    ImGui.separator();
    ImGui.text("Klipler");
    ImGui.textDisabled("Aynı iskeletle üretilmiş FBX'lerin animasyonu bu modele eklenir. Karakter durma, yurume, kosma, hizli_kosma adlarını kullanır; silahlı set _tufek gibi türün ekiyle. Kollar seçilirse kollar o klibin ilk karesindeki duruşta kalır.");
    var gone = -1;
    for (i in 0...settings.clips.length) {
      var clip = settings.clips[i];
      ImGui.pushID('klip$i');
      ImGui.pushItemWidth(110 * editor.interfaceScale);
      var name = clip.name;
      if (ImGui.inputText("##ad", name)) clip.name = name;
      ImGui.popItemWidth();
      ImGui.sameLine();
      ImGui.pushItemWidth(280 * editor.interfaceScale);
      // Kutuda dosya adı görünür; aynı klasördeki klipler ayırt edilsin. Tam yol listede.
      if (ImGui.beginCombo("##kaynak", clip.source == "" ? "(FBX seç)" : Path.withoutDirectory(clip.source))) {
        for (candidate in sources) if (candidate != source && ImGui.selectable(candidate, candidate == clip.source)) clip.source = candidate;
        ImGui.endCombo();
      }
      ImGui.popItemWidth();
      ImGui.sameLine();
      // Kollar: seçilirse kollar o klibin ilk karesindeki duruşta kalır (silahlı set türetmek için).
      ImGui.pushItemWidth(220 * editor.interfaceScale);
      if (ImGui.beginCombo("##kollar", clip.arms == null || clip.arms == "" ? "(kollar klipten)" : "Kollar: " + Path.withoutDirectory(clip.arms))) {
        if (ImGui.selectable("(kollar klipten)", clip.arms == null || clip.arms == "")) clip.arms = null;
        for (candidate in sources) if (candidate != source && ImGui.selectable(candidate, candidate == clip.arms)) clip.arms = candidate;
        ImGui.endCombo();
      }
      ImGui.popItemWidth();
      ImGui.sameLine();
      if (ImGui.smallButton("Sil")) gone = i;
      ImGui.popID();
    }
    if (gone >= 0) settings.clips.splice(gone, 1);
    if (ImGui.smallButton("+ Klip")) settings.clips.push({name: freeClipName(), source: ""});
    ImGui.separator();
    drawSockets(source);
    ImGui.separator();
    if (ImGui.smallButton("Kaydet")) {
      try {
        var checked = new ImportSettings();
        checked.trim = [for (box in trimBoxes) ModelTrim.check(box)];
        checked.clips = [for (clip in settings.clips) ImportSettings.checkClip(clip)];
        checked.sockets = [for (socket in settings.sockets) ImportSettings.checkSocket(socket)];
        checked.write(source);
        pending = editor.importer.pending();
        editor.show('Ayarlar kaydedildi: ${ImportSettings.path(source)}. Modeli yeniden al');
      } catch (e : Dynamic) editor.show('Ayarlar kaydedilemedi: $e', true);
    }
    ImGui.unindent();
  }

  // Takma noktaları: silah ve eşyanın takıldığı eklem, konum (metre) ve dönüş (derece). Karakterde
  // eksenler X ileri, Y sağ, Z yukarı (bağlama pozunda). İskeletsiz modelde (silah) eklem boş: tutamak modelin kendisinde.
  function drawSockets(source : String) {
    ImGui.text("Takma noktaları");
    ImGui.textDisabled("Silah ve eşyalar bu noktalara takılır. Karakterde X ileri, Y sağ, Z yukarı; silahta tutamak noktası (tutamak), eklem boş.");
    if (settings.sockets.length == 0) {
      ImGui.textDisabled(joints.length > 0 ? "Ayar yok: iskeletli modelde varsayılan noktalar kullanılır (sag_el, sol_el, sirt, bel, bas)." : "Ayar yok.");
      if (importedDefaults.length > 0) {
        if (ImGui.smallButton("Varsayılanları düzenle"))
          settings.sockets = [for (socket in importedDefaults) ImportSettings.checkSocket(haxe.Json.parse(haxe.Json.stringify(socket)))];
      }
    }
    var width = 64 * editor.interfaceScale;
    var gone = -1;
    for (i in 0...settings.sockets.length) {
      var socket = settings.sockets[i];
      ImGui.pushID('nokta$i');
      ImGui.pushItemWidth(110 * editor.interfaceScale);
      var name = socket.name;
      if (ImGui.inputText("##ad", name)) socket.name = name;
      ImGui.popItemWidth();
      ImGui.sameLine();
      ImGui.pushItemWidth(170 * editor.interfaceScale);
      if (joints.length > 0) {
        if (ImGui.beginCombo("##eklem", socket.joint == "" ? "(modelin kendisi)" : socket.joint)) {
          if (ImGui.selectable("(modelin kendisi)", socket.joint == "")) socket.joint = "";
          for (joint in joints) if (ImGui.selectable(joint, joint == socket.joint)) socket.joint = joint;
          ImGui.endCombo();
        }
      } else {
        var joint = socket.joint;
        if (ImGui.inputText("##eklem", joint)) socket.joint = joint;
      }
      ImGui.popItemWidth();
      ImGui.sameLine();
      if (ImGui.smallButton("Sil")) gone = i;
      for (row in 0...2) {
        var values = row == 0 ? socket.offset : socket.rotation;
        if (row == 1) ImGui.sameLine();
        ImGui.text(row == 0 ? "Konum (m)" : "Dönüş (°)");
        for (axis in 0...3) {
          ImGui.sameLine();
          ImGui.pushItemWidth(width);
          var edited = values[axis];
          if (ImGui.inputDouble('${["x", "y", "z"][axis]}##n$row', edited, 0, 0, row == 0 ? "%.3f" : "%.1f")) values[axis] = edited;
          ImGui.popItemWidth();
        }
      }
      ImGui.popID();
    }
    if (gone >= 0) settings.sockets.splice(gone, 1);
    if (ImGui.smallButton("+ Nokta")) settings.sockets.push({name: freeSocketName(), joint: "", offset: [0., 0., 0.], rotation: [0., 0., 0.]});
  }

  function freeSocketName() : String {
    var used = [for (socket in settings.sockets) socket.name => true];
    var preferred = joints.length == 0 ? ["tutamak"] : ["sag_el", "sol_el", "sirt", "bel", "bas"];
    for (name in preferred) if (!used.exists(name)) return name;
    var n = settings.sockets.length + 1;
    while (used.exists('nokta_$n')) n++;
    return 'nokta_$n';
  }

  // Daha önce alınmış modelin eklemleri: dosyanın yalnızca başlığı okunur, FBX dönüştürülmez.
  function importedJoints(source : String) : Array<String> {
    var target = editor.importer.targetOf(source);
    if (!sys.FileSystem.exists(target)) return [];
    return try {
      var hmd = new hxd.fmt.hmd.Reader(new haxe.io.BytesInput(sys.io.File.getBytes(target))).readHeader();
      [for (model in hmd.models) if (model.skin != null) for (joint in model.skin.joints) if (!StringTools.endsWith(joint.name, "_end")) joint.name];
    } catch (e : Dynamic) [];
  }

  // İçe aktarmanın yazdığı varsayılan noktalar (<hedef>.model.json): düzenlemeye bunlardan başlanır.
  function importedSockets(source : String) : Array<ImportSettings.SocketSpec> {
    var info = scene.editor.AssetImporter.infoPath(editor.importer.targetOf(source));
    if (!sys.FileSystem.exists(info)) return [];
    return try {
      var raw : Dynamic = haxe.Json.parse(sys.io.File.getContent(info));
      var items : Array<Dynamic> = raw.sockets == null ? [] : raw.sockets;
      [for (item in items) ImportSettings.checkSocket(item)];
    } catch (e : Dynamic) [];
  }

  // Karakterin aradığı adlardan kullanılmayan ilki, hepsi varsa klip_N.
  function freeClipName() : String {
    var used = [for (clip in settings.clips) clip.name => true];
    for (name in ["durma", "yurume", "kosma", "hizli_kosma"]) if (!used.exists(name)) return name;
    var n = settings.clips.length + 1;
    while (used.exists('klip_$n')) n++;
    return 'klip_$n';
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
    editor.show('İçe aktarıldı: ${result.target} (${result.triangles} üçgen, ${result.parts} parça${result.trimmed > 0 ? ", " + result.trimmed + " üçgen kırpıldı" : ""})');
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
