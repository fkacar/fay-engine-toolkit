package scene.story;

// Tetikleyici nesnesine eklenir. Bütün koşullar sağlanırsa eylemler sırayla çalışır.
class TriggerCondition extends Component {
  public function passes(story : Story) : Bool {
    return true;
  }

  override public function category() : String {
    return "Koşul";
  }
}
