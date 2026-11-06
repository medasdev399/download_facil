/// Download Fácil
/// Gerenciador de downloads multithread, extrator e conversor de mídia.
/// Desenvolvedor: Gabriel Moreno Medeiros
/// Versão: 1.1.0

import 'package:flutter/material.dart';
import 'services/log_service.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LogService.initGlobalErrorHandling();
  runApp(const DownloadFacilApp());
}

class DownloadFacilApp extends StatelessWidget {
  const DownloadFacilApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Download Fácil',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: const HomePage(),
    );
  }
}