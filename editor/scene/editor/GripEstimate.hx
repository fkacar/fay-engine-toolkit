package scene.editor;

import h3d.Vector;
import scene.editor.ImportSettings.SocketSpec;

// İskeletsiz modelin (silah, alet) tutamak (avucun tuttuğu yer) tahmini, köşelerden. Uzun eksen köşelerin temel
// bileşenidir (çapraz duran model de olur); ince ucu sap sayılır, tutamak o uçtan boyun GRIP_FRACTION'ı kadar
// içeride, sapın kesit ortasında. Tutamağın ekseni: Z saptan başa, X başın (balta ağzı, çekiç başı) çıkıntı yönü.
// Tahmin yanlışsa ayar dosyasında "tutamak" takma noktası elle verilir.
class GripEstimate {
  public static inline var GRIP = "tutamak";
  static inline var GRIP_FRACTION = 0.18;
  static inline var END_FRACTION = 0.2;

  public static function estimate(points : Array<Vector>) : Null<SocketSpec> {
    if (points.length < 4) return null;
    // Uzun eksen: köşelerin temel bileşeni (çapraz duran model de doğru eksen alır).
    var center = centroid(points);
    var axis = principal(points, center);
    var low = 1e30, high = -1e30;
    for (p in points) {
      var t = p.sub(center).dot(axis);
      low = Math.min(low, t);
      high = Math.max(high, t);
    }
    var long = high - low;
    if (long < 1e-6) return null;
    function along(p : Vector) return (p.sub(center).dot(axis) - low) / long;
    function across(p : Vector) : Vector {
      var d = p.sub(center);
      return d.sub(axis.scaled(d.dot(axis)));
    }
    // İki uç dilimin kesit yayılımı: ince olan sap.
    function slice(from : Float, to : Float) : {count : Int, radius : Float, center : Vector, points : Array<Vector>} {
      var inside = points.filter(p -> {
        var t = along(p);
        t >= from && t <= to;
      });
      var middle = centroid(inside);
      var radius = 0.;
      var offset = across(middle);
      for (p in inside) radius = Math.max(radius, across(p).sub(offset).length());
      return {count: inside.length, radius: radius, center: middle, points: inside};
    }
    var start = slice(0, END_FRACTION), end = slice(1 - END_FRACTION, 1);
    var handleAtStart = start.radius <= end.radius;
    var t = handleAtStart ? GRIP_FRACTION : 1 - GRIP_FRACTION;
    var cut = slice(t - 0.05, t + 0.05);
    if (cut.count == 0) return null;
    // Tutamak: sapın kesit ortası, eksen üstünde t noktasında.
    var grip = center.add(axis.scaled(low + t * long)).add(across(cut.center));
    // Z: saptan başa. X: başın kesitte en geniş yayıldığı yön (balta ağzı, kılıcın ağzı), işareti başın sap
    // çizgisinden çıkıntısından (baltada ağız tarafı). Baş yuvarlaksa (topuz) çıkıntı, o da yoksa eksene dik bir yön.
    var z = handleAtStart ? axis.clone() : axis.scaled(-1);
    var head = handleAtStart ? end : start;
    var offsets = [for (p in head.points) across(p).sub(across(cut.center))];
    var protrusion = centroid(offsets);
    var x = principal(offsets, protrusion);
    x = x.sub(z.scaled(x.dot(z)));
    var spread = 0.;
    for (o in offsets) spread = Math.max(spread, Math.abs(o.sub(protrusion).dot(x.normalized())));
    if (x.length() < 1e-6 || spread < head.radius * 0.6) x = protrusion.clone();
    else if (x.dot(protrusion) < 0) x = x.scaled(-1);
    x = x.sub(z.scaled(x.dot(z)));
    if (x.length() < long * 0.01) x = Math.abs(z.z) < 0.9 ? new Vector(0, 0, 1).cross(z) : new Vector(1, 0, 0).cross(z);
    x = x.sub(z.scaled(x.dot(z)));
    x.normalize();
    var y = z.cross(x);
    y.normalize();
    var m = new h3d.Matrix();
    m.identity();
    m._11 = x.x; m._12 = x.y; m._13 = x.z;
    m._21 = y.x; m._22 = y.y; m._23 = y.z;
    m._31 = z.x; m._32 = z.y; m._33 = z.z;
    var euler = m.getEulerAngles();
    return {name: GRIP, joint: "", offset: [round(grip.x), round(grip.y), round(grip.z)],
      rotation: [degrees(euler.x), degrees(euler.y), degrees(euler.z)]};
  }

  // Kovaryansın en büyük özvektörü (üs yöntemi); birim vektör.
  static function principal(points : Array<Vector>, center : Vector) : Vector {
    var c = [0., 0., 0., 0., 0., 0.];
    for (p in points) {
      var d = p.sub(center);
      c[0] += d.x * d.x; c[1] += d.x * d.y; c[2] += d.x * d.z;
      c[3] += d.y * d.y; c[4] += d.y * d.z; c[5] += d.z * d.z;
    }
    var v = new Vector(1, 1, 1);
    for (_ in 0...50) {
      var next = new Vector(c[0] * v.x + c[1] * v.y + c[2] * v.z, c[1] * v.x + c[3] * v.y + c[4] * v.z, c[2] * v.x + c[4] * v.y + c[5] * v.z);
      if (next.length() < 1e-12) return new Vector(0, 0, 1);
      next.normalize();
      v = next;
    }
    return v;
  }

  static function centroid(points : Array<Vector>) : Vector {
    var sum = new Vector();
    for (p in points) sum = sum.add(p);
    return points.length == 0 ? sum : sum.scaled(1 / points.length);
  }

  static function degrees(radians : Float) : Float {
    var value = Math.round(radians * 1800 / Math.PI) / 10;
    return value == 0 ? 0 : value;
  }

  static function round(value : Float) : Float {
    return Math.round(value * 1000) / 1000;
  }
}
