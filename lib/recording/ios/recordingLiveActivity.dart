import 'package:live_activities/live_activities.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

Logger logger = Logger();

final _liveActivitiesPlugin = LiveActivities();

Future<void> init() async{
  if(await _liveActivitiesPlugin.areActivitiesEnabled()){
    logger.i('Live Activities are enabled');
  } else {
    logger.i('Live Activities are not enabled');
    return;
  }
  logger.i('Initializing Live Activities');
  await _liveActivitiesPlugin.init(appGroupId: "group.delta.strnadi");
  logger.i('Live Activities initialized');
}

Future<String?> start() async{
  final Map<String, dynamic> activityModel = {
    "testText": "Hello World",
  };
  logger.i('Starting Live Activity with model: $activityModel');
  final String? activityId = await _liveActivitiesPlugin.createActivity(activityModel);
  logger.i('Live Activity started with ID: $activityId');
  return activityId;
}

Future<void> stop(String activityId) async{
  logger.i('Stopping Live Activity with ID: $activityId');
  return await _liveActivitiesPlugin.endActivity(activityId);
}



class LiveActivityTester extends StatefulWidget {
  const LiveActivityTester({Key? key}) : super(key: key);

  @override
  _LiveActivityTesterState createState() => _LiveActivityTesterState();
}

class _LiveActivityTesterState extends State<LiveActivityTester> {
  String? _activityId;

  @override
  void initState() {
    super.initState();
    // Initialize live activities
    init();
  }

  Future<void> _startActivity() async {
    final activityId = await start();
    setState(() {
      _activityId = activityId;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Live Activity started: $activityId')),
    );
  }

  Future<void> _stopActivity() async {
    if (_activityId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No activity to stop.')),
      );
      return;
    }
    await stop(_activityId!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Live Activity stopped.')),
    );
    setState(() {
      _activityId = null;
    });
  }

  Future<void> _getAllActivities() async {
    final activities = await _liveActivitiesPlugin.getAllActivities();
    logger.i('All Live Activities: $activities');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('All Live Activities: $activities')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Live Activity Tester'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _startActivity,
              child: Text('Start Live Activity'),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _stopActivity,
              child: Text('Stop Live Activity'),
            ),
          ],
        ),
      ),
    );
  }
}