package scene.story;

import scene.Component;

// Oyunun hikâye izi: hangi tetikleyici çalıştı, hangi koşul tutmadı, hangi olay yayıldı, hangi
// diyalog düğümü geçildi, eşya ve değişkenler nasıl değişti. "Bu görev neden çalışmıyor" sorusunun
// oyundaki cevabı. Yalnızca istenince (editörden açılan oyunda) tutulur.
class StoryLog {
  public var entries(default, null) : Array<Dynamic> = [];
  public var time = 0.;   // oyun saniyesi

  public function new() {}

  public function add(type : String, data : Dynamic) {
    data.type = type;
    data.time = Math.round(time * 10) / 10;
    entries.push(data);
  }

  public static function fields(component : Component) : Dynamic {
    var values : Dynamic = {};
    for (field in component.describeFields()) Reflect.setField(values, field.label, component.readField(field.name));
    return values;
  }
}
