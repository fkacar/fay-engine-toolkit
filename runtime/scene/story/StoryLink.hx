package scene.story;

// Görev bağlantısı: bileşen veya diyalog düğümü bir olayı bekler ya da yayar, bir değişkeni okur ya da
// ayarlar, bir eşyayı ister ya da verir. Uyarılar ve ajanın görev incelemesi bunları eşleştirir.
typedef StoryLink = {
  var kind : String;
  var name : String;
}

class StoryLinks {
  public static inline var LISTENS = "listens";
  public static inline var EMITS = "emits";
  public static inline var READS = "reads";
  public static inline var SETS = "sets";
  public static inline var NEEDS = "needs";
  public static inline var GIVES = "gives";
  public static inline var TAKES = "takes";
  public static inline var STARTS = "starts";
  public static inline var STANDING = "standing";

  public static function ofNode(node : Dialog.DialogNode) : Array<StoryLink> {
    return switch (node.type) {
      case Dialog.EVENT if (node.event != null && node.event != ""): [{kind: EMITS, name: node.event}];
      case Dialog.CONDITION if (node.name != null && node.name != ""): [{kind: node.kind == Dialog.ITEM ? NEEDS : READS, name: node.name}];
      default: [];
    };
  }

  // Aynı adın karşı tarafı: bekleyen için yayan, okuyan için ayarlayan.
  public static function family(kind : String) : Array<String> {
    return switch (kind) {
      case LISTENS, EMITS: [LISTENS, EMITS];
      case READS, SETS: [READS, SETS];
      case NEEDS, GIVES, TAKES: [NEEDS, GIVES, TAKES];
      case STARTS: [STARTS];
      default: [kind];
    };
  }
}
