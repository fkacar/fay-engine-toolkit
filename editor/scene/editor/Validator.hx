package scene.editor;

import scene.Entity;
import scene.SceneInstance;

typedef Issue = {
  var entity : Entity;
  var message : String;
}

// Kaydederken çalışır, kaydı engellemez: tasarımcı yarım işini de kaydedebilmeli.
class Validator {
  public var rules : Array<SceneInstance->Array<Issue>> = [];
  // Dünyanın bir kısmı yüklüyken başka hücredeki hedef kırık sanılmamalı.
  public var isPartial : Void->Bool = () -> false;

  var assetExists : String->Bool;

  public function new(assetExists : String->Bool) {
    this.assetExists = assetExists;
    rules.push(checkFields);
  }

  public function run(scene : SceneInstance) : Array<Issue> {
    var issues = [];
    for (rule in rules) issues = issues.concat(rule(scene));
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
