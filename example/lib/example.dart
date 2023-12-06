import 'dart:async';
import 'package:queue_plus/queue_plus.dart';

// in this example there is 2 queues:
// first queue with 1 parrarel processing (by default) and each process take 1 second
// second queue with 3 parallel processing  and each process take differnt time.
// eache queue has a listener to the remaining items count 
// the output will be:
    // Queue 1 Remaining items: 0
    // Queue 2 Remaining items: 0
    // Queue 1 Remaining items: 1
    // Queue 2 Remaining items: 1
    // Queue 1 Remaining items: 2
    // Queue 2 Remaining items: 2
    // Queue 1 Remaining items: 3
    // Queue 2 Remaining items: 3
    // Queue1: 1
    // Queue 1 Remaining items: 2
    // Queue2: 1
    // Queue 2 Remaining items: 2
    // Queue2: 3
    // Queue 2 Remaining items: 1
    // Queue1: 2
    // Queue 1 Remaining items: 1
    // Queue2: 2
    // Queue 2 completed
    // Queue 2 Remaining items: 0
    // Queue 2 Remaining items: 0
    // Queue1: 3
    // Queue 1 completed
    // Exited.

void main() async {
  QueuePlus<void> queue = QueuePlus(onComplete: () async => print('Queue 1 completed'));
  var queue1itemsListener = queue.remainingItems.listen((count) {
    print('Queue 1 Remaining items: $count');
  });
  queue.add(QueueItem(task: () async => Future.delayed(Duration(seconds: 1), () => print('Queue1: 1'))));
  queue.add(QueueItem(task: () async => Future.delayed(Duration(seconds: 1), () => print('Queue1: 2'))));
  queue.add(QueueItem(task: () async => Future.delayed(Duration(seconds: 1), () => print('Queue1: 3'))));

  // second queue with 3 parallel process and each process take differnt time
  //
  // output:
  // Queue3: 1
  // Queue2: 3
  // Queue2: 2
  // Queue 2 completed
  QueuePlus<void> queue2 = QueuePlus(parallel: 3, onComplete: () async => print('Queue 2 completed'));
  var queue2itemsListener = queue2.remainingItems.listen((count) {
    print('Queue 2 Remaining items: $count');
  });
  queue2.add(QueueItem(task: () async => Future.delayed(Duration(seconds: 1), () => print('Queue2: 1'))));
  queue2.add(QueueItem(task: () async => Future.delayed(Duration(seconds: 3), () => print('Queue2: 2'))));
  queue2.add(QueueItem(task: () async => Future.delayed(Duration(seconds: 1), () => print('Queue2: 3'))));

  await queue.finished;
  await queue2.finished;
  queue1itemsListener.cancel();
  queue2itemsListener.cancel();
  queue.dispose();
}
