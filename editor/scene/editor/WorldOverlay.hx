package scene.editor;

import imgui.ImGui;
import imgui.types.ImDrawList;
import scene.Overlay;

// Bileşenlerin yardımcı çizimlerini dünya uzayından ekrana çevirip ImGui listesine yazar.
class WorldOverlay implements Overlay {
  static inline var LINE_WIDTH = 2.;
  static inline var LABEL_SHADOW = 0xD0000000;

  var view : h3d.Camera;
  var list : ImDrawList;
  var ahead : Vec3;
  var eye : Vec3;
  var thickness = 1.;

  public function new(view : h3d.Camera) {
    this.view = view;
  }

  public function begin(list : ImDrawList, ahead : Vec3, density : Float) {
    this.list = list;
    this.ahead = ahead;
    eye = new Vec3(view.pos.x, view.pos.y, view.pos.z);
    thickness = LINE_WIDTH * density;
  }

  public function line(x1 : Float, y1 : Float, z1 : Float, x2 : Float, y2 : Float, z2 : Float, color : Int) {
    if (!isInFront(x1, y1, z1) || !isInFront(x2, y2, z2)) return;
    var a = project(x1, y1, z1), b = project(x2, y2, z2);
    list.addLine({x: a.x, y: a.y}, {x: b.x, y: b.y}, color, thickness);
  }

  public function label(x : Float, y : Float, z : Float, text : String, color : Int) {
    if (!isInFront(x, y, z)) return;
    var at = project(x, y, z);
    var size = ImGui.calcTextSize(text);
    var x = at.x - size.x * 0.5, y = at.y - size.y;
    list.addText({x: x + 1, y: y + 1}, LABEL_SHADOW, text);
    list.addText({x: x, y: y}, color, text);
  }

  inline function isInFront(x : Float, y : Float, z : Float) {
    return new Vec3(x, y, z).sub(eye).dot(ahead) > view.zNear;
  }

  inline function project(x : Float, y : Float, z : Float) {
    var engine = h3d.Engine.getCurrent();
    return view.project(x, y, z, engine.width, engine.height);
  }
}
