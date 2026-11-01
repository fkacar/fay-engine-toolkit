package scene;

import hxd.Key;

// Pencere odağı giderken bırakılan tuşun olayı gelmez (Cmd+Tab, Alt+Tab) ve Heaps tuşu
// sonsuza dek basılı sanır. Odak kaybında tüm tuşlar bırakılmış sayılır.
class FocusGuard {
  public static function install() {
    hxd.Window.getInstance().addEventTarget(e -> if (e.kind == EFocusLost) @:privateAccess Key.keyPressed = []);
  }
}
