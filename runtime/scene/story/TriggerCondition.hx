package scene.story;

// Tetikleyici nesnesine eklenir. Bütün koşullar sağlanırsa eylemler sırayla çalışır.
class TriggerCondition extends Component {
  public static inline var CATEGORY = "Koşul";

  public function passes(story : Story) : Bool {
    return true;
  }

  override public function category() : String {
    return CATEGORY;
  }
}
