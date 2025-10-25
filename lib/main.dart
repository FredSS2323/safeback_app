import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:audioplayers/audioplayers.dart';

void main() {
  runApp(const SafeBackApp());
}

class SafeBackApp extends StatelessWidget {
  const SafeBackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeBack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SafeBackHome(),
    );
  }
}

class SafeBackHome extends StatefulWidget {
  const SafeBackHome({super.key});

  @override
  State<SafeBackHome> createState() => _SafeBackHomeState();
}

class _SafeBackHomeState extends State<SafeBackHome> {
  BluetoothDevice? _device;
  BluetoothConnection? _connection;
  bool _connected = false;
  String _status = "Desconectado";
  final _player = AudioPlayer();
  Timer? _reconnectTimer;

  /// Função de conexão manual
  Future<void> _connectToESP() async {
    setState(() => _status = "Procurando dispositivos...");

    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();

      // Procura o dispositivo com nome "SafeBack"
      _device = devices.firstWhere(
        (d) => d.name == "SafeBack",
        orElse: () => throw Exception("Dispositivo 'SafeBack' não encontrado"),
      );

      _status = "Conectando a ${_device!.name}...";
      setState(() {});

      _connection = await BluetoothConnection.toAddress(_device!.address);

      setState(() {
        _connected = true;
        _status = "Conectado a ${_device!.name}";
      });

      _connection!.input!.listen((Uint8List data) {
        final message = String.fromCharCodes(data).trim();
        debugPrint("Recebido: $message");

        if (message.contains("OCUPADO")) {
          _tocarAlerta();
        }
      }).onDone(() {
        setState(() {
          _connected = false;
          _status = "Conexão perdida. Tentando reconectar...";
        });
        _startAutoReconnect();
      });
    } catch (e) {
      setState(() {
        _connected = false;
        _status = "Erro: $e";
      });
      _startAutoReconnect();
    }
  }

  /// Reconexão automática a cada 5s se a conexão cair
  void _startAutoReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_connected) {
        debugPrint("Tentando reconectar...");
        _connectToESP();
      } else {
        timer.cancel();
      }
    });
  }

  /// Desconectar do ESP32
  Future<void> _disconnect() async {
    await _connection?.close();
    setState(() {
      _connected = false;
      _status = "Desconectado";
    });
    _reconnectTimer?.cancel();
  }

  /// Toca alerta sonoro
  Future<void> _tocarAlerta() async {
    await _player.play(AssetSource('sounds/alerta.mp3'));
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _connection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SafeBack"),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              size: 100,
              color: _connected ? Colors.blue : Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _status,
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // BOTÃO DE CONEXÃO / DESCONECTAR
            ElevatedButton.icon(
              onPressed: _connected ? _disconnect : _connectToESP,
              icon: Icon(_connected ? Icons.link_off : Icons.bluetooth_searching),
              label: Text(_connected ? "Desconectar" : "Conectar ao Safeback"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),

            const SizedBox(height: 20),

            // BOTÃO TESTE DE ALERTA
            ElevatedButton.icon(
              onPressed: _tocarAlerta,
              icon: const Icon(Icons.volume_up),
              label: const Text("Testar alerta sonoro"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
