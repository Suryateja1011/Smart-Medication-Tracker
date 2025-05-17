import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:convert';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeNotifications();
  tz.initializeTimeZones();
  runApp(const MyApp());
}

Future<void> _initializeNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  final initSettings = InitializationSettings(android: androidSettings);
  await flutterLocalNotificationsPlugin.initialize(initSettings);
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Medication Tracker',
      theme: ThemeData(primarySwatch: Colors.teal),
      home: const MedicationCalendarScreen(),
    );
  }
}

class MedicationCalendarScreen extends StatefulWidget {
  const MedicationCalendarScreen({super.key});
  @override
  State<MedicationCalendarScreen> createState() => _MedicationCalendarScreenState();
}

class _MedicationCalendarScreenState extends State<MedicationCalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  final TextEditingController _medController = TextEditingController();
  TimeOfDay? _selectedTime;
  Map<String, List<Map<String, dynamic>>> _scheduledMedications = {};

  @override
  void initState() {
    super.initState();
    _loadMedications();
  }

  void _loadMedications() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('medications');
    if (data != null) {
      setState(() {
        _scheduledMedications = Map<String, List<Map<String, dynamic>>>.from(
          json.decode(data).map((key, value) =>
              MapEntry(key, List<Map<String, dynamic>>.from(value))),
        );
      });
    }
  }

  void _saveMedications() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('medications', json.encode(_scheduledMedications));
  }

  void _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _scheduleNotification(String name, DateTime datetime) async {
    final tzDate = tz.TZDateTime.from(datetime, tz.local);
    final id = datetime.hashCode;

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id,
      'Medication Reminder',
      'Time to take: $name',
      tzDate,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'med_channel', 'Medication Reminders',
          channelDescription: 'Daily Medications',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidAllowWhileIdle: true,
      matchDateTimeComponents: DateTimeComponents.time,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  void _addMedication() {
    final name = _medController.text.trim();
    if (name.isNotEmpty && _selectedTime != null) {
      final scheduledDateTime = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      final key = _selectedDay.toIso8601String().split('T').first;
      _scheduledMedications.putIfAbsent(key, () => []);
      _scheduledMedications[key]!.add({
        'name': name,
        'time': _selectedTime!.format(context),
        'datetime': scheduledDateTime.toIso8601String(),
      });

      _saveMedications();
      _scheduleNotification(name, scheduledDateTime);
      _medController.clear();
      setState(() => _selectedTime = null);
    }
  }

  void _deleteMedication(int index) {
    final key = _selectedDay.toIso8601String().split('T').first;
    final med = _scheduledMedications[key]![index];
    final dt = DateTime.parse(med['datetime']);
    flutterLocalNotificationsPlugin.cancel(dt.hashCode);
    setState(() {
      _scheduledMedications[key]!.removeAt(index);
      if (_scheduledMedications[key]!.isEmpty) {
        _scheduledMedications.remove(key);
      }
    });
    _saveMedications();
  }

  @override
  Widget build(BuildContext context) {
    final selectedKey = _selectedDay.toIso8601String().split('T').first;
    final meds = _scheduledMedications[selectedKey] ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Smart Medication Tracker')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TableCalendar(
                focusedDay: _focusedDay,
                firstDay: DateTime.utc(2022, 1, 1),
                lastDay: DateTime.utc(2035, 12, 31),
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _medController,
                decoration: const InputDecoration(labelText: 'Medication Name'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton(onPressed: _pickTime, child: const Text('Pick Time')),
                  const SizedBox(width: 16),
                  Text(_selectedTime?.format(context) ?? 'No time selected'),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _addMedication,
                icon: const Icon(Icons.add),
                label: const Text('Schedule Reminder'),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const Text('Medications for selected date:', style: TextStyle(fontWeight: FontWeight.bold)),
              ListView.builder(
                shrinkWrap: true,
                itemCount: meds.length,
                itemBuilder: (context, index) {
                  final med = meds[index];
                  return ListTile(
                    title: Text('${med['name']} at ${med['time']}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deleteMedication(index),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}


