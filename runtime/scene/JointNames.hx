package scene;

// İskeletlerin standart eklem adları (Mixamo düzeni: Hips, Spine, LeftHand...) ve bilinen başka adlandırmalar:
// `mixamorig:` öneki, Rigify (`DEF-hips`, `DEF-hand.L`; Quaternius UAL, Blender). İçe aktarma eşlemeyi bir kez
// çözer ve <ad>.model.json'a yazar (joints); oyun ve içe aktarıcı aynı eşlemeyi kullanır, yeni iskelet için kod
// değişmez. Tanınmayan iskelette ayar dosyasının joints alanı elle eşleme verir (standart ad → gerçek ad).
class JointNames {
  public static var STANDARD = [
    "Hips", "Spine", "Spine1", "Spine2", "Neck", "Head",
    "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand",
    "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase", "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
  ];

  // Rigify kemik adları (yan eki .L / .R ayrıca eklenir).
  static var RIGIFY = [
    "Hips" => "hips", "Spine" => "spine.001", "Spine1" => "spine.002", "Spine2" => "spine.003", "Neck" => "neck", "Head" => "head",
    "Shoulder" => "shoulder", "Arm" => "upper_arm", "ForeArm" => "forearm", "Hand" => "hand",
    "UpLeg" => "thigh", "Leg" => "shin", "Foot" => "foot", "ToeBase" => "toe",
  ];

  // Standart ad → iskeletteki ad, bulunanlar. overrides (standart → gerçek) önce gelir; iskelette yoksa atlanır.
  public static function resolve(names : Array<String>, ?overrides : Map<String, String>) : Map<String, String> {
    var have = [for (name in names) name => true];
    var found = new Map<String, String>();
    for (standard in STANDARD) {
      var wanted = overrides == null ? null : overrides.get(standard);
      if (wanted != null && have.exists(wanted)) {
        found.set(standard, wanted);
        continue;
      }
      for (candidate in candidates(standard)) if (have.exists(candidate)) {
        found.set(standard, candidate);
        break;
      }
    }
    return found;
  }

  // Eşlemede varsa gerçek ad, yoksa standart adın kendisi (eski modeller, eşlemesiz bilgi dosyası).
  public static function actual(map : Null<Map<String, String>>, standard : String) : String {
    var name = map == null ? null : map.get(standard);
    return name == null ? standard : name;
  }

  // Bilgi dosyasındaki joints nesnesinden eşleme (JSON nesnesi).
  public static function fromData(data : Dynamic) : Null<Map<String, String>> {
    if (data == null) return null;
    var map = new Map<String, String>();
    for (field in Reflect.fields(data)) {
      var value : Dynamic = Reflect.field(data, field);
      if (Std.isOfType(value, String)) map.set(field, value);
    }
    return map;
  }

  public static function toData(map : Map<String, String>) : Dynamic {
    var data = {};
    for (standard in STANDARD) if (map.exists(standard)) Reflect.setField(data, standard, map.get(standard));
    return data;
  }

  static function candidates(standard : String) : Array<String> {
    var list = [standard, "mixamorig:" + standard, "mixamorig_" + standard];
    var side = StringTools.startsWith(standard, "Left") ? "L" : StringTools.startsWith(standard, "Right") ? "R" : null;
    var base = side == null ? standard : standard.substr(side == "L" ? 4 : 5);
    var rig = RIGIFY.get(base);
    if (rig != null) for (prefix in ["DEF-", "ORG-", ""]) list.push(prefix + rig + (side == null ? "" : "." + side));
    return list;
  }
}
