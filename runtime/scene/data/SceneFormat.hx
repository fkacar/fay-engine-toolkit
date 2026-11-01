package scene.data;

import haxe.Int64;
import scene.data.SceneData;

// Sahne dosyası okuma ve yazma. Çıktı deterministiktir: aynı sahne her sistemde ve her
// kayıtta aynı dosyayı üretir, git'te sahte fark oluşmaz.
class SceneFormat {
  public static inline var VERSION = 1;

  static inline var PRECISION = 100000.0;
  static inline var FRACTION_DIGITS = 5;

  // Dizin, yükseltilen sürümdür: MIGRATIONS[1] dosyayı 1'den 2'ye taşır.
  static var MIGRATIONS : Array<Dynamic->Void> = [null];

  public static function read(text : String) : SceneData {
    return parse(haxe.Json.parse(text), MIGRATIONS);
  }

  public static function write(data : SceneData) : String {
    var out = new StringBuf();
    out.add('{\n  "version": ${data.version},\n  "entities": [');
    for (i in 0...data.entities.length) {
      if (i > 0) out.add(",");
      writeEntity(out, data.entities[i]);
    }
    out.add(data.entities.length == 0 ? "]\n}\n" : "\n  ]\n}\n");
    return out.toString();
  }

  // Kayan nokta metni sisteme göre değişebilir, bu yüzden sayı elle biçimlendirilir.
  public static function number(value : Float) : String {
    if (Math.isNaN(value) || !Math.isFinite(value)) throw 'Sahneye yazılamayan sayı: $value';
    var scaled = Math.fround(Math.abs(value) * PRECISION);
    var whole = Math.ffloor(scaled / PRECISION);
    var fraction = Std.int(scaled - whole * PRECISION);
    var text = Int64.toStr(Int64.fromFloat(whole));
    if (fraction > 0) {
      var digits = StringTools.lpad(Std.string(fraction), "0", FRACTION_DIGITS);
      while (StringTools.endsWith(digits, "0")) digits = digits.substr(0, digits.length - 1);
      text += "." + digits;
    }
    return value < 0 && scaled > 0 ? "-" + text : text;
  }

  public static function parse(raw : Dynamic, migrations : Array<Dynamic->Void>) : SceneData {
    var declared : Null<Int> = raw.version;
    if (declared == null) throw "Sahne dosyasında version alanı yok";
    var version : Int = declared;
    if (version > VERSION) throw 'Sahne bu derlemeden yeni: dosya v$version, derleme v$VERSION';
    while (version < VERSION) {
      migrations[version](raw);
      version++;
    }

    var data = new SceneData(VERSION);
    var entities : Array<Dynamic> = raw.entities;
    for (item in entities) data.entities.push(parseEntity(item));
    return data;
  }

  static function parseEntity(raw : Dynamic) : EntityData {
    var entity = new EntityData(raw.id, raw.name);
    entity.parent = raw.parent;
    if (raw.active != null) entity.active = raw.active;
    if (raw.position != null) entity.position = raw.position;
    if (raw.rotation != null) entity.rotation = raw.rotation;
    if (raw.scale != null) entity.scale = raw.scale;
    var components : Array<Dynamic> = raw.components;
    if (components != null)
      for (item in components) {
        var component = new ComponentData(item.type);
        var fields : Dynamic = item.fields;
        if (fields != null)
          for (name in Reflect.fields(fields)) component.fields.set(name, Reflect.field(fields, name));
        entity.components.push(component);
      }
    return entity;
  }

  static function writeEntity(out : StringBuf, entity : EntityData) {
    out.add('\n    {\n      "id": ${quote(entity.id)},\n      "name": ${quote(entity.name)},');
    if (entity.parent != null) out.add('\n      "parent": ${quote(entity.parent)},');
    if (!entity.active) out.add('\n      "active": false,');
    out.add('\n      "position": ${vector(entity.position)},');
    out.add('\n      "rotation": ${vector(entity.rotation)},');
    out.add('\n      "scale": ${vector(entity.scale)},');
    out.add('\n      "components": [');
    for (i in 0...entity.components.length) {
      if (i > 0) out.add(",");
      writeComponent(out, entity.components[i]);
    }
    out.add(entity.components.length == 0 ? "]\n    }" : "\n      ]\n    }");
  }

  static function writeComponent(out : StringBuf, component : ComponentData) {
    out.add('\n        {\n          "type": ${quote(component.type)},\n          "fields": {');
    var names = sorted([for (name in component.fields.keys()) name]);
    for (i in 0...names.length) {
      if (i > 0) out.add(",");
      var value = component.fields.get(names[i]);
      out.add('\n            ${quote(names[i])}: ${writeValue(value)}');
    }
    out.add(names.length == 0 ? "}\n        }" : "\n          }\n        }");
  }

  // Tanınmayan alanlar da korunduğu için dizi ve nesneler de yazılabilir.
  static function writeValue(value : Dynamic) : String {
    if (value == null) return "null";
    if (Std.isOfType(value, Bool)) return value ? "true" : "false";
    if (Std.isOfType(value, String)) return quote(value);
    if (Std.isOfType(value, Float)) return number(value);
    if (Std.isOfType(value, Array)) {
      var items : Array<Dynamic> = value;
      return "[" + [for (item in items) writeValue(item)].join(", ") + "]";
    }
    var names = sorted(Reflect.fields(value));
    return "{" + [for (name in names) quote(name) + ": " + writeValue(Reflect.field(value, name))].join(", ") + "}";
  }

  static function vector(values : Array<Float>) {
    return "[" + [for (value in values) number(value)].join(", ") + "]";
  }

  static function quote(text : String) {
    return haxe.Json.stringify(text);
  }

  static function sorted(names : Array<String>) {
    names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
    return names;
  }
}
