// ignore_for_file: public_member_api_docs

class QueueCancelledException implements Exception {
  QueueCancelledException();
  final String message = 'Queue has been cancelled and cannot be used , please create a new queue';

  @override
  String toString() => message;
}
