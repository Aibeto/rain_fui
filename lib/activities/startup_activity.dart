import 'package:fluent_ui/fluent_ui.dart';

import 'home_activity.dart';

/// The launch activity from spec §1.
///
/// It paints nothing at all: `main()` already finished the bootstrap
/// (preferences + locale resolution) before `runApp`, so this route only hands
/// over to [HomeActivity] with `pushReplacement`, keeping the startup stack a
/// single entry deep.
class StartupActivity extends StatefulWidget {
  const StartupActivity({super.key});

  @override
  State<StartupActivity> createState() => _StartupActivityState();
}

class _StartupActivityState extends State<StartupActivity> {
  bool _handedOver = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handOver());
  }

  Future<void> _handOver() async {
    if (_handedOver || !mounted) {
      return;
    }
    _handedOver = true;
    await Navigator.of(context).pushReplacement<void, void>(
      FluentPageRoute<void>(
        builder: (BuildContext context) => const HomeActivity(),
      ),
    );
  }

  /// No UI by design.
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
