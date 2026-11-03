package scene.editor;

import hxd.fmt.fbx.Data.FbxNode;
import hxd.fmt.fbx.Data.FbxTools;

// Heaps bir kemiğin X, Y, Z eğrilerini yalnızca ilk eğrinin anahtar zamanlarıyla okur. Anahtarları
// eksen eksen azaltılmış dosyada (Meshy, Blender'ın sadeleştirmesi) eksenler kayar, eksik kareler
// sıfır olur: karakter yere gömülür, yana kayar. Okumadan önce aynı düğümün eğrileri ortak zamanlara
// doğrusal olarak yeniden örneklenir; anahtarları zaten aynı olan eğrilere dokunulmaz.
class FbxCurves {
  public static function sync(root : FbxNode) : Int {
    var curves = new Map<Int, FbxNode>();
    for (curve in FbxTools.getAll(root, "Objects.AnimationCurve")) curves.set(FbxTools.getId(curve), curve);
    var groups = new Map<Int, Array<FbxNode>>();
    for (connection in FbxTools.getAll(root, "Connections.C")) {
      if (connection.props.length < 4) continue;
      var curve = curves.get(FbxTools.toInt(connection.props[1]));
      if (curve == null) continue;
      var parent = FbxTools.toInt(connection.props[2]);
      if (!groups.exists(parent)) groups.set(parent, []);
      groups.get(parent).push(curve);
    }
    var changed = 0;
    for (group in groups) {
      if (group.length < 2) continue;
      var seen = new Map<String, Bool>(), times : Array<Float> = [];
      for (curve in group)
        for (time in FbxTools.getFloats(FbxTools.get(curve, "KeyTime"))) {
          var key = Std.string(time);
          if (seen.exists(key)) continue;
          seen.set(key, true);
          times.push(time);
        }
      times.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
      for (curve in group) {
        var own = FbxTools.getFloats(FbxTools.get(curve, "KeyTime"));
        if (own.length == times.length) continue;
        var values = FbxTools.getFloats(FbxTools.get(curve, "KeyValueFloat"));
        FbxTools.get(curve, "KeyTime").props[0] = PFloats(times.copy());
        FbxTools.get(curve, "KeyValueFloat").props[0] = PFloats([for (time in times) sample(own, values, time)]);
        changed++;
      }
    }
    return changed;
  }

  static function sample(times : Array<Float>, values : Array<Float>, time : Float) : Float {
    if (times.length == 0) return 0;
    if (time <= times[0]) return values[0];
    for (i in 1...times.length)
      if (time <= times[i]) {
        var t = (time - times[i - 1]) / (times[i] - times[i - 1]);
        return values[i - 1] + (values[i] - values[i - 1]) * t;
      }
    return values[values.length - 1];
  }
}
