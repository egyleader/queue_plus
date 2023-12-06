import 'dart:async';

import 'package:queue_plus/src/enums/queue_item_state.dart';

/// {@template QueueItem}
/// [QueueItem] is a data structure that holds the information related to the item in the queue.
/// this is used for easy minpulation and tracking of the queue items.
///
/// {@endtemplate}
class QueueItem<T> {
  /// {@macro QueueItem}
  QueueItem({required this.task, this.timeout = const Duration(seconds: 30), this.onComplete});

  /// The completer for the item future ,
  /// used to controle the task future according to the queue item & queue state.
  final Completer<T> completer = Completer<T>();

  /// the Future to be executed
  final Future<T> Function() task;

  /// the timeout for the Future to be executed before marking it as failed
  final Duration timeout;

  /// the callback to be executed after the Future is completed
  Function? onComplete;

  bool _timedOut = false;

  /// executes the Future and handles the state of the queue item
  ///
  Future<void> execute() async {
    try {
      T result;
      Timer? timoutTimer;
      _updateQueueItemStateStream(QueueItemState.processing);

      timoutTimer = Timer(timeout, () {
        completer.completeError(TimeoutException('Future timed out after $timeout', timeout));
        _timedOut = true;
        _updateQueueItemStateStream(QueueItemState.timedOut);
      });

      result = await task();
      completer.complete(result);
      _updateQueueItemStateStream(result != null ? QueueItemState.completed : QueueItemState.failed);

      //Make sure not to execute the next command until this future has completed
      timoutTimer.cancel();
      await Future.microtask(() {});
    } catch (e, stack) {
      completer.completeError(e, stack);
      _updateQueueItemStateStream(QueueItemState.failed);
    } finally {
      onComplete?.call();
    }
  }

  /// ============================================
  ///              QueueItem Status Stream
  ///=============================================

  StreamController<QueueItemState>? _queueItemStateController;

  /// the current State of the QueueItem
  /// created lazily to avoid creating a stream that is never listened to.
  Stream<QueueItemState> get queueItemState {
    if (_queueItemStateController == null) {
      _createQueueItemStateStream();
    }

    return _queueItemStateController!.stream;
  }

  void _createQueueItemStateStream() {
    _queueItemStateController = StreamController<QueueItemState>();
    _queueItemStateController!.add(QueueItemState.waiting);
  }

  void _updateQueueItemStateStream(QueueItemState state) {
    if (_queueItemStateController == null) {
      _createQueueItemStateStream();
    }
    _queueItemStateController!.add(state);
  }

  @override
  String toString() => 'QueueItem{completer: $completer, task: $task, timeout: $timeout, onComplete: $onComplete, _timedOut: $_timedOut}';
}
