import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/room_booking/data/models.dart';
import 'package:intl/intl.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 13, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 15, minute: 0);
  
  bool _isLoading = false;
  bool _isAutoLoggingIn = false;
  List<RoomWithSlots>? _availableRooms;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.read(authStateProvider)) {
        _attemptAutoLogin();
      }
    });
  }

  Future<void> _attemptAutoLogin() async {
    setState(() => _isAutoLoggingIn = true);
    try {
      final storage = ref.read(secureStorageProvider);
      final creds = await storage.getCredentials();
      final username = creds['username'];
      final password = creds['password'];
      
      if (username != null && username.isNotEmpty && password != null && password.isNotEmpty) {
        final authService = ref.read(authServiceProvider);
        final success = await authService.login(username, password);
        ref.read(authStateProvider.notifier).state = success;
      }
    } catch (e) {
      // Auto login failed silently
    } finally {
      if (mounted) {
        setState(() => _isAutoLoggingIn = false);
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 14)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _availableRooms = null;
      });
    }
  }

  TimeOfDay _snapTime(TimeOfDay time) {
    if (time.minute < 15) return TimeOfDay(hour: time.hour, minute: 0);
    if (time.minute < 45) return TimeOfDay(hour: time.hour, minute: 30);
    return TimeOfDay(hour: (time.hour + 1) % 24, minute: 0);
  }

  Future<void> _selectStartTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) {
      final snapped = _snapTime(picked);
      if (snapped != _startTime) {
        setState(() {
          _startTime = snapped;
          _availableRooms = null;
        });
        if (snapped.minute != picked.minute && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time rounded to nearest 30 mins')));
        }
      }
    }
  }

  Future<void> _selectEndTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) {
      final snapped = _snapTime(picked);
      if (snapped != _endTime) {
        setState(() {
          _endTime = snapped;
          _availableRooms = null;
        });
        if (snapped.minute != picked.minute && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Time rounded to nearest 30 mins')));
        }
      }
    }
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return "$h:$m";
  }

  int _toMin(String time) {
    final parts = time.split(":");
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  List<RoomSlot> _slotsInRange(List<RoomSlot> slots, String rangeStr) {
    final parts = rangeStr.split("-");
    final lo = _toMin(parts[0]);
    final hi = _toMin(parts[1]);
    
    List<RoomSlot> picks = [];
    for (var sl in slots) {
      if (!sl.available) continue;
      
      try {
        final lblParts = sl.label.split("-");
        final sMin = _toMin(lblParts[0]);
        final eMin = _toMin(lblParts[1]);
        if (sMin >= lo && eMin <= hi) {
          picks.add(sl);
        }
      } catch (e) {
        // ignore malformed labels
      }
    }
    picks.sort((a, b) => _toMin(a.label.split("-")[0]).compareTo(_toMin(b.label.split("-")[0])));
    return picks;
  }

  Future<void> _fetchRooms() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _availableRooms = null;
    });

    try {
      final service = ref.read(bookingServiceProvider);
      final rooms = await service.getRooms();
      
      final dateStr = DateFormat('d MMM yyyy').format(_selectedDate); // e.g. 18 May 2026
      
      final info = await service.checkAvailability(rooms, dateStr, "07:00", "22:00");
      
      final timeRangeStr = "${_formatTime(_startTime)}-${_formatTime(_endTime)}";
      
      // Filter slots by requested time range
      List<RoomWithSlots> validRooms = [];
      for (var rm in info) {
        final picks = _slotsInRange(rm.slots, timeRangeStr);
        if (picks.isNotEmpty) {
          validRooms.add(RoomWithSlots(rm.room, picks));
        }
      }

      setState(() {
        _availableRooms = validRooms;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _bookRoom(RoomWithSlots roomWithSlots) async {
    try {
      showDialog(
        context: context, 
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator())
      );

      final service = ref.read(bookingServiceProvider);
      final dateStr = DateFormat('d MMM yyyy').format(_selectedDate);
      
      await service.initiateAndConfirmBooking(roomWithSlots.room, roomWithSlots.slots, dateStr);

      if (mounted) {
        Navigator.pop(context); // pop loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully booked ${roomWithSlots.room.rsrcName}!'), backgroundColor: Colors.green)
        );
        _fetchRooms(); // refresh
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // pop loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking failed: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(authStateProvider);

    if (_isAutoLoggingIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Create Booking')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Authenticating securely...', style: TextStyle(fontSize: 18)),
            ],
          ),
        ),
      );
    }

    if (!isAuthenticated) {
      return Scaffold(
        appBar: AppBar(title: const Text('Create Booking')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 80, color: Colors.grey),
              SizedBox(height: 20),
              Text('Not Authenticated', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 10),
              Text('Please go to Settings to connect your ADFS account.'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Create Booking')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectDate(context),
                    icon: const Icon(Icons.calendar_month),
                    label: Text(DateFormat('d MMM yyyy').format(_selectedDate)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectStartTime(context),
                    icon: const Icon(Icons.access_time),
                    label: Text("Start: ${_startTime.format(context)}"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectEndTime(context),
                    icon: const Icon(Icons.access_time),
                    label: Text("End: ${_endTime.format(context)}"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _fetchRooms,
                child: _isLoading 
                  ? const CircularProgressIndicator()
                  : const Text('Find Available Rooms'),
              ),
            ),
            const SizedBox(height: 24),
            
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              
            if (_availableRooms != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Available Rooms (${_availableRooms!.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: _availableRooms!.length,
                  itemBuilder: (context, index) {
                    final rm = _availableRooms![index];
                    return Card(
                      child: ListTile(
                        title: Text(rm.room.rsrcName),
                        subtitle: Text('Capacity: ${rm.room.capacity} • Slots: ${rm.slots.length}'),
                        trailing: ElevatedButton(
                          onPressed: () => _bookRoom(rm),
                          child: const Text('Book'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
