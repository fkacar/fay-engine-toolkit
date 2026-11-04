// Heaps'in matematik türlerini (h3d.Vector, h3d.Matrix) isteyen araç takımı testleri. Yorumlayıcıda Heaps'in
// model verisi (hxd.fmt.hmd) derlenmez; buradaki kodlar ona bağlanmaz. Oyunun kökünden: haxe libs/scene-toolkit/tests-heaps.hxml
class HeapsTests {
  static var failures = 0;
  static var checks = 0;

  static function check(condition : Bool, label : String, ?pos : haxe.PosInfos) {
    checks++;
    if (!condition) {
      failures++;
      Sys.println('HATA satır ${pos.lineNumber}: $label');
    }
  }

  static function equals(actual : Dynamic, expected : Dynamic, label : String, ?pos : haxe.PosInfos) {
    check(actual == expected, '$label: beklenen <$expected>, gelen <$actual>', pos);
  }

  // Tutamak tahmini: ince uç sap, Z saptan başa, X başın çıkıntısı; ters duran ve çapraz duran model de.
  static function testGripEstimate() {
    equals(scene.editor.GripEstimate.estimate([new h3d.Vector(), new h3d.Vector(0, 0, 1)]), null, "az köşe");
    // Sap: Z boyunca 0-0.75, yarıçap 0.015. Baş: üstte, +X'e 0.15 çıkıntı.
    function axe(flip : Bool, turn : Float) : Array<h3d.Vector> {
      var points = [];
      for (i in 0...76) for (a in 0...8) {
        var angle = a * Math.PI / 4;
        points.push(new h3d.Vector(Math.cos(angle) * 0.015, Math.sin(angle) * 0.015, i * 0.01));
      }
      for (i in 0...16) for (j in 0...16) points.push(new h3d.Vector(j * 0.01, (i % 2) * 0.01 - 0.005, 0.6 + i * 0.01));
      return [for (p in points) {
        var z = flip ? 0.75 - p.z : p.z;
        // turn: Y ekseni etrafında çevir (çapraz duran model).
        new h3d.Vector(p.x * Math.cos(turn) + z * Math.sin(turn), p.y, -p.x * Math.sin(turn) + z * Math.cos(turn));
      }];
    }
    function frame(spec : Dynamic) : h3d.Matrix {
      var m = new h3d.Matrix();
      m.initRotation(spec.rotation[0] * Math.PI / 180, spec.rotation[1] * Math.PI / 180, spec.rotation[2] * Math.PI / 180);
      return m;
    }
    var upright = scene.editor.GripEstimate.estimate(axe(false, 0));
    equals(upright.name, "tutamak", "tutamak adı");
    check(Math.abs(upright.offset[2] - 0.135) < 0.04 && Math.abs(upright.offset[0]) < 0.03, 'tutamak sapın alt ucundan %18 yukarıda: ${upright.offset}');
    var m = frame(upright);
    check(m._33 > 0.95, 'Z saptan başa (yukarı): ${m._31},${m._32},${m._33}');
    check(m._11 > 0.95, 'X başın çıkıntısına (+X): ${m._11},${m._12},${m._13}');
    var flipped = scene.editor.GripEstimate.estimate(axe(true, 0));
    check(Math.abs(flipped.offset[2] - (0.75 - 0.135)) < 0.04, 'ters duran: tutamak üstte: ${flipped.offset}');
    check(frame(flipped)._33 < -0.95, "ters duran: Z aşağı (başa doğru)");
    // Kılıç: ince kabza (0-0.15), Y'de geniş balçak, Y'de geniş yassı ağız. X ağzın genişliği boyunca (ağız yönü).
    var sword = [];
    for (i in 0...16) for (a in 0...8) sword.push(new h3d.Vector(Math.cos(a * Math.PI / 4) * 0.012, Math.sin(a * Math.PI / 4) * 0.012, i * 0.01));
    for (j in 0...17) sword.push(new h3d.Vector(0, j * 0.01 - 0.08, 0.155));
    for (i in 0...55) for (j in 0...11) for (k in 0...2) sword.push(new h3d.Vector(k * 0.008 - 0.004, j * 0.005 - 0.025, 0.16 + i * 0.01));
    var edge = frame(scene.editor.GripEstimate.estimate(sword));
    check(edge._33 > 0.95, 'kılıç: Z kabzadan uca: ${edge._31},${edge._32},${edge._33}');
    check(Math.abs(edge._12) > 0.9, 'kılıç: X ağzın genişliğinde (Y): ${edge._11},${edge._12},${edge._13}');
    var tilted = scene.editor.GripEstimate.estimate(axe(false, Math.PI / 4));
    var t = frame(tilted);
    check(t._31 > 0.6 && t._33 > 0.6, 'çapraz duran: Z modelin uzun ekseninde: ${t._31},${t._32},${t._33}');
  }

  static function main() {
    testGripEstimate();
    Sys.println('$checks kontrol, $failures hata');
    if (failures > 0) Sys.exit(1);
  }
}
