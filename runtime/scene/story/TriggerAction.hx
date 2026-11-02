package scene.story;

// Tetikleyici nesnesine eklenir, bileşen sırasıyla çalışır.
class TriggerAction extends Component {
  public function run(story : Story) {}

  override public function category() : String {
    return "Eylem";
  }
}
