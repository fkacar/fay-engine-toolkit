package scene.editor;

import scene.data.SceneData;
import scene.data.SceneFormat;
import scene.editor.Validator.Issue;
import scene.world.WorldData;
import scene.world.WorldState;
import sys.FileSystem;
import sys.io.File;

// Açık sahne dosyası: kaydetme, açma, son açılanlar, otomatik yedek ve kurtarma.
class SceneDocument {
  static inline var SCENE_DIRECTORY = "res/scenes";
  static inline var SCENE_SUFFIX = ".scene.json";
  static inline var PREFAB_SUFFIX = ".prefab.json";
  static inline var NEW_SCENE_NAME = "yeni";
  static inline var AUTOSAVE_DIRECTORY = EditorPrefs.DIRECTORY + "/autosave";
  static inline var AUTOSAVE_SECONDS = 60.;
  static inline var AUTOSAVE_WORLD = AUTOSAVE_DIRECTORY + "/world";

  public var path(default, null) : String;
  public var lastSaved(default, null) = "";
  public var issues(default, null) : Array<Issue> = [];
  public var prefs(default, null) = new EditorPrefs();
  public var hasRecovery(default, null) = false;
  // Açık belge dünyaysa dolu, tek sahne veya prefab açıkken boştur.
  public var world(default, null) : Null<WorldDocument>;

  var worlds : Null<WorldDocument>;
  var worldFile = "";
  var editor : Editor;
  var scene : SceneInstance;
  var autosaveTimer = 0.;
  var autosavedRevision = 0;

  public function new(editor : Editor, scene : SceneInstance, path : String, ?state : WorldState) {
    this.editor = editor;
    this.scene = scene;
    this.path = path;
    if (state != null) {
      worlds = new WorldDocument(editor, scene, state);
      worldFile = path;
    }
    applyFlags();
    hasRecovery = isRecoverable();
  }

  public function canOpenWorld() {
    return worlds != null;
  }

  public function worldPath() {
    return worldFile;
  }

  public function save() {
    var written = 1;
    try {
      if (world != null) written = world.save();
      else File.saveContent(path, SceneFormat.write(scene.toData()));
    } catch (e : Dynamic) {
      editor.show('Kaydedilemedi: $e', true);
      return false;
    }
    editor.commands.markSaved();
    removeAutosave();
    prefs.addRecent(path);
    lastSaved = DateTools.format(Date.now(), "%H:%M:%S");
    validate();
    var count = warningCount();
    var name = world == null ? path : '$written dosya';
    editor.show(count == 0 ? 'Kaydedildi: $name' : 'Kaydedildi: $name ($count uyarı)', false);
    return true;
  }

  public function saveAs(name : String) {
    var clean = cleanName(name);
    if (clean == "") {
      editor.show("Geçerli bir sahne adı yaz", true);
      return false;
    }
    var target = '$SCENE_DIRECTORY/$clean$SCENE_SUFFIX';
    if (target != path && FileSystem.exists(target)) {
      editor.show('Bu adda bir sahne var: $clean', true);
      return false;
    }
    path = target;
    return save();
  }

  public function open(target : String) {
    var isWorld = WorldData.isWorldFile(target) && worlds != null;
    try {
      if (isWorld) worlds.open(prefs.cellsIn(target), target);
      else scene.load(SceneFormat.read(File.getContent(target)));
    } catch (e : Dynamic) {
      editor.show('Açılamadı: $e', true);
      prefs.removeRecent(target);
      return;
    }
    if (world != null && !isWorld) world.close();
    world = isWorld ? worlds : null;
    path = target;
    prefs.addRecent(target);
    loaded('Açıldı: $target');
  }

  public function reopen() {
    open(path);
  }

  public function newScene() {
    scene.load(new SceneData(SceneFormat.VERSION));
    if (world != null) world.close();
    world = null;
    path = freeName();
    loaded('Yeni sahne: $path');
  }

  public function sceneFiles() : Array<String> {
    if (!FileSystem.exists(SCENE_DIRECTORY)) return [];
    var names = FileSystem.readDirectory(SCENE_DIRECTORY).filter(name -> StringTools.endsWith(name, SCENE_SUFFIX));
    names.sort(Reflect.compare);
    return [for (name in names) '$SCENE_DIRECTORY/$name'];
  }

  public function recover() {
    try {
      if (world != null) world.recover(AUTOSAVE_WORLD, prefs.cellsIn(path), path);
      else scene.load(SceneFormat.read(File.getContent(autosavePath())));
    } catch (e : Dynamic) {
      editor.show('Yedek açılamadı: $e', true);
      discardRecovery();
      return;
    }
    loaded("Otomatik yedekten dönüldü, kaydetmeyi unutma");
    hasRecovery = false;
    editor.commands.markUnsaved();
  }

  public function discardRecovery() {
    removeAutosave();
    hasRecovery = false;
  }

  public function rememberFlags() {
    var hidden = [for (entity in scene.entities) if (entity.hiddenInEditor) entity.id];
    var groups = editor.groups.toIds();
    // Yüklü olmayan hücrelerin kişisel ayarları kaybolmasın.
    if (world != null) {
      hidden = hidden.concat(prefs.hiddenIn(path).filter(id -> scene.find(id) == null));
      groups = groups.concat(prefs.groupsIn(path).filter(group -> Lambda.exists(group, id -> scene.find(id) == null)));
    }
    prefs.setFlags(path, hidden, groups);
  }

  // Hücre yüklenince veya boşaltılınca seçim, kişisel ayarlar ve uyarılar güncellenir.
  public function cellsChanged() {
    prefs.setCells(path, world.loadedCells());
    applyFlags();
    validate();
  }

  public function showAll() {
    for (entity in scene.entities) if (entity.hiddenInEditor) entity.hiddenInEditor = false;
    rememberFlags();
  }

  // Prefab dosyası tek köklüdür, aksi halde instance'lar açılamaz.
  public function prefabRootIssues() : Array<Validator.Issue> {
    var roots = scene.entities.filter(entity -> entity.parent == null);
    if (!StringTools.endsWith(path, PREFAB_SUFFIX) || roots.length < 2) return [];
    return [{entity: roots[1], message: '${roots[1].name}: prefab tek köklü olmalı, nesneleri tek kökün altına al'}];
  }

  public function validate() {
    issues = editor.validator.run(scene);
  }

  public function warningCount() {
    return issues.length + scene.warnings.length;
  }

  public function update(dt : Float) {
    autosaveTimer += dt;
    if (autosaveTimer < AUTOSAVE_SECONDS) return;
    autosaveTimer = 0;
    var commands = editor.commands;
    if (!commands.isDirty || commands.revision == autosavedRevision) return;
    try {
      if (!FileSystem.exists(AUTOSAVE_DIRECTORY)) FileSystem.createDirectory(AUTOSAVE_DIRECTORY);
      if (world != null) world.autosave(AUTOSAVE_WORLD);
      else File.saveContent(autosavePath(), SceneFormat.write(scene.toData()));
      autosavedRevision = commands.revision;
    } catch (e : Dynamic) {
      editor.show('Otomatik yedek alınamadı: $e', true);
    }
  }

  // Oyuna geçerken yol `res` köküne göre verilir: Heaps kaynakları böyle bulur.
  public function resourcePath() {
    return StringTools.startsWith(path, "res/") ? path.substr(4) : path;
  }

  public function removeAutosave() {
    if (FileSystem.exists(autosavePath())) FileSystem.deleteFile(autosavePath());
    if (!FileSystem.exists(AUTOSAVE_WORLD)) return;
    for (name in FileSystem.readDirectory(AUTOSAVE_WORLD)) FileSystem.deleteFile('$AUTOSAVE_WORLD/$name');
  }

  function loaded(message : String) {
    editor.selection.clear();
    editor.commands.clear();
    lastSaved = "";
    issues = [];
    autosaveTimer = 0;
    autosavedRevision = 0;
    applyFlags();
    validate();
    hasRecovery = isRecoverable();
    editor.show(message);
  }

  function applyFlags() {
    for (id in prefs.hiddenIn(path)) {
      var entity = scene.find(id);
      if (entity != null) entity.hiddenInEditor = true;
    }
    editor.groups.load(prefs.groupsIn(path), scene);
  }

  function autosavePath() {
    return AUTOSAVE_DIRECTORY + "/" + haxe.io.Path.withoutDirectory(path);
  }

  // Yedek sahneden yeniyse editör kapanmadan önce kaydedilmemiş iş kalmıştır.
  function isRecoverable() {
    if (WorldData.isWorldFile(path)) return FileSystem.exists(AUTOSAVE_WORLD) && FileSystem.readDirectory(AUTOSAVE_WORLD).length > 0;
    if (!FileSystem.exists(autosavePath())) return false;
    if (!FileSystem.exists(path)) return true;
    return FileSystem.stat(autosavePath()).mtime.getTime() > FileSystem.stat(path).mtime.getTime();
  }

  function freeName() {
    var candidate = '$SCENE_DIRECTORY/$NEW_SCENE_NAME$SCENE_SUFFIX';
    var index = 2;
    while (FileSystem.exists(candidate)) candidate = '$SCENE_DIRECTORY/$NEW_SCENE_NAME-${index++}$SCENE_SUFFIX';
    return candidate;
  }

  // Dosya adı her sistemde ve komut satırında sorunsuz olmalı.
  public static function cleanName(name : String) {
    var out = new StringBuf();
    for (i in 0...name.length) {
      var code = StringTools.fastCodeAt(name, i);
      var text = name.charAt(i);
      out.add(switch (text) {
        case "ç", "Ç": "c";
        case "ğ", "Ğ": "g";
        case "ı", "I", "İ": "i";
        case "ö", "Ö": "o";
        case "ş", "Ş": "s";
        case "ü", "Ü": "u";
        case " ", "-", "_", "+", ".": "_";
        default: isPlain(code) ? text.toLowerCase() : "";
      });
    }
    var clean = out.toString();
    while (clean.indexOf("__") >= 0) clean = StringTools.replace(clean, "__", "_");
    while (StringTools.startsWith(clean, "_")) clean = clean.substr(1);
    while (StringTools.endsWith(clean, "_")) clean = clean.substr(0, clean.length - 1);
    return clean;
  }

  static function isPlain(code : Int) {
    return (code >= "a".code && code <= "z".code) || (code >= "A".code && code <= "Z".code) || (code >= "0".code && code <= "9".code);
  }
}
