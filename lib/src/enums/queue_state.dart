enum QueueState {
  /// The queue is just starting or finished processing all items
  idle, 
  /// The queue is currently processing items
  processing,

  /// The queue is currently paused
  paused,

  /// The queue has been cancelled
  cancelled,
}
