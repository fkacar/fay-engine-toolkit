package scene.editor;

import scene.Entity;
import scene.SceneInstance;

typedef Issue = {
  var entity : Null<Entity>;  // diyalog gibi sahne dışı sorunlarda yok
  var message : String;
  @:optional var dialog : String;
  @:optional var node : Int;
}

// Kaydederken çalışır, kaydı engellemez: tasarımcı yarım işini de kaydedebilmeli.
class Validator {
  public var rules : Array<SceneInstance->Array<Issue>> = [];
  // Dünyanın bir kısmı yüklüyken başka hücredeki hedef kırık sanılmamalı.
  public var isPartial : Void->Bool = () -> false;
  // Tablo ve kimlik verilir, satır varsa true.
  public var refExists : (String, String) -> Bool = (table, id) -> true;
  public var dialogExists : String->Bool = _ -> true;

  var assetExists : String->Bool;

  public function new(assetExists : String->Bool) {
    this.assetExists = assetExists;
    rules.push(checkFields);
    rules.push(checkComponents);
  }

  public function run(scene : SceneInstance) : Array<Issue> {
    var issues = [];
    for (rule in rules) issues = issues.concat(rule(scene));
    return issues;
  }

  // Bileşenin kendi kuralları: eksik eylem, seçilmemiş eşya gibi.
  function checkComponents(scene : SceneInstance) {
    var issues : Array<Issue> = [];
    for (entity in scene.entities)
      for (component in entity.components)
        for (message in component.issues()) issues.push({entity: entity, message: '${entity.name}: $message'});
    return issues;
  }

  function checkFields(scene : SceneInstance) {
    var issues : Array<Issue> = [];
    for (entity in scene.entities)
      for (component in entity.components)
        for (field in component.describeFields()) {
          switch (field.hint) {
            case HChoice(options):
              var choice : String = component.readField(field.name);
              if (options.indexOf(choice) < 0)
                issues.push({entity: entity, message: '${entity.name}: geçersiz seçenek "$choice" (${field.label})'});
              continue;
            case HDialog:
              var id : String = component.readField(field.name);
              if (id != null && id != "" && !dialogExists(id))
                issues.push({entity: entity, message: '${entity.name}: "$id" diyaloğu yok (${field.label})'});
              continue;
            case HRef(table):
              var id : String = component.readField(field.name);
              if (id != null && id != "" && !refExists(table, id))
                issues.push({entity: entity, message: '${entity.name}: $table tablosunda "$id" yok (${field.label})'});
              continue;
            default:
          }
          var isFile = field.hint == HAsset || field.hint == HPrefab;
          if (!isFile && field.hint != HEntity) continue;
          var value : String = component.readField(field.name);
          if (value == null || value == "") continue;
          if (isFile && !assetExists(value))
            issues.push({entity: entity, message: '${entity.name}: eksik asset "$value" (${field.label})'});
          if (field.hint == HEntity && scene.find(value) == null && !isPartial())
            issues.push({entity: entity, message: '${entity.name}: kırık referans ${field.label} ($value)'});
        }
    return issues;
  }
}
