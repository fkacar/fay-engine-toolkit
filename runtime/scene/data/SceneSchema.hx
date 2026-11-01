package scene.data;

// Sahne dosyasını kodun bildiği bileşenlerle karşılaştırır.
class SceneSchema {
  var components = new Map<String, Map<String, String>>();

  public function new() {}

  // ids: kimlik ve eski kimlikler. fields: alan adı (eskileri dahil) ve tipi.
  public function add(ids : Array<String>, fields : Map<String, String>) {
    for (id in ids) components.set(id, fields);
  }

  public function check(text : String) : Array<String> {
    var data = try SceneFormat.read(text) catch (e : Dynamic) return ['Dosya okunamadı: $e'];
    var problems = [];
    for (entity in data.entities)
      for (component in entity.components) {
        var fields = components.get(component.type);
        if (fields == null) {
          problems.push('${entity.name}: "${component.type}" bileşeni kodda yok. Kimlik değiştiyse sınıfa @:formerly("${component.type}") ekle.');
          continue;
        }
        for (name => value in component.fields) {
          var kind = fields.get(name);
          if (kind == null)
            problems.push('${entity.name}: "${component.type}" bileşeninde "$name" alanı kodda yok. Ad değiştiyse alana @:formerly("$name") ekle.');
          else if (!matches(kind, value))
            problems.push('${entity.name}: "${component.type}.$name" alanı $kind olmalı, dosyada: $value');
        }
      }
    return problems;
  }

  static function matches(kind : String, value : Dynamic) {
    return switch (kind) {
      case "Float": Std.isOfType(value, Float);
      case "Int": Std.isOfType(value, Int);
      case "Bool": Std.isOfType(value, Bool);
      case "String": Std.isOfType(value, String);
      default: true;
    };
  }
}
