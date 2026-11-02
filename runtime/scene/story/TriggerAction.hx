package scene.story;

// Tetikleyici nesnesine eklenir, bileşen sırasıyla çalışır.
class TriggerAction extends Component {
  public static inline var CATEGORY = "Eylem";

  public function run(story : Story) {}

  override public function category() : String {
    return CATEGORY;
  }
}
