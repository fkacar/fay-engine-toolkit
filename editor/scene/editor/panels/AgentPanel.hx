package scene.editor.panels;

import imgui.ImGui;
import scene.editor.agent.AgentServer;

// Ajanın ne yaptığı: bağlantı durumu ve son çağrılar. Yalnızca görünürlük içindir, onay vermez.
// Yazan çağrılar sarı; her biri geçmişte "Ajan:" adımıdır, Cmd+Z ile geri alınır.
class AgentPanel {
  static inline var ACTIVE_SECONDS = 30.;
  static var WRITE_COLOR : ImVec4 = {x: 1, y: 0.8, z: 0.35, w: 1};
  static var ERROR_COLOR : ImVec4 = {x: 1, y: 0.45, z: 0.4, w: 1};

  var editor : Editor;

  public function new(editor : Editor) {
    this.editor = editor;
  }

  public function draw() {
    var agent = editor.agent;
    if (!agent.isListening()) ImGui.textColored(ERROR_COLOR, 'Sunucu kapalı: ${agent.error}. Başka bir editör açık olabilir, birkaç saniyede bir yeniden deneniyor.');
    else {
      var idle = haxe.Timer.stamp() - agent.lastRequest;
      ImGui.text(agent.calls == 0 ? 'Sunucu açık (port ${AgentServer.PORT}), henüz ajan bağlanmadı'
        : idle < ACTIVE_SECONDS ? 'Ajan bağlı, ${agent.calls} çağrı' : 'Sunucu açık, son çağrı ${Math.round(idle)} sn önce');
    }
    if (agent.log.length > 0) {
      ImGui.sameLine();
      if (ImGui.smallButton("Temizle")) agent.log.splice(0, agent.log.length);
    }
    var i = agent.log.length;
    while (i-- > 0) {
      var entry = agent.log[i];
      var time = DateTools.format(Date.fromTime(entry.time), "%H:%M:%S");
      var line = '$time  ${entry.tool}${entry.summary == "" ? "" : "  " + entry.summary}';
      if (!entry.ok) ImGui.textColored(ERROR_COLOR, line);
      else if (entry.writes) ImGui.textColored(WRITE_COLOR, line);
      else ImGui.textDisabled(line);
    }
  }
}
