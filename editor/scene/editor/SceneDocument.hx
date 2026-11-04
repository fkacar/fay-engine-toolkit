package scene.editor;

import scene.data.SceneData;
import scene.data.SceneFormat;
import scene.data.ThreeWay;
import scene.data.ThreeWay.MergeOutcome;
import scene.editor.commands.SetDialogCommand;
import scene.editor.commands.SetTableCommand;
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
  // Tek sahne kipinde diskten son okunan veya yazılan hal: kaydederken birleştirmenin tabanı.
  var sceneBase : Null<String>;
  var notifiedPending = 0;
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

  // Bellekte açık olan dosya: dünyada genel dosya ve yüklü hücreler, tek sahnede kendisi.
  public function isOpenFile(file : String) {
    if (world == null) return file == path;
    var data = world.data;
    if (file == "res/" + data.path(WorldData.GLOBAL, WorldData.OBJECTS_SUFFIX)) return true;
    for (cell in world.loadedCells()) if (file == "res/" + data.path(cell, WorldData.OBJECTS_SUFFIX)) return true;
    return false;
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
      else written = saveScene();
      written += editor.data.save() + editor.dialogs.save();
    } catch (e : Dynamic) {
      editor.show('Kaydedilemedi: $e', true);
      return false;
    }
    // Çakışan dosya kaydedilmedi: belge kaydedilmiş sayılmaz, kapatırken yine sorulur.
    var conflicts = editor.diskGuard.conflicts.length;
    if (conflicts > 0) {
      validate();
      editor.show('$conflicts dosya kaydedilmedi: dışarıda da değişmiş ve aynı yerler çakışıyor. Uyarılar paneline bak', true);
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
    sceneBase = DiskGuard.read(target);
    return save();
  }

  public function open(target : String) {
    var isWorld = WorldData.isWorldFile(target) && worlds != null;
    editor.diskGuard.forgetAll();
    try {
      if (isWorld) worlds.open(prefs.cellsIn(target), target);
      else {
        var text = File.getContent(target);
        scene.load(SceneFormat.read(text));
        sceneBase = text;
        editor.diskGuard.observe(target, text);
      }
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

  // Açık dosyalar dışarıda değişti mi: temiz olanlar yeniden yüklenir, kaydedilmemiş değişikliği
  // olanlar kaydederken birleşir.
  public function checkDisk() {
    var reloaded = world != null ? world.checkDisk() : checkScene();
    reloaded = reloaded.concat(editor.data.checkDisk()).concat(editor.dialogs.checkDisk());
    if (reloaded.length > 0) {
      validate();
      editor.show(reloaded.length == 1 ? 'Dışarıda değişti, yeniden yüklendi: ${reloaded[0]}' : 'Dışarıda değişti, yeniden yüklendi: ${reloaded.length} dosya');
    }
    var pending = Lambda.count(editor.diskGuard.pending);
    if (pending > notifiedPending) editor.show("Kaydedilmemiş değişikliğin olan bir dosya dışarıda değişti: kaydedince birleştirilecek");
    notifiedPending = pending;
  }

  // Kaydedilmemiş bütün dosyalar: sahne veya hücreler, tablolar, diyaloglar.
  public function unsavedFiles() : Array<String> {
    var files = world != null ? world.unsavedFiles() : sceneBase == null && scene.entities.length == 0
      || sceneBase != null && SceneFormat.write(scene.toData()) == canonical(sceneBase) ? [] : [path];
    return files.concat(editor.data.unsavedFiles()).concat(editor.dialogs.unsavedFiles());
  }

  // Bir dosyanın editördeki hali: kaydedilirse yazılacak metin.
  public function editorText(file : String) : Null<String> {
    if (world != null && StringTools.startsWith(file, "res/world/")) return world.editorText(file);
    if (world == null && file == path) return SceneFormat.write(scene.toData());
    var table = editor.data.editorText(file);
    return table != null ? table : editor.dialogs.editorText(file);
  }

  function checkScene() : Array<String> {
    var change = editor.diskGuard.changed(path);
    if (change == null || change.text == sceneBase) return [];
    var mine = SceneFormat.write(scene.toData());
    if (mine == change.text) {
      sceneBase = change.text;
      return [];
    }
    var clean = sceneBase == null ? scene.entities.length == 0 : mine == canonical(sceneBase);
    if (!clean || change.text == null) {
      editor.diskGuard.pending.set(path, true);
      return [];
    }
    try replaceScene(change.text) catch (e : Dynamic) {
      editor.diskGuard.pending.set(path, true);
      editor.show('$path okunamadı: $e', true);
      return [];
    }
    sceneBase = change.text;
    return [path];
  }

  function saveScene() : Int {
    var mine = SceneFormat.write(scene.toData());
    var current = DiskGuard.read(path);
    var output : Null<String> = mine;
    if (current != sceneBase) {
      var result = mergeScene(sceneBase, mine, current, null);
      if (result.text == null && result.conflicts.length > 0) {
        editor.diskGuard.backup(path, mine, current);
        editor.diskGuard.addConflict(path, result.conflicts, resolveScene);
        return 0;
      }
      output = result.text;
      if (output != mine) replaceScene(output);
    }
    if (output == null) editor.diskGuard.delete(path);
    else editor.diskGuard.write(path, output);
    sceneBase = output;
    return 1;
  }

  function resolveScene(prefer : String) {
    var current = DiskGuard.read(path);
    var result = mergeScene(sceneBase, SceneFormat.write(scene.toData()), current, prefer);
    editor.diskGuard.removeConflict(path);
    if (result.text == null) editor.diskGuard.delete(path);
    else editor.diskGuard.write(path, result.text);
    sceneBase = result.text;
    replaceScene(result.text);
  }

  function mergeScene(base : Null<String>, mine : Null<String>, theirs : Null<String>, prefer : Null<String>) : MergeOutcome {
    try {
      return ThreeWay.scene(base, mine, theirs, prefer);
    } catch (e : Dynamic) {
      if (prefer == null) return {text: null, conflicts: ['okunamadı: $e']};
      return ThreeWay.whole(base, mine, theirs, prefer);
    }
  }

  // Sahne nesneleri yeniden kurulur: onlara dokunan geri alma adımları düşer, tablo ve diyalog adımları kalır.
  function replaceScene(text : Null<String>) {
    scene.load(text == null ? new SceneData(SceneFormat.VERSION) : SceneFormat.read(text));
    editor.commands.forget(command -> !Std.isOfType(command, SetTableCommand) && !Std.isOfType(command, SetDialogCommand));
    editor.selection.clear();
    applyFlags();
  }

  static function canonical(text : String) {
    return try SceneFormat.write(SceneFormat.read(text)) catch (e : Dynamic) text;
  }

  public function reopen() {
    open(path);
  }

  public function newScene() {
    editor.diskGuard.forgetAll();
    sceneBase = null;
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
    return issues.length + scene.warnings.length + editor.diskGuard.conflicts.length;
  }

  public function update(dt : Float) {
    if (editor.diskGuard.due(dt)) checkDisk();
    autosaveTimer += dt;
    if (autosaveTimer < AUTOSAVE_SECONDS) return;
    autosaveTimer = 0;
    backupNow();
  }

  // Otomatik yedek şimdi: süre beklenmez (editörde hata olunca da çağrılır). Yedeklenecek değişiklik yoksa false.
  public function backupNow() : Bool {
    var commands = editor.commands;
    if (!commands.isDirty || commands.revision == autosavedRevision) return false;
    try {
      if (!FileSystem.exists(AUTOSAVE_DIRECTORY)) FileSystem.createDirectory(AUTOSAVE_DIRECTORY);
      if (world != null) world.autosave(AUTOSAVE_WORLD);
      else File.saveContent(autosavePath(), SceneFormat.write(scene.toData()));
      autosavedRevision = commands.revision;
      return true;
    } catch (e : Dynamic) {
      editor.show('Otomatik yedek alınamadı: $e', true);
      return false;
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
    // Kaydedilmeden bırakılan tablo değişiklikleri de atılır, geçmişle birlikte.
    editor.data.reload();
    editor.dialogs.reload();
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
