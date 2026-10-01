/// Possible states of a [VrmAnimationQueue].
enum VrmAnimationQueueState {
  /// Queue is idle — no queue-managed animation is playing.
  stopped,

  /// Queue is actively playing animations in sequence.
  playing,

  /// Queue is paused — current animation finishes, next one won't start
  /// until [VrmAnimationQueue.resume] is called.
  paused,

  /// A priority animation interrupted the queue via [VrmAnimationQueue.interrupt].
  /// After the priority animation finishes, the queue resumes automatically.
  interrupted,
}
