package scene.editor;

import hxd.Key;

// Editörün kamerası. Oyunun kamerasından bağımsızdır, arazi veya oyun kuralı bilmez.
class EditorCamera {
  public static inline var MIN_SPEED = 0.5;
  public static inline var MAX_SPEED = 500.;

  static inline var LOOK_SPEED = 0.0045;  // rad/nokta
  static inline var MAX_PITCH = 1.54;
  static inline var DOLLY_STEP = 0.14;    // tekerlek adımında uzaklığın katı
  static inline var SPEED_STEP = 1.2;
  static inline var BOOST = 3.;
  static inline var MIN_DISTANCE = 1.;
  static inline var FOCUS_MARGIN = 3.6;
  static inline var FOCUS_SMOOTHING = 12.;

  public var speed = 20.;                       // m/sn
  public var distance(default, null) = 40.;     // orbit bu kadar öndeki noktanın etrafında döner

  var camera : h3d.Camera;
  var position : Vec3;
  var yaw : Float;
  var pitch : Float;
  var goal : Null<Vec3>;

  public function new(camera : h3d.Camera) {
    this.camera = camera;
    position = new Vec3(camera.pos.x, camera.pos.y, camera.pos.z);
    var view = new Vec3(camera.target.x, camera.target.y, camera.target.z).sub(position);
    distance = Math.max(view.length(), MIN_DISTANCE);
    yaw = Math.atan2(view.y, view.x);
    pitch = Math.asin(view.z / Math.max(view.length(), 1e-6));
  }

  public function forward() {
    var flat = Math.cos(pitch);
    return new Vec3(Math.cos(yaw) * flat, Math.sin(yaw) * flat, Math.sin(pitch));
  }

  public function right() {
    return new Vec3(Math.sin(yaw), -Math.cos(yaw), 0);
  }

  public function look(dx : Float, dy : Float) {
    goal = null;
    yaw -= dx * LOOK_SPEED;
    pitch = Math.max(-MAX_PITCH, Math.min(MAX_PITCH, pitch - dy * LOOK_SPEED));
  }

  // Bakılan noktayı yerinde tutarak döner.
  public function orbit(dx : Float, dy : Float) {
    var pivot = position.add(forward().scale(distance));
    look(dx, dy);
    position = pivot.sub(forward().scale(distance));
  }

  public function pan(dx : Float, dy : Float, screenHeight : Float) {
    goal = null;
    var unit = 2 * distance * Math.tan(camera.fovY * Math.PI / 360) / screenHeight;
    var up = right().cross(forward());
    position = position.sub(right().scale(dx * unit)).add(up.scale(dy * unit));
  }

  public function dolly(wheel : Float) {
    goal = null;
    var step = Math.max(distance, MIN_DISTANCE * 4) * DOLLY_STEP * wheel;
    position = position.add(forward().scale(step));
    distance = Math.max(distance - step, MIN_DISTANCE);
  }

  public function fly(dt : Float) {
    var right = axis(Key.D, Key.A), ahead = axis(Key.W, Key.S), rise = axis(Key.E, Key.Q);
    if (right == 0 && ahead == 0 && rise == 0) return;
    goal = null;
    var step = speed * dt * (Key.isDown(Key.SHIFT) ? BOOST : 1);
    position = position.add(forward().scale(ahead * step)).add(this.right().scale(right * step)).add(new Vec3(0, 0, rise * step));
  }

  public function changeSpeed(wheel : Float) {
    speed = Math.max(MIN_SPEED, Math.min(MAX_SPEED, speed * Math.pow(SPEED_STEP, wheel)));
  }

  public function setDistance(value : Float) {
    distance = Math.max(value, MIN_DISTANCE);
  }

  public function focus(center : Vec3, radius : Float) {
    distance = Math.max(radius * FOCUS_MARGIN, MIN_DISTANCE * 4);
    goal = center.sub(forward().scale(distance));
  }

  public function update(dt : Float) {
    if (goal != null) {
      position = position.add(goal.sub(position).scale(1 - Math.exp(-FOCUS_SMOOTHING * dt)));
      if (goal.sub(position).length() < 0.01) goal = null;
    }
    var view = position.add(forward());
    camera.pos.set(position.x, position.y, position.z);
    camera.target.set(view.x, view.y, view.z);
    camera.update();
  }

  inline function axis(positive : Int, negative : Int) {
    return (Key.isDown(positive) ? 1 : 0) - (Key.isDown(negative) ? 1 : 0);
  }
}
