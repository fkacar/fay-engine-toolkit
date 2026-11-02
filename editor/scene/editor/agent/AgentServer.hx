package scene.editor.agent;

import haxe.io.Bytes;
import sys.net.Host;
import sys.net.Socket;

typedef AgentTool = {
  var name : String;
  var description : String;
  var schema : Dynamic;                  // JSON Schema, girdi nesnesi
  var readOnly : Bool;
  var run : Dynamic->AgentReply;
}

typedef AgentPrompt = {
  var name : String;
  var description : String;
  var arguments : Array<{name : String, description : String, required : Bool}>;
  var text : Dynamic->String;            // argümanlarla ajana gidecek istek
}

typedef AgentReply = {
  var ?value : Dynamic;                  // metin olarak JSON gider
  var ?text : String;
  var ?png : Bytes;
  var ?wait : Void->Null<AgentReply>;   // birkaç karede biten iş: hazır olunca yanıt döner
}

private class Client {
  public var socket : Socket;
  public var input = Bytes.alloc(0);
  public var output : Null<Bytes>;
  public var sent = 0;
  public var closeAfterSend = false;

  public function new(socket : Socket) {
    this.socket = socket;
  }
}

// Editörün içindeki MCP sunucusu: Claude Code gibi dış ajanlar HTTP ile bağlanır. Yalnızca bu
// bilgisayardan erişilir. Soket bloklamaz, her karede yoklanır; istekler editörün ana döngüsünde,
// tasarımcının düzenlemeleriyle aynı sırada işlenir.
class AgentServer {
  public static inline var PORT = 8890;
  static inline var PATH = "/mcp";
  static inline var MAX_REQUEST = 4 * 1024 * 1024;
  static inline var MAX_TEXT = 40000;
  static inline var RETRY_SECONDS = 2.;
  static var VERSIONS = ["2025-11-25", "2025-06-18", "2025-03-26"];
  static inline var DEFERRED = "\u0000bekliyor";
  static inline var WAIT_FRAMES = 600;

  public var error(default, null) : Null<String>;
  public var calls(default, null) = 0;
  public var lastTool(default, null) = "";

  var port : Int;
  var listener : Null<Socket>;
  var clients : Array<Client> = [];
  var tools = new Map<String, AgentTool>();
  var order : Array<String> = [];
  var prompts : Array<AgentPrompt> = [];
  var instructions : String;
  var retry = 0.;
  var buffer = Bytes.alloc(64 * 1024);
  var waiting : Array<{id : Dynamic, wait : Void->Null<AgentReply>, client : Null<Client>, frames : Int}> = [];

  public function new(port : Int, instructions : String) {
    this.port = port;
    this.instructions = instructions;
    open();
  }

  public function add(tool : AgentTool) {
    if (!tools.exists(tool.name)) order.push(tool.name);
    tools.set(tool.name, tool);
  }

  // Claude Code'da "/sunucu:ad" komutu olur.
  public function addPrompt(prompt : AgentPrompt) {
    prompts = prompts.filter(other -> other.name != prompt.name);
    prompts.push(prompt);
  }

  public function isListening() {
    return listener != null;
  }

  // Port kullanımdaysa (başka bir editör açık) birkaç saniyede bir yeniden denenir.
  public function update(dt : Float) {
    if (listener == null) {
      retry += dt;
      if (retry >= RETRY_SECONDS) {
        retry = 0;
        open();
      }
      return;
    }
    accept();
    for (job in waiting.copy()) {
      job.frames++;
      var result = try job.wait() catch (e : Dynamic) ({text: 'çalışmadı: $e'} : AgentReply);
      if (result == null && job.frames < WAIT_FRAMES) continue;
      if (result == null) result = {text: "zaman aşımı"};
      waiting.remove(job);
      if (job.client != null) respond(job.client, 200, "application/json", reply(job.id, content(result)));
    }
    for (client in clients.copy()) {
      if (client.output == null) receive(client);
      if (client.output != null) send(client);
    }
  }

  public function close() {
    for (client in clients) try client.socket.close() catch (e : Dynamic) {}
    clients = [];
    if (listener != null) try listener.close() catch (e : Dynamic) {}
    listener = null;
  }

  // HTTP gövdesi dışında da denenebilsin diye ayrı: JSON-RPC mesajı alır, yanıt metni verir.
  public function handle(body : String) : Null<String> {
    var message : Dynamic = try haxe.Json.parse(body) catch (e : Dynamic) return reply(null, null, {code: -32700, message: "JSON okunamadı"});
    if (Std.isOfType(message, Array)) {
      var items : Array<Dynamic> = message;
      var answers = [for (item in items) answer(item)].filter(text -> text != null);
      return answers.length == 0 ? null : "[" + answers.join(",") + "]";
    }
    return answer(message);
  }

  function open() {
    try {
      var socket = new Socket();
      socket.bind(new Host("127.0.0.1"), port);
      socket.listen(16);
      socket.setBlocking(false);
      listener = socket;
      error = null;
    } catch (e : Dynamic) {
      listener = null;
      error = 'port $port açılamadı: $e';
    }
  }

  function accept() {
    while (true) {
      var socket = try listener.accept() catch (e : Dynamic) null;
      if (socket == null) return;
      socket.setBlocking(false);
      clients.push(new Client(socket));
    }
  }

  function receive(client : Client) {
    while (true) {
      var count = try client.socket.input.readBytes(buffer, 0, buffer.length) catch (e : haxe.io.Error) {
        if (e.match(Blocked)) break;
        drop(client);
        return;
      } catch (e : Dynamic) {
        drop(client);
        return;
      }
      if (count <= 0) break;
      var joined = Bytes.alloc(client.input.length + count);
      joined.blit(0, client.input, 0, client.input.length);
      joined.blit(client.input.length, buffer, 0, count);
      client.input = joined;
      if (client.input.length > MAX_REQUEST) {
        respond(client, 413, "text/plain", "çok büyük");
        return;
      }
    }
    var request = parse(client.input);
    if (request == null) return;
    client.input = request.rest == null ? Bytes.alloc(0) : request.rest;
    route(client, request);
  }

  function parse(bytes : Bytes) : Null<{method : String, path : String, headers : Map<String, String>, body : String, rest : Null<Bytes>}> {
    var end = -1;
    for (i in 0...bytes.length - 3)
      if (bytes.get(i) == 13 && bytes.get(i + 1) == 10 && bytes.get(i + 2) == 13 && bytes.get(i + 3) == 10) {
        end = i;
        break;
      }
    if (end < 0) return null;
    var lines = bytes.getString(0, end).split("\r\n");
    var first = lines.shift().split(" ");
    var headers = new Map<String, String>();
    for (line in lines) {
      var colon = line.indexOf(":");
      if (colon > 0) headers.set(line.substr(0, colon).toLowerCase(), StringTools.trim(line.substr(colon + 1)));
    }
    var length = headers.exists("content-length") ? Std.parseInt(headers.get("content-length")) : 0;
    var start = end + 4;
    if (bytes.length - start < length) return null;
    var rest = bytes.length - start - length > 0 ? bytes.sub(start + length, bytes.length - start - length) : null;
    return {method: first[0], path: first.length > 1 ? first[1] : "/", headers: headers, body: bytes.getString(start, length), rest: rest};
  }

  // Tarayıcıdan gelen istek (Origin başlığı olan) ve başka adla gelen istek reddedilir: bir web
  // sayfası editöre ulaşamaz, DNS yeniden bağlama da işe yaramaz.
  function route(client : Client, request : {method : String, path : String, headers : Map<String, String>, body : String, rest : Null<Bytes>}) {
    var host = request.headers.get("host");
    var allowed = host == '127.0.0.1:$port' || host == 'localhost:$port';
    if (request.headers.exists("origin") || !allowed) {
      respond(client, 403, "text/plain", "yalnızca bu bilgisayardaki ajanlar bağlanabilir");
      return;
    }
    var path = request.path.split("?")[0];
    if (path != PATH) {
      respond(client, 404, "text/plain", "yol yok");
      return;
    }
    if (request.method != "POST") {
      respond(client, 405, "text/plain", "yalnızca POST");
      return;
    }
    var answer = try handle(request.body) catch (e : Dynamic) reply(null, null, {code: -32603, message: Std.string(e)});
    if (answer == DEFERRED) {
      waiting[waiting.length - 1].client = client;
      return;
    }
    if (answer == null) respond(client, 202, "text/plain", "");
    else respond(client, 200, "application/json", answer);
  }

  function answer(message : Dynamic) : Null<String> {
    var id : Dynamic = message.id;
    var method : String = message.method;
    if (id == null || method == null) return null;
    var params : Dynamic = message.params == null ? {} : message.params;
    return switch (method) {
      case "initialize":
        var asked : String = params.protocolVersion;
        reply(id, {
          protocolVersion: VERSIONS.indexOf(asked) >= 0 ? asked : VERSIONS[1],
          capabilities: {tools: {listChanged: false}, prompts: {listChanged: false}},
          serverInfo: {name: "yoa-editor", version: "0.1.0"},
          instructions: instructions,
        });
      case "ping": reply(id, {});
      case "tools/list": reply(id, {tools: [for (name in order) describe(tools.get(name))]});
      case "tools/call":
        var result = call(params.name, params.arguments == null ? {} : params.arguments);
        if (result != null && result.wait != null) {
          waiting.push({id: id, wait: result.wait, client: null, frames: 0});
          DEFERRED;
        } else reply(id, result);
      case "prompts/list": reply(id, {prompts: [for (prompt in prompts) {name: prompt.name, description: prompt.description, arguments: prompt.arguments}]});
      case "prompts/get":
        var prompt = Lambda.find(prompts, item -> item.name == params.name);
        if (prompt == null) reply(id, null, {code: -32602, message: 'böyle bir istem yok: ${params.name}'});
        else reply(id, {description: prompt.description, messages: [{role: "user", content: {type: "text", text: prompt.text(params.arguments == null ? {} : params.arguments)}}]});
      case "resources/list": reply(id, {resources: []});
      default: reply(id, null, {code: -32601, message: 'bilinmeyen yöntem: $method'});
    };
  }

  function describe(tool : AgentTool) : Dynamic {
    return {
      name: tool.name,
      description: tool.description,
      inputSchema: tool.schema,
      annotations: {readOnlyHint: tool.readOnly},
    };
  }

  // Araç hatası editörü düşürmez, ajana hata olarak döner.
  function call(name : String, arguments : Dynamic) : Dynamic {
    var tool = tools.get(name);
    if (tool == null) return {content: [{type: "text", text: 'Böyle bir araç yok: $name'}], isError: true};
    calls++;
    lastTool = name;
    try {
      var result = tool.run(arguments);
      if (result.wait != null) return result;
      return content(result);
    } catch (e : Dynamic) {
      return {content: [{type: "text", text: '$name çalışmadı: $e'}], isError: true};
    }
  }

  static function content(result : AgentReply) : Dynamic {
    var content : Array<Dynamic> = [];
    if (result.value != null) content.push({type: "text", text: limit(haxe.Json.stringify(result.value, null, " "))});
    if (result.text != null) content.push({type: "text", text: limit(result.text)});
    if (result.png != null) content.push({type: "image", data: haxe.crypto.Base64.encode(result.png), mimeType: "image/png"});
    return {content: content};
  }

  static function limit(text : String) {
    return text.length <= MAX_TEXT ? text : text.substr(0, MAX_TEXT) + '\n... kısaltıldı (${text.length} karakter). Filtre veya sayfa kullan.';
  }

  static function reply(id : Dynamic, result : Dynamic, ?error : Dynamic) : String {
    var message : Dynamic = {jsonrpc: "2.0", id: id};
    if (error != null) message.error = error;
    else message.result = result;
    return haxe.Json.stringify(message);
  }

  function respond(client : Client, status : Int, type : String, body : String) {
    var payload = Bytes.ofString(body);
    var reason = switch (status) {
      case 200: "OK";
      case 202: "Accepted";
      case 403: "Forbidden";
      case 404: "Not Found";
      case 405: "Method Not Allowed";
      case 413: "Payload Too Large";
      default: "Error";
    };
    var head = 'HTTP/1.1 $status $reason\r\nContent-Type: $type; charset=utf-8\r\nContent-Length: ${payload.length}\r\nConnection: close\r\n\r\n';
    var all = new haxe.io.BytesBuffer();
    all.addString(head);
    all.addBytes(payload, 0, payload.length);
    client.output = all.getBytes();
    client.sent = 0;
    client.closeAfterSend = true;
  }

  // Büyük yanıt (görüntü) karede bitmeyebilir: kalanı sonraki karede gider.
  function send(client : Client) {
    while (client.sent < client.output.length) {
      var count = try client.socket.output.writeBytes(client.output, client.sent, client.output.length - client.sent) catch (e : haxe.io.Error) {
        if (e.match(Blocked)) return;
        drop(client);
        return;
      } catch (e : Dynamic) {
        drop(client);
        return;
      }
      if (count <= 0) return;
      client.sent += count;
    }
    drop(client);
  }

  function drop(client : Client) {
    try client.socket.close() catch (e : Dynamic) {}
    clients.remove(client);
  }
}
