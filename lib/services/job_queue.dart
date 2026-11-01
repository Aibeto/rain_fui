/// The queue that runs encodes in the background and the state a row on the
/// home screen reads.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../src/ffmpeg/ffmpeg.dart';
import '../src/media/encode_request.dart';

/// Lifecycle of one queued encode.
enum JobState {
  /// Waiting for the previous job to finish.
  queued,

  /// FFmpeg is running.
  running,

  /// FFmpeg is suspended by the platform.
  paused,

  /// Finished with exit code 0.
  completed,

  /// Finished with a non-zero exit code.
  failed,

  /// Stopped by the user.
  cancelled,
}

/// One encode, observable by the UI.
class EncodeJob extends ChangeNotifier {
  EncodeJob({required this.id, required this.request, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();

  /// Stable identifier used as a widget key.
  final String id;

  /// Frozen form selection.
  final EncodeRequest request;

  /// When the user pressed Start.
  final DateTime createdAt;

  JobState _state = JobState.queued;
  double? _progress;
  Duration _position = Duration.zero;
  Duration? _duration;
  String? _error;
  String _logTail = '';
  bool _canSuspend = true;

  /// Current lifecycle state.
  JobState get state => _state;

  /// 0..1 when the input duration is known, null while it is not.
  double? get progress => _progress;

  /// Position FFmpeg reported last.
  Duration get position => _position;

  /// Duration parsed from FFmpeg's input banner, when it printed one.
  Duration? get duration => _duration;

  /// Failure detail, shown under the row.
  String? get error => _error;

  /// Last progress/log lines, kept short for the row tooltip.
  String get logTail => _logTail;

  /// False once the platform refused to suspend the process.
  bool get canSuspend => _canSuspend;

  /// Output file name, shown as the row title.
  String get displayName => p.basename(request.outputPath);

  /// Where the result is written.
  String get outputPath => request.outputPath;

  /// Input file name, shown as the row subtitle.
  String get inputName => request.inputName;

  /// Whether the row should offer Pause (running) or Resume (paused).
  bool get isActive => _state == JobState.running || _state == JobState.paused;

  /// Whether the job occupies the queue slot.
  bool get isFinished =>
      _state == JobState.completed ||
      _state == JobState.failed ||
      _state == JobState.cancelled;

  void markQueued() => _transit(JobState.queued);

  void markRunning() {
    _error = null;
    _transit(JobState.running);
  }

  void markPaused() => _transit(JobState.paused);

  void markResumed() => _transit(JobState.running);

  void markCompleted() {
    _progress = 1;
    _transit(JobState.completed);
  }

  void markFailed(String message) {
    _error = message;
    _transit(JobState.failed);
  }

  void markCancelled() => _transit(JobState.cancelled);

  /// Records that the platform cannot suspend this job.
  void denySuspend() {
    _canSuspend = false;
    notifyListeners();
  }

  void applyProgress(FfmpegProgress progress) {
    final Duration? time = progress.outTime;
    if (time != null) {
      _position = time;
      final Duration? total = _duration;
      if (total != null && total.inMilliseconds > 0) {
        _progress = (time.inMilliseconds / total.inMilliseconds).clamp(
          0.0,
          1.0,
        );
      }
    }
    notifyListeners();
  }

  void applyLogLine(String line) {
    if (line.trim().isEmpty) {
      return;
    }
    if (_duration == null) {
      final Duration? parsed = parseMediaDuration(line);
      if (parsed != null && parsed > Duration.zero) {
        _duration = parsed;
        notifyListeners();
        return;
      }
    }
    _logTail = line;
  }

  void _transit(JobState next) {
    if (_state == next) {
      return;
    }
    _state = next;
    notifyListeners();
  }
}

/// Last few lines of FFmpeg's stderr, used as the failure detail.
String _tail(String text, {int lines = 4}) {
  final List<String> all = text
      .split('\n')
      .map((String line) => line.trimRight())
      .where((String line) => line.isNotEmpty)
      .toList();
  if (all.length <= lines) {
    return all.join('\n');
  }
  return all.sublist(all.length - lines).join('\n');
}

/// Parses the `Duration: 00:01:23.45` line FFmpeg prints while probing input.
Duration? parseMediaDuration(String line) {
  final Match? match = RegExp(r'Duration:\s*(\d+):(\d{2}):(\d{2}(?:\.\d+)?)')
      .firstMatch(line);
  if (match == null) {
    return null;
  }
  final double seconds = double.parse(match.group(3)!);
  return Duration(
    hours: int.parse(match.group(1)!),
    minutes: int.parse(match.group(2)!),
    milliseconds: (seconds * 1000).round(),
  );
}

/// Serial queue that drives one encode at a time.
///
/// A single instance is enough for the whole app: the home screen listens to it
/// and the encode form only ever enqueues.
class JobQueue extends ChangeNotifier {
  JobQueue() : _backend = null;

  /// Queue bound to an explicit backend, used by tests.
  @visibleForTesting
  JobQueue.withBackend(FfmpegBackend backend) : _backend = backend;

  /// Process-wide queue.
  static final JobQueue instance = JobQueue();

  final List<EncodeJob> _jobs = <EncodeJob>[];
  FfmpegBackend? _backend;
  EncodeJob? _active;
  FfmpegTask? _task;
  int _counter = 0;

  /// Jobs in creation order, newest last.
  List<EncodeJob> get jobs => List<EncodeJob>.unmodifiable(_jobs);

  /// Whether a job currently owns the runner.
  bool get isBusy => _active != null;

  /// Adds [request] and starts pumping the queue.
  EncodeJob enqueue(EncodeRequest request) {
    final EncodeJob job = EncodeJob(id: 'job-${_counter++}', request: request);
    _jobs.add(job);
    notifyListeners();
    unawaited(_pump());
    return job;
  }

  /// Removes a finished job from the list.
  void remove(EncodeJob job) {
    if (!job.isFinished) {
      return;
    }
    _jobs.remove(job);
    job.dispose();
    notifyListeners();
  }

  /// Suspends [job] if it is the running one and the platform allows it.
  Future<bool> pause(EncodeJob job) async {
    if (job != _active || job.state != JobState.running) {
      return false;
    }
    final FfmpegTask? task = _task;
    if (task == null) {
      return false;
    }
    final bool suspended = await task.suspend();
    if (suspended) {
      job.markPaused();
      notifyListeners();
    } else {
      job.denySuspend();
    }
    return suspended;
  }

  /// Resumes a paused [job].
  Future<bool> resume(EncodeJob job) async {
    if (job != _active || job.state != JobState.paused) {
      return false;
    }
    final FfmpegTask? task = _task;
    if (task == null) {
      return false;
    }
    final bool resumed = await task.resume();
    if (resumed) {
      job.markResumed();
      notifyListeners();
    }
    return resumed;
  }

  /// Stops [job]; a queued job is dropped, a running one is terminated.
  Future<void> cancel(EncodeJob job) async {
    if (job.isFinished) {
      return;
    }
    if (job == _active) {
      await _task?.cancel();
      return;
    }
    job.markCancelled();
    notifyListeners();
  }

  Future<void> _pump() async {
    if (_active != null) {
      return;
    }
    EncodeJob? next;
    for (final EncodeJob job in _jobs) {
      if (job.state == JobState.queued) {
        next = job;
        break;
      }
    }
    if (next == null) {
      return;
    }
    _active = next;
    next.markRunning();
    notifyListeners();

    final FfmpegBackend backend = _backend ??= createFfmpegBackend();
    try {
      await backend.initialize();
      if (!backend.isAvailable) {
        next.markFailed(backend.unavailableReason ?? 'FFmpeg is unavailable');
        return;
      }
      final FfmpegTask task = await backend.run(
        FfmpegCommand(buildEncodeArgs(next.request)),
      );
      _task = task;
      final StreamSubscription<String> logs = task.logs.listen(
        next.applyLogLine,
      );
      final StreamSubscription<FfmpegProgress> progress = task.progress.listen(
        next.applyProgress,
      );
      final FfmpegResult result = await task.done;
      await logs.cancel();
      await progress.cancel();
      if (result.succeeded) {
        next.markCompleted();
      } else if (task.wasCancelled) {
        next.markCancelled();
      } else {
        next.markFailed(_tail(result.stderr));
      }
    } on FfmpegException catch (error) {
      next.markFailed(error.message);
    } on Object catch (error) {
      next.markFailed('$error');
    } finally {
      _task = null;
      _active = null;
      notifyListeners();
      unawaited(_pump());
    }
  }
}
