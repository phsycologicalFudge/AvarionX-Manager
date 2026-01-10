import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'screens/home_screen.dart';
import 'utils/auto_update_worker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Workmanager().initialize(
    autoUpdateWorker,
    isInDebugMode: false,
  );

  await Workmanager().registerPeriodicTask(
    'cs_auto_update',
    'cs_auto_update',
    frequency: const Duration(hours: 6),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}
