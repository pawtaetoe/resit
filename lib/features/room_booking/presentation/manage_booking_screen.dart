import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/features/room_booking/data/models.dart';

class ManageBookingScreen extends ConsumerStatefulWidget {
  const ManageBookingScreen({super.key});

  @override
  ConsumerState<ManageBookingScreen> createState() => _ManageBookingScreenState();
}

class _ManageBookingScreenState extends ConsumerState<ManageBookingScreen> {
  bool _isLoading = false;
  bool _isAutoLoggingIn = false;
  List<Booking>? _bookings;
  String? _errorMessage;
  String _selectedStatus = 'current';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(authStateProvider)) {
        _fetchBookings();
      } else {
        _attemptAutoLogin();
      }
    });
  }

  Future<void> _attemptAutoLogin() async {
    setState(() => _isAutoLoggingIn = true);
    try {
      // A fresh login needs MFA approval, so only reuse the saved session
      // here. If it has lapsed the user reconnects from Settings.
      final success = await ref.read(authServiceProvider).resumeSession();
      if (success && mounted) {
        _fetchBookings();
      }
    } catch (e) {
      // Auto login failed silently
    } finally {
      if (mounted) {
        setState(() => _isAutoLoggingIn = false);
      }
    }
  }

  DateTime _parseBookingDateTime(String dateStr, String timeRangeStr) {
    try {
      final date = DateFormat('d MMM yyyy').parse(dateStr);
      if (timeRangeStr.contains('-')) {
        final startTimeStr = timeRangeStr.split('-')[0].trim();
        final parts = startTimeStr.split(':');
        if (parts.length == 2) {
          final hours = int.parse(parts[0]);
          final minutes = int.parse(parts[1]);
          return date.add(Duration(hours: hours, minutes: minutes));
        }
      }
      return date;
    } catch (_) {
      try {
        return DateFormat('d MMM yyyy').parse(dateStr);
      } catch (_) {
        return DateTime(1970);
      }
    }
  }

  Future<void> _fetchBookings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final service = ref.read(bookingServiceProvider);
      
      if (_selectedStatus == 'current') {
        final rawList = await service.getBookings(bookingStatus: 'current');
        final filteredList = rawList.where((b) => b.status.toLowerCase() == 'confirmed').toList();
        
        filteredList.sort((a, b) {
          final aDateTime = _parseBookingDateTime(a.date, a.timeRange);
          final bDateTime = _parseBookingDateTime(b.date, b.timeRange);
          return bDateTime.compareTo(aDateTime);
        });

        setState(() {
          _bookings = filteredList;
        });
      } else {
        // Fetch history and current to combine non-confirmed ones
        List<Booking> historyList = [];
        try {
          historyList = await service.getBookings(bookingStatus: 'history');
        } catch (_) {
          // Ignore history API failure/absence and default to empty
        }

        List<Booking> currentList = [];
        try {
          currentList = await service.getBookings(bookingStatus: 'current');
        } catch (_) {
          // Ignore current API failure for this part
        }

        final nonConfirmedCurrent = currentList.where((b) => b.status.toLowerCase() != 'confirmed').toList();

        final combinedMap = <String, Booking>{};
        for (var b in historyList) {
          combinedMap[b.bookingRef] = b;
        }
        for (var b in nonConfirmedCurrent) {
          combinedMap[b.bookingRef] = b;
        }

        final combinedList = combinedMap.values.toList();
        
        combinedList.sort((a, b) {
          final aDateTime = _parseBookingDateTime(a.date, a.timeRange);
          final bDateTime = _parseBookingDateTime(b.date, b.timeRange);
          return bDateTime.compareTo(aDateTime);
        });

        setState(() {
          _bookings = combinedList;
        });
      }
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

  Future<void> _confirmAndCancelBooking(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Cancel Booking'),
          ],
        ),
        content: Text('Are you sure you want to cancel your booking for ${booking.roomName} on ${booking.date} (${booking.timeRange})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final service = ref.read(bookingServiceProvider);
      await service.cancelBooking(booking.cancelId);

      if (mounted) {
        Navigator.pop(context); // pop loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully cancelled booking ${booking.bookingRef}!'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchBookings(); // refresh the list
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // pop loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Booking reference copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAuthenticated = ref.watch(authStateProvider);

    if (_isAutoLoggingIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Manage Bookings')),
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
        appBar: AppBar(title: const Text('Manage Bookings')),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 80, color: Colors.grey),
              SizedBox(height: 20),
              Text(
                'Not Authenticated',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 10),
              Text('Please go to Settings to connect your ADFS account first.'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Bookings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchBookings,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: 'current',
                    label: Text('Current'),
                    icon: Icon(Icons.today),
                  ),
                  ButtonSegment<String>(
                    value: 'history',
                    label: Text('History'),
                    icon: Icon(Icons.history),
                  ),
                ],
                selected: {_selectedStatus},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _selectedStatus = newSelection.first;
                    _bookings = null;
                  });
                  _fetchBookings();
                },
              ),
            ),
          ),
          Expanded(
            child: _buildMainContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_isLoading && _bookings == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error Fetching Bookings',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchBookings,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_bookings == null || _bookings!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today_outlined, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 20),
            Text(
              'No Bookings Found',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Text(
              _selectedStatus == 'current'
                  ? 'You don\'t have any active bookings.'
                  : 'You have no booking history.',
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                // Navigate back or to dashboard screen
                Navigator.pop(context);
              },
              child: const Text('Go Book a Room'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _bookings!.length,
      itemBuilder: (context, index) {
        final booking = _bookings![index];
        final isConfirmed = booking.status.toLowerCase() == 'confirmed';
        final isCancelled = booking.status.toLowerCase() == 'cancelled';

        Color statusColor = Colors.grey;
        if (isConfirmed) statusColor = Colors.green;
        if (isCancelled) statusColor = Colors.red;

        return Card(
          margin: const EdgeInsets.only(bottom: 16.0),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        booking.roomName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusColor.withOpacity(0.5)),
                      ),
                      child: Text(
                        booking.status,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(booking.date),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(booking.timeRange),
                  ],
                ),
                if (booking.purpose.isNotEmpty && booking.purpose != 'N.A') ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.label_outline, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text('Purpose: ${booking.purpose}'),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => _copyToClipboard(booking.bookingRef),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.copy, size: 14, color: Colors.blueAccent),
                        const SizedBox(width: 6),
                        Text(
                          'Ref: ${booking.bookingRef}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (isConfirmed && booking.cancelId.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmAndCancelBooking(booking),
                      icon: const Icon(Icons.cancel_outlined, size: 18),
                      label: const Text('Cancel Booking'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
