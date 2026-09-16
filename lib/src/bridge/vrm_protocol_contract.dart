/// Internal command names shared with the web runtime protocol contract.
enum VrmProtocolCommand {
  loadModelFromUrl,
  cancelModelLoad,
  getModelReport,
  getRuntimeHealth,
  unloadModel,
  playAnimationFromUrl,
  cancelAnimationLoad,
  pauseAnimation,
  resumeAnimation,
  pauseRendering,
  resumeRendering,
  stopAnimation,
  setAnimationSpeed,
  getPose,
  setPose,
  resetPose,
  setShadows,
  setExpression,
  clearExpressionLayer,
  clearAllExpressions,
  setCustomBlendShape,
  setLipSyncAmplitude,
  setViseme,
  enqueueSpeechVisemes,
  enqueueSpeechAmplitudes,
  beginSpeech,
  appendSpeechVisemes,
  appendSpeechAmplitudes,
  finishSpeech,
  cancelSpeech,
  setAutoBlink,
  setLookAtTarget,
  setAutoSaccades,
  setLookAtConfig,
  setCameraMode,
  resetCamera,
  getTransform,
  setTransform,
  setLighting,
  setBackground,
  setPhysics,
  stopWind,
  setWind,
  setEnvironmentColor,
  setGraphicsSettings,
  setGraphicsPreset,
  setAdaptiveQuality,
  getPerformanceSnapshot,
  setRenderQuality,
}

/// Internal event names shared with the web runtime protocol contract.
enum VrmProtocolEvent {
  onModelLoaded,
  onModelLoadProgress,
  onModelReport,
  onModelUnloaded,
  onAnimationStarted,
  onAnimationFinished,
  onExpressionChanged,
  onSpeechFinished,
  onError,
  onStateChanged,
  onCameraChanged,
  onPerformance,
  onWebGlContextChanged,
  onTap,
}

extension VrmProtocolEventWireName on VrmProtocolEvent {
  String get wireName => switch (this) {
    VrmProtocolEvent.onWebGlContextChanged => 'onWebGLContextChanged',
    _ => name,
  };
}

VrmProtocolEvent? vrmProtocolEventFromWireName(String wireName) {
  for (final event in VrmProtocolEvent.values) {
    if (event.wireName == wireName) return event;
  }
  return null;
}
