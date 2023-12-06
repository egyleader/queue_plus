/// NOTE: This is a modified version of the queue package
library;

import 'dart:async';
import 'dart:collection';

import 'package:queue_plus/src/enums/queue_item_state.dart';
import 'package:queue_plus/src/enums/queue_state.dart';
import 'package:queue_plus/src/models/exceptions/queue_cancelled_exception.dart';
import 'package:queue_plus/src/models/queue_item.dart';

/// {@template QueuePlus}
/// Queue to execute Futures in order, It awaits each future before executing the next one.
/// - follows the FIFO (First In First Out) principle
/// - eache queue item has a [QueueItemState] for each item to know the state of the item .
/// - has a [QueueState] to represent the sending state of the whole queue.
/// - eache queue item has a [SendingProgress] to represent the sending progress of the whole queue.
/// - has a progress % for the whole queue to represent the sending state of the bag
///? - has a [DateTime estimatedTime] to represent the estimated time of completion for the whole queue
/// - has methods to add/remove items to the queue
/// - has methods to pause/cancel the queue
///
/// {@endtemplate}
class QueuePlus<E> {
  /// {@macro QueuePlus}
  QueuePlus({this.delay, this.parallel = 1, this.timeout, this.onComplete});

  final Queue<QueueItem<E>> _queuedItems = Queue();

  /// The number of items that have been processed ,
  /// useful for having multiple processes running at the same time
  final Queue<QueueItem<E>> _activeItems = Queue();

  /// A delay to await between each future.
  final Duration? delay;

  /// A timeout before making the item as Failed
  ///  processing the next item in the queue
  final Duration? timeout;

  /// queue length
  int get length => _activeItems.length + _queuedItems.length;

  /// if the queue is empty
  bool get isEmpty => _activeItems.length + _queuedItems.length == 0;

  /// callback to be executed when the queue is completed
  final Future<void> Function()? onComplete;

  /// ============================================
  ///              Queue Minpulation
  ///=============================================

  /// Adds the future-returning closure to the queue.
  /// Will throw an exception if the queue has been cancelled.
  Future<E> add(QueueItem<E> item) {
    if (_cancelled) throw QueueCancelledException();
    _queuedItems.add(item);
    _updateRemainingItemsStream();
    unawaited(_process());
    return item.completer.future;
  }

  Future<void> remove<T>(QueueItem<E> item) async {
    if (_cancelled) throw QueueCancelledException();
    _queuedItems.remove(item);
    _activeItems.remove(item);
    unawaited(_process());
  }

  /// ============================================
  ///                Processing
  ///=============================================

  /// The number of items to process at one time
  /// Can be edited mid processing
  int parallel;

  /// Handles the number of parallel tasks firing at any one time
  Future<void> _process() async => _activeItems.length < parallel ? _queueUpNextItem() : null;

  void _queueUpNextItem() {
    if (_queuedItems.isEmpty || _cancelled || _paused || _activeItems.length > parallel) {
      if (_activeItems.isEmpty && _queuedItems.isEmpty) _finishQueueProcessing();
      return;
    }

    final item = _queuedItems.removeFirst();
    _addOnItemComplete(item);
    _activeItems.add(item);
    _updateQueueStateStream(QueueState.processing);
    unawaited(item.execute());
  }

  void _addOnItemComplete(QueueItem<E> item) {
    item.onComplete = () async {
      _activeItems.remove(item);
      _updateRemainingItemsStream();
      _updateQueueStateStream(QueueState.idle); // to update the state to idle if there is a delay
      if (delay != null) await Future<E>.delayed(delay!);
      _queueUpNextItem();
    };
  }

  /// ============================================
  ///                Queue Pausing
  ///=============================================

  /// pauses the queue from processing any more items , but does not cancel the queue
  /// helpful for pausing the queue and resuming it on some condition (connection lost ..etc)

  bool _paused = false;
  bool get isPaused => _paused;

  void pause() {
    _paused = true;
    _updateQueueStateStream(QueueState.paused);
  }

  void resume() {
    _paused = false;
    _updateQueueStateStream(QueueState.idle); // to update the state to idle if there is no item in the queue
    _process();
  }

  /// ============================================
  ///          Queue Cancelling & disposing
  ///=============================================
  /// Cancels the queue. Also cancels any unprocessed items throwing a [QueueCancelledException]
  /// Subsquent calls to [add] will throw.
  /// useful for cancelling the queue on demand (user cancle sending to device ..etc ).
  ///

  bool _cancelled = false;

  /// Cancels the queue. Also cancels any unprocessed items throwing a [QueueCancelledException]
  ///
  /// Subsquent calls to [add] will throw.
  void cancel() {
    for (final item in _queuedItems) {
      item.completer.completeError(QueueCancelledException());
    }
    _queuedItems.removeWhere((item) => item.completer.isCompleted);
    _cancelled = true;
    _updateQueueStateStream(QueueState.cancelled);
  }

  /// This will run the [cancel] function and close the remaining items stream
  /// To gracefully exit the queue, waiting for items to complete first,
  /// call `await Queue.finished;` before disposing
  void dispose() {
    cancel();
    _remainingItemsController?.close();
    _queueStateController?.close();
  }

  /// ============================================
  ///              Queue Status Stream
  ///=============================================

  StreamController<QueueState>? _queueStateController;

  // created lazily to avoid creating a stream that is never listened to.
  Stream<QueueState> get queueState {
    if (_queueStateController == null) {
      _createQueueStateStream();
    }

    return _queueStateController!.stream;
  }

  void _createQueueStateStream() {
    _queueStateController = StreamController<QueueState>();
    _queueStateController!.add(QueueState.idle);
  }

  void _updateQueueStateStream(QueueState state) {
    if (_queueStateController == null) {
      _createQueueStateStream();
    }
    _queueStateController!.add(state);
  }

  /// ============================================
  ///              Remaining Items Stream
  ///=============================================
  StreamController<int>? _remainingItemsController;

  Stream<int> get remainingItems {
    if (_remainingItemsController == null) {
      _createRemainingItemsStream();
    }

    return _remainingItemsController!.stream;
  }

  // created lazily to avoid creating a stream that is never listened to.
  void _createRemainingItemsStream() {
    _remainingItemsController = StreamController<int>();
    _remainingItemsController!.add(_queuedItems.length + _activeItems.length);
  }

  void _updateRemainingItemsStream() {
    if (_remainingItemsController == null) {
      _createRemainingItemsStream();
    }
    _remainingItemsController!.add(_queuedItems.length + _activeItems.length);
  }

  /// ============================================
  ///                  Queue completion
  ///=============================================

  final List<Completer<void>> _completeListeners = [];

  Future<void> _finishQueueProcessing() async {
    await onComplete?.call(); // execute the onComplete callback
    // End Queue by completing all listeners
    // this is to make sure that the queue is completed even if the user didn't listen to the onComplete callback
    for (final completer in _completeListeners) {
      if (completer.isCompleted != true) {
        completer.complete();
      }
    }
    _completeListeners.clear();
    // update queue stats
    _updateRemainingItemsStream();
    _updateQueueStateStream(QueueState.idle);
  }

  /// Resolve when all items are complete
  ///
  /// Returns a future that will resolve when all items in the queue have
  /// finished processing
  /// useful for waiting for the queue to finish processing before doing something else.
  /// example: "await queue.finished;"
  Future<E> get finished {
    final completer = Completer<E>();
    _completeListeners.add(completer);
    return completer.future;
  }

  /// ============================================
  ///                  helpers & utils
  ///=============================================

  @override
  String toString() =>
      'QueuePlus{delay: $delay, parallel: $parallel, timeout: $timeout, _queuedItems: ${_queuedItems.length}, _activeItems: ${_activeItems.length}, _paused: $_paused, _cancelled: $_cancelled}';
}
