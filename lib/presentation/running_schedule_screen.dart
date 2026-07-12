import 'package:flutter/material.dart';
import '../data/services/isar_service.dart';
import '../data/models/schedule_item.dart';

class RunningScheduleScreen extends StatefulWidget {
  final IsarService isarService;

  const RunningScheduleScreen({
    super.key,
    required this.isarService,
  });

  @override
  State<RunningScheduleScreen> createState() => _RunningScheduleScreenState();
}

class _RunningScheduleScreenState extends State<RunningScheduleScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ScheduleItem> _defaultLoop = [];
  List<ScheduleItem> _priorityQueue = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    try {
      final defaultLoop = await widget.isarService.getDefaultLoop();
      final priorityQueue = await widget.isarService.getPriorityQueue();

      // Sort items by srtOrd
      defaultLoop.sort((a, b) => a.srtOrd.compareTo(b.srtOrd));
      priorityQueue.sort((a, b) => a.srtOrd.compareTo(b.srtOrd));

      if (mounted) {
        setState(() {
          _defaultLoop = defaultLoop;
          _priorityQueue = priorityQueue;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildScheduleList(List<ScheduleItem> items, String emptyMessage) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.playlist_remove, size: 64, color: Colors.white24),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: const TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isPriority = item.isPriority;

        // Determine appropriate icon based on media type/source
        IconData mediaIcon = Icons.web;
        if (item.type.toLowerCase().contains('video') || item.source.contains('youtube.com') || item.source.contains('youtu.be')) {
          mediaIcon = Icons.play_circle_outline;
        } else if (item.type.toLowerCase().contains('image')) {
          mediaIcon = Icons.image_outlined;
        }

        return Card(
          color: const Color(0xFF1E1E30),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isPriority ? Colors.amber.withOpacity(0.4) : Colors.white10,
              width: 1,
            ),
          ),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Badge / Order Index
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isPriority ? Colors.amber.withOpacity(0.2) : Colors.white12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${item.srtOrd}',
                        style: TextStyle(
                          color: isPriority ? Colors.amber : Colors.white70,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    // Type Badge
                    Row(
                      children: [
                        Icon(mediaIcon, size: 16, color: Colors.white54),
                        const SizedBox(width: 4),
                        Text(
                          item.type.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Title
                Text(
                  item.title.isEmpty ? 'Untitled Schedule' : item.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                // Source / URL text
                Text(
                  item.source,
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 13,
                    overflow: TextOverflow.ellipsis,
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Duration info
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined, size: 16, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          'Duration: ${item.durationSeconds}s',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                    // Schedule specifics (e.g. start time)
                    if (isPriority && item.startTime != null)
                      Row(
                        children: [
                          const Icon(Icons.alarm, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            'Starts: ${_formatTime(item.startTime!)}',
                            style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dateTime) {
    // Format to HH:mm
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E30),
        elevation: 0,
        title: const Text(
          'Running Playback Schedules',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFCF6679),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(
              icon: Icon(Icons.loop),
              text: 'Default Loop',
            ),
            Tab(
              icon: Icon(Icons.priority_high),
              text: 'Priority Queue',
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildScheduleList(_defaultLoop, 'No active default loop schedules found.'),
                _buildScheduleList(_priorityQueue, 'No active priority/scheduled items found.'),
              ],
            ),
    );
  }
}
