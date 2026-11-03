package scene.save;

import haxe.io.Path;
import sys.FileSystem;

// seed: oyun olaylarının rastgele akışlarının kökü (RandomStreams). ended/result: Ironman'da ekip tükenince
// sefer biter; kayıtları silinmez, salt okunur kalır.
typedef CampaignInfo = {id : String, name : String, created : Float, ironman : Bool, version : String, ?seed : Int, ?ended : Bool, ?result : String};
typedef SaveEntry = {path : String, kind : String, modified : Float, campaign : String};

// Seferler ve yuvalar: <kök>/<sefer>/{sefer.json, elle_<tarih>.kayit, hizli.kayit, oto_1..3.kayit, ironman.kayit}.
// Liste klasör taranarak çıkar; her kayıtta değişen ortak bir dizin dosyası yok (Steam Cloud'da çakışmasın).
class SaveSlots {
  public static inline var EXTENSION = "kayit";
  public static inline var CAMPAIGN_FILE = "sefer.json";
  public static inline var MANUAL = "elle";
  public static inline var QUICK = "hizli";
  public static inline var AUTO = "oto";
  public static inline var IRONMAN = "ironman";
  public static inline var AUTO_COUNT = 3;
  public static inline var MANUAL_LIMIT = 50;

  public var root(default, null) : String;

  public function new(root : String) {
    this.root = root;
  }

  public function campaigns() : Array<CampaignInfo> {
    if (!FileSystem.exists(root)) return [];
    var found = [];
    for (name in FileSystem.readDirectory(root)) {
      var file = '$root/$name/$CAMPAIGN_FILE';
      if (!FileSystem.exists(file)) continue;
      var info : Null<CampaignInfo> = try haxe.Json.parse(sys.io.File.getContent(file)) catch (e : Dynamic) null;
      if (info != null) found.push(info);
    }
    found.sort((a, b) -> a.created < b.created ? 1 : a.created > b.created ? -1 : 0);
    return found;
  }

  public function campaign(id : String) : Null<CampaignInfo> {
    return Lambda.find(campaigns(), info -> info.id == id);
  }

  // Kimlik tarih ve rastgele ekten: iki bilgisayarda aynı anda açılan seferler çakışmaz.
  // Yeni seferin tohumu. Oyun kodunda tohumsuz rastgelelik yasak; tek kaynak burası.
  public static function newSeed() : Int {
    return Std.random(0x7FFFFFFF);
  }

  public function createCampaign(name : String, ironman : Bool, version : String, ?seed : Int) : CampaignInfo {
    var id = DateTools.format(Date.now(), "%Y%m%d_%H%M%S") + "_" + StringTools.hex(Std.random(0xFFFFFF), 6).toLowerCase();
    var info : CampaignInfo = {id: id, name: name, created: Date.now().getTime(), ironman: ironman, version: version, seed: seed == null ? newSeed() : seed};
    updateCampaign(info);
    return info;
  }

  public function updateCampaign(info : CampaignInfo) {
    makeDirectory('$root/${info.id}');
    sys.io.File.saveContent('$root/${info.id}/$CAMPAIGN_FILE', haxe.Json.stringify(info, null, "  ") + "\n");
  }

  // Devam et: bitmemiş seferlerin en yeni kaydı.
  public function latestOverall() : Null<SaveEntry> {
    var best : Null<SaveEntry> = null;
    for (info in campaigns()) {
      if (info.ended == true) continue;
      var entry = latest(info.id);
      if (entry != null && (best == null || entry.modified > best.modified)) best = entry;
    }
    return best;
  }

  // Steam Cloud'un eşitlediği boyut (kayıtlar ve sefer dosyası; yedek ve geçici dosya eşitlenmez).
  public function campaignSize(campaign : String) : Int {
    var folder = '$root/$campaign';
    if (!FileSystem.exists(folder)) return 0;
    var total = 0;
    for (name in FileSystem.readDirectory(folder))
      if (name == CAMPAIGN_FILE || Path.extension(name) == EXTENSION) total += FileSystem.stat('$folder/$name').size;
    return total;
  }

  public function oldestManual(campaign : String) : Null<SaveEntry> {
    var manual = saves(campaign).filter(entry -> entry.kind == MANUAL);
    return manual.length == 0 ? null : manual[manual.length - 1];
  }

  // Kaydı ve yedeğini siler. Yalnızca bu kökteki bir seferin .kayit dosyası; başka yol reddedilir.
  public function deleteSave(entry : SaveEntry) {
    if (Path.directory(entry.path) != '$root/${entry.campaign}' || Path.extension(entry.path) != EXTENSION) throw 'kayıt yolu değil: ${entry.path}';
    if (FileSystem.exists(entry.path)) FileSystem.deleteFile(entry.path);
    var backup = entry.path + SaveFile.BACKUP_SUFFIX;
    if (FileSystem.exists(backup)) FileSystem.deleteFile(backup);
  }

  // Başka kökte olup burada olmayan seferler (Steam'siz oynanan "yerel" seferler Steam hesabında).
  public function missingFrom(other : SaveSlots) : Array<CampaignInfo> {
    var here = [for (info in campaigns()) info.id => true];
    return other.campaigns().filter(info -> !here.exists(info.id));
  }

  // Seferi başka kökten kopyalar (sefer dosyası ve kayıtlar; yedek değil). Burada zaten varsa dokunmaz.
  public function copyCampaign(from : SaveSlots, id : String) : Bool {
    var source = '${from.root}/$id', target = '$root/$id';
    if (!FileSystem.exists('$source/$CAMPAIGN_FILE') || FileSystem.exists(target)) return false;
    makeDirectory(target);
    for (name in FileSystem.readDirectory(source))
      if (name == CAMPAIGN_FILE || Path.extension(name) == EXTENSION) sys.io.File.copy('$source/$name', '$target/$name');
    return true;
  }

  // Seferin kayıtları, en yenisi başta.
  public function saves(campaign : String) : Array<SaveEntry> {
    var folder = '$root/$campaign';
    if (!FileSystem.exists(folder)) return [];
    var found = [];
    for (name in FileSystem.readDirectory(folder)) {
      if (Path.extension(name) != EXTENSION) continue;
      var path = '$folder/$name';
      found.push({path: path, kind: kindOf(name), modified: FileSystem.stat(path).mtime.getTime(), campaign: campaign});
    }
    found.sort((a, b) -> a.modified < b.modified ? 1 : a.modified > b.modified ? -1 : 0);
    return found;
  }

  public function latest(campaign : String) : Null<SaveEntry> {
    return saves(campaign)[0];
  }

  public function manualCount(campaign : String) : Int {
    return saves(campaign).filter(entry -> entry.kind == MANUAL).length;
  }

  // Yazılacak dosya: elle tarihle yeni dosya, hızlı tek yuva, otomatik en eski oto_N, ironman tek yuva.
  public function pathFor(campaign : String, kind : String) : String {
    var folder = '$root/$campaign';
    makeDirectory(folder);
    return switch (kind) {
      case MANUAL:
        var base = '$folder/${MANUAL}_${DateTools.format(Date.now(), "%Y-%m-%d_%H%M%S")}', path = '$base.$EXTENSION', n = 2;
        while (FileSystem.exists(path)) path = '${base}_${n++}.$EXTENSION';
        path;
      case AUTO:
        var oldest = '$folder/${AUTO}_1.$EXTENSION', time = Math.POSITIVE_INFINITY;
        for (i in 1...AUTO_COUNT + 1) {
          var path = '$folder/${AUTO}_$i.$EXTENSION';
          if (!FileSystem.exists(path)) return path;
          var mtime = FileSystem.stat(path).mtime.getTime();
          if (mtime < time) {
            time = mtime;
            oldest = path;
          }
        }
        oldest;
      case QUICK, IRONMAN: '$folder/$kind.$EXTENSION';
      default: throw 'bilinmeyen kayıt türü: $kind';
    };
  }

  public static function kindOf(name : String) : String {
    var base = Path.withoutExtension(Path.withoutDirectory(name));
    for (kind in [MANUAL, AUTO, QUICK, IRONMAN]) if (base == kind || StringTools.startsWith(base, kind + "_")) return kind;
    return MANUAL;
  }

  static function makeDirectory(path : String) {
    if (!FileSystem.exists(path)) FileSystem.createDirectory(path);
  }
}
