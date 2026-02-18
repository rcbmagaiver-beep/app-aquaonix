import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

void main() => runApp(MaterialApp(home: AquaonixApp(), theme: ThemeData.dark()));

class AquaonixApp extends StatefulWidget {
  @override
  _AquaonixAppState createState() => _AquaonixAppState();
}

class _AquaonixAppState extends State<AquaonixApp> {
  final String ipLocal = "192.168.0.115";
  final String ipTailscale = "100.X.Y.Z"; // <--- SUBSTITUI PELO TEU IP DO TAILSCALE
  
  MqttServerClient? client;
  List<bool> relayStates = List.generate(16, (index) => false);
  String status = "A iniciar...";

  @override
  void initState() {
    super.initState();
    _tentarConectar();
  }

  Future<void> _tentarConectar() async {
    setState(() => status = "A procurar painel local...");
    bool localOk = await _checkPort(ipLocal);
    _iniciarMqtt(localOk ? ipLocal : ipTailscale);
  }

  Future<bool> _checkPort(String ip) async {
    try {
      final socket = await Socket.connect(ip, 1883, timeout: Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) { return false; }
  }

  void _iniciarMqtt(String host) async {
    setState(() => status = "A conectar a $host...");
    client = MqttServerClient(host, 'app_client_${DateTime.now().millisecondsSinceEpoch}');
    client!.port = 1883;
    client!.connectionMessage = MqttConnectMessage()
        .withClientIdentifier('AquaApp')
        .authenticateAs('esp32', 'esp32mqtt')
        .startClean();

    try {
      await client!.connect();
      setState(() => status = "Online: $host");
      for (int i = 0; i < 16; i++) {
        client!.subscribe("homeassistant/switch/aquaonix_relay_$i/state", MqttQos.atLeastOnce);
      }
      client!.updates!.listen((c) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        int index = int.parse(RegExp(r'\d+').firstMatch(c[0].topic)!.group(0)!);
        setState(() => relayStates[index] = (pt == "ON"));
      });
    } catch (e) {
      setState(() => status = "Erro de ligação");
    }
  }

  void _toggle(int i) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(relayStates[i] ? 'OFF' : 'ON');
    client?.publishMessage("homeassistant/switch/aquaonix_relay_$i/set", MqttQos.atLeastOnce, builder.payload!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Aquaonix Pro"), actions: [IconButton(icon: Icon(Icons.refresh), onPressed: _tentarConectar)]),
      body: Column(
        children: [
          Container(width: double.infinity, padding: EdgeInsets.all(8), color: Colors.blueGrey[900], child: Text(status, textAlign: TextAlign.center)),
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.all(10),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.6, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: 16,
              itemBuilder: (context, i) => ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: relayStates[i] ? Colors.blueAccent : Colors.grey[850]),
                onPressed: () => _toggle(i),
                child: Text("SAÍDA ${i + 1}"),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
