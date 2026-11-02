package scene.data;

// Sahne dosyasını kodun bildiği bileşenlerle karşılaştırır.
class SceneSchema {
  var components = new Map<String, Map<String, String>>();
  var choices = new Map<String, Map<String, Array<String>>>();
  var references = new Map<String, Map<String, String>>();
  var refExists : Null<(String, String) -> Bool>;
  // Tablo satırı, diyalog ve prefab dosyası içeriktir: tasarımcı derleme yapmadan değiştirir, iki kişinin
  // birleştirmesi de kırabilir. Derlemeyi durdurursa ekip editörü açıp düzeltemez, bu yüzden uyarıdır.
  public var warnings(default, null) : Array<String> = [];

  public function new() {}

  // ids: kimlik ve eski kimlikler. fields: alan adı (eskileri dahil) ve tipi.
  // options: `@:choice` alanlarının geçerli değerleri.
  // refs: `@:ref` alanlarının tabloları.
  public function add(ids : Array<String>, fields : Map<String, String>, ?options : Map<String, Array<String>>, ?refs : Map<String, String>) {
    for (id in ids) {
      components.set(id, fields);
      if (options != null) choices.set(id, options);
      if (refs != null) references.set(id, refs);
    }
  }

  // refExists: tablo ve kimlik verilir, satır varsa true.
  public function check(text : String, ?prefabExists : String->Bool, ?refExists : (String, String) -> Bool) : Array<String> {
    this.refExists = refExists;
    warnings = [];
    var data = try SceneFormat.read(text) catch (e : Dynamic) return ['Dosya okunamadı: $e'];
    var problems = [];
    for (entity in data.entities) {
      if (entity.prefab != null && prefabExists != null && !prefabExists(entity.prefab))
        warnings.push('${entity.name}: "${entity.prefab}" prefab dosyası yok. Oyunda bu nesne boş kalır, editörde Uyarılar panelinden düzelt.');
      for (change in entity.overrides) {
        var parts = Prefabs.componentField(change.field);
        if (parts == null) continue;
        var fields = components.get(parts.type);
        if (fields == null) problems.push('${entity.name}: "${parts.type}" bileşeni kodda yok. Kimlik değiştiyse sınıfa @:formerly("${parts.type}") ekle.');
        else checkField(problems, entity.name, parts.type, parts.name, change.value);
      }
      for (component in entity.components) {
        var fields = components.get(component.type);
        if (fields == null) {
          problems.push('${entity.name}: "${component.type}" bileşeni kodda yok. Kimlik değiştiyse sınıfa @:formerly("${component.type}") ekle.');
          continue;
        }
        for (name => value in component.fields) checkField(problems, entity.name, component.type, name, value);
      }
    }
    return problems;
  }

  function checkField(problems : Array<String>, entity : String, type : String, name : String, value : Dynamic) {
    var kind = components.get(type).get(name);
    if (kind == null) {
      problems.push('$entity: "$type" bileşeninde "$name" alanı kodda yok. Ad değiştiyse alana @:formerly("$name") ekle.');
      return;
    }
    if (!matches(kind, value)) {
      problems.push('$entity: "$type.$name" alanı $kind olmalı, dosyada: $value');
      return;
    }
    var allowed = choices.exists(type) ? choices.get(type).get(name) : null;
    if (allowed != null && allowed.indexOf(value) < 0)
      problems.push('$entity: "$type.$name" değeri "$value" seçeneklerde yok (${allowed.join(", ")}). Seçeneği koda geri ekle veya dosyadaki değeri değiştir.');
    var table = references.exists(type) ? references.get(type).get(name) : null;
    if (table != null && refExists != null && value != "" && !refExists(table, value))
      warnings.push(table.charAt(0) == "@" ? '$entity: "$type.$name" değeri "$value" bulunamadı. Editörde Uyarılar panelinden düzelt.'
        : '$entity: "$type.$name" değeri "$value" $table tablosunda yok. Editörde Uyarılar panelinden düzelt.');
  }

  static function matches(kind : String, value : Dynamic) {
    return switch (kind) {
      case "Float": Std.isOfType(value, Float);
      case "Int": Std.isOfType(value, Int);
      case "Bool": Std.isOfType(value, Bool);
      case "String": Std.isOfType(value, String);
      case "Array<String>", "Array<Float>": Std.isOfType(value, Array);
      default: true;
    };
  }
}
