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
  bool _modoSimulacao = true; // modo de teste sem ESP32
  bool _alertaAtivo = false; // controla se o som está tocando

  String _status = "Desconectado";
  final AudioPlayer _player = AudioPlayer();

  Timer? _reconnectTimer;
  Timer? _alertTimer;
  Timer? _verificacaoTimer;

  final int _tempoVerificacao = 10; // segundos

  /// Conecta ao ESP32 ou entra em modo simulação
  Future<void> _connectToESP() async {
    if (_modoSimulacao) {
      setState(() {
        _connected = true;
        _status = "Conectado";
      });
      _iniciarContagemDeVerificacao();
      return;
    }

    setState(() => _status = "Procurando dispositivos...");

    try {
      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();

      _device = devices.firstWhere(
        (d) => d.name == "SafeBack",
        orElse: () => throw Exception("Dispositivo 'SafeBack' não encontrado"),
      );

      setState(() => _status = "Conectando a ${_device!.name}...");

      _connection = await BluetoothConnection.toAddress(_device!.address);

      setState(() {
        _connected = true;
        _status = "Conectado a ${_device!.name}";
      });

      _iniciarContagemDeVerificacao();

      _connection!.input!.listen((Uint8List data) {
        final message = String.fromCharCodes(data).trim();
        debugPrint("Recebido: $message");

        if (message.contains("OCUPADO")) {
          _reiniciarContagem();
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

  /// Reconexão automática
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

  /// Desconecta e reseta tudo
  Future<void> _disconnect() async {
    await _connection?.close();
    await _pararAlerta();
    _cancelarContagens();

    setState(() {
      _connected = false;
      _status = "Desconectado";
    });

    _reconnectTimer?.cancel();
  }

  /// 🔊 Tocar alerta
  Future<void> _tocarAlerta() async {
    await _player.play(AssetSource('sounds/alerta.mp3'), volume: 1.0);
    _player.setReleaseMode(ReleaseMode.loop);
    setState(() {
      _alertaAtivo = true;
      _status = "⚠️ ALERTA ATIVO!";
    });

    _alertTimer?.cancel();
    _alertTimer = Timer(const Duration(seconds: 15), () {
      _pararAlerta();
    });
  }

  /// ⏹️ Parar alerta
  Future<void> _pararAlerta() async {
    _alertTimer?.cancel();
    await _player.stop();
    setState(() {
      _alertaAtivo = false;
      if (_connected) {
        _status = "Alerta desativado.";
      }
    });
  }

  /// ⏱️ Inicia contagem de verificação
  void _iniciarContagemDeVerificacao() {
    _verificacaoTimer?.cancel();
    debugPrint("⏱️ Iniciando contagem de $_tempoVerificacao segundos...");
    _verificacaoTimer = Timer(Duration(seconds: _tempoVerificacao), () {
      debugPrint("⚠️ Nenhum sinal recebido — acionando alerta!");
      _tocarAlerta();
    });
  }

  /// Reinicia contagem quando sinal é recebido
  void _reiniciarContagem() {
    debugPrint("🔄 Sinal recebido — reiniciando contagem.");
    _verificacaoTimer?.cancel();
    _iniciarContagemDeVerificacao();
  }

  /// Cancela timers
  void _cancelarContagens() {
    _verificacaoTimer?.cancel();
    _alertTimer?.cancel();
  }

  /// Simula sinal vindo do ESP
  void _simularSinalDoESP() {
    if (!_connected) return;
    debugPrint("Simulação: recebendo sinal OCUPADO...");
    setState(() {
      _status = "Sinal simulado recebido (OCUPADO)";
    });
    _reiniciarContagem();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _alertTimer?.cancel();
    _verificacaoTimer?.cancel();
    _connection?.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SafeBack"),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
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

              ElevatedButton.icon(
                onPressed: _connected ? _disconnect : _connectToESP,
                icon: Icon(_connected ? Icons.link_off : Icons.bluetooth_searching),
                label: Text(_connected ? "Desconectar" : "Conectar ao SafeBack"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),

              const SizedBox(height: 20),

              if (_alertaAtivo)
                ElevatedButton.icon(
                  onPressed: _pararAlerta,
                  icon: const Icon(Icons.stop_circle),
                  label: const Text("Desativar Alarme"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    textStyle: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
