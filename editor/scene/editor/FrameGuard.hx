package scene.editor;

// Kare koruması: editörde bir karenin ortasında hata olursa editör kapanmaz.
//
// Dear ImGui yarım kalan bir kareyi sonraki karede fark edince uygulamayı durdurur (assert). Bunu iki katman önler,
// yerel tarafı `editor/native/imgui_guard.cpp` (hlimgui eklentisine derlenir, tools/build-hlimgui.*):
// - `run`: Bir panelin ya da bölümün çizimi korunur. Hata olursa yalnızca onun açtığı pencere ve yığınlar kapanır,
//   karenin geri kalanı çizilir; hata ve yığın izi geri döner.
// - `beforeFrame`: Uygulama `ImGui.newFrame`'den önce çağırır. Önceki kare korunmayan bir yerde yarıda kaldıysa ImGui
//   toparlanır; o karedeki hata metni (Heaps'in hata bildirimi yakalanır) geri döner.
// Uygulamanın yapacakları (oyunun `Main`'i örnek): açılışta `install`, `mainLoop` başında `beforeFrame` ve sonucu
// `Editor.frameFailed`'e, `update` ve `render` gövdesi `run` ile; çizimde hata olunca `frameOpen` ise ImGui yine çizilir.
class FrameGuard {
  static var lastError : Null<String>;
  static var installed = false;

  // Heaps'in hata bildirimini sarar: hata yine yazılır, metni `beforeFrame` için saklanır.
  public static function install() {
    if (installed) return;
    installed = true;
    var report = hxd.System.reportError;
    hxd.System.reportError = function(e : Dynamic) {
      lastError = describe(e);
      report(e);
    };
  }

  public static function beforeFrame() : Null<String> {
    if (!Native.recoverFrame()) return null;
    var message = lastError != null ? lastError : "bilinmeyen hata";
    lastError = null;
    return message;
  }

  // Çizimi korur. Hata olursa açtıkları kapanır ve hata metni döner; hata yoksa null.
  public static function run(draw : Void->Void) : Null<String> {
    var mark = Native.mark();
    try {
      draw();
    } catch (e : haxe.Exception) {
      Native.unwind(mark);
      return describe(e);
    }
    Native.release(mark);
    return null;
  }

  // Kare hâlâ açık mı (ImGui.render çağrılmadı): çizimde hata olunca arayüzü yine çizmek için.
  public static function frameOpen() : Bool {
    return Native.frameOpen();
  }

  public static function describe(e : Dynamic) : String {
    if (Std.isOfType(e, haxe.Exception)) {
      var exception : haxe.Exception = e;
      return exception.message + haxe.CallStack.toString(exception.stack);
    }
    return Std.string(e);
  }
}

private class Native {
  @:hlNative("hlimgui", "guard_mark") public static function mark() : Int return -1;

  @:hlNative("hlimgui", "guard_release") public static function release(index : Int) : Void {}

  @:hlNative("hlimgui", "guard_unwind") public static function unwind(index : Int) : Void {}

  @:hlNative("hlimgui", "guard_recover_frame") public static function recoverFrame() : Bool return false;

  @:hlNative("hlimgui", "guard_frame_open") public static function frameOpen() : Bool return false;
}
