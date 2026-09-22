import {
  THREE,
  createRuntimeCommandDispatcher,
  getRuntimeInfo,
  isRuntimeCanceledError,
  installRuntimeBridge,
  postRuntimeEvent,
  RuntimeSpeechController,
  RuntimeFaceController,
  RuntimeGazeController,
  RuntimeMotionController,
  RuntimeCameraController,
  RuntimeSceneController,
  RuntimeBackgroundController,
  RuntimeGraphicsController,
  VrmModelLoader,
  VrmAnimationLoader,
  VrmModelSession,
} from './main';
// Подавляем безвредные предупреждения от @pixiv/three-vrm-animation для старых vrma файлов
const originalConsoleWarn = console.warn;
console.warn = function (...args) {
  if (typeof args[0] === 'string' && args[0].includes('Unknown VRMC_vrm_animation spec version')) {
    return; // Игнорируем это предупреждение
  }
  originalConsoleWarn.apply(console, args);
};

class VrmRunner {
  constructor() {
    if (!this.isWebGLAvailable()) {
      this.notifyFlutter('onError', { message: 'WebGL not supported on this device/webview.' });
      return;
    }

    this.container = document.getElementById('canvas-container');
    this.sceneController = null;
    this.cameraController = null;

    this.modelLoader = new VrmModelLoader();
    this.animationLoader = new VrmAnimationLoader();
    this.motionController = new RuntimeMotionController({
      getVrm: () => this.currentVrm,
      getTransitions: () => this.modelSession?.motionTransitions ?? null,
      finalizeRestPose: () => this.finalizeRestPose(),
      onStarted: (event) => this.notifyFlutter('onAnimationStarted', event),
      onFinished: (event) => this.notifyFlutter('onAnimationFinished', event),
    });
    // Вместо устаревшего THREE.Clock используем нативный performance.now()
    this.lastTime = performance.now();
    this.elapsedTime = 0;

    // Explicit eye gaze and automatic saccades are independent of pointer input.
    this.gazeController = new RuntimeGazeController(() => this.currentVrm);

    this.faceController = new RuntimeFaceController({
      getVrm: () => this.currentVrm,
      applySpeechAmplitude: (manager) => this.speechController.applyAmplitude(manager),
      onExpressionChanged: (name, layer) =>
        this.notifyFlutter('onExpressionChanged', { expression: name, layer }),
    });

    // Dynamic Bounding Box
    this.modelBoundingWidth = 0.6;
    this.modelBoundingHeight = 1.6;

    // Lip Sync & Audio Amplitude
    this.speechController = new RuntimeSpeechController({
      clearMouth: () => this.clearExpressionLayer('mouth'),
      setMouthExpression: (name, weight, duration) =>
        this.setExpression(name, 'mouth', weight, duration),
      onFinished: (sessionId) =>
        this.notifyFlutter('onSpeechFinished', { sessionId }),
    });

    this.windConfig = { type: 'light', direction: 'right' };
    this.currentWindIntensity = 0.0;
    this.targetWindIntensity = 0.0;

    // Pre-allocated temporary objects to avoid per-frame GC pressure
    this._tmpVec3A = new THREE.Vector3();
    this._tmpVec3B = new THREE.Vector3();
    this._tmpVec3C = new THREE.Vector3();
    // Custom Camera Panning
    this.isDragging = false;
    this.dragStartPoint = new THREE.Vector2();
    this.controlsStartPos = new THREE.Vector3();

    // Graphics and Performance state
    this._isRenderingPaused = false;
    this._animationFrameId = null;
    this._isDisposed = false;
    this._pointerEventCanvas = null;
    this._onWindowResize = () => this.onWindowResize();
    this._onPointerDown = (event) => this.onPointerDown(event);
    this._onPointerMove = (event) => this.onPointerMove(event);
    this._onPointerUp = (event) => this.onPointerUp(event);
    this._onControlsStart = () => {
      this.cameraController.markCustomTransform();
    };
    this._onControlsEnd = () => {
      this.cameraController.captureControlsTransform();
      if (this.cameraController.mode === 'constrained') this.notifyCameraChanged(true);
    };
    this._onPageHide = () => this.dispose();
    this._detachRuntimeBridge = null;

    this.initScene();
    this.backgroundController = new RuntimeBackgroundController({
      style: document.body.style,
      setCanvasBackground: (colorHex, transparent) =>
        this.sceneController.setCanvasBackground(colorHex, transparent),
    });
    this.modelSession = new VrmModelSession(this.scene);
    this.graphicsController = new RuntimeGraphicsController({
      scene: this.sceneController,
      recreateRenderer: (antialias) => this._recreateRenderer(antialias),
      setPhysicsEnabled: (enabled) => this.modelSession.setPhysicsEnabled(enabled),
      onPerformance: (snapshot) => this.notifyFlutter('onPerformance', snapshot),
      devicePixelRatio: () => window.devicePixelRatio,
    }, this.lastTime);
    this.initEvents();
    this.animate();

    this.notifyFlutter('onStateChanged', { state: 'initialized' });
  }

  isWebGLAvailable() {
    try {
      const canvas = document.createElement('canvas');
      return !!(window.WebGLRenderingContext && (canvas.getContext('webgl') || canvas.getContext('experimental-webgl')));
    } catch (e) {
      return false;
    }
  }

  /**
   * Инициализация базовой 3D сцены Three.js, камеры, света и контроллера вращения
   */
  initScene() {
    this.sceneController = new RuntimeSceneController({
      container: this.container,
      lookAtTarget: this.gazeController.target,
      antialias: true,
      onControlsStart: this._onControlsStart,
      onControlsEnd: this._onControlsEnd,
      onContextLost: () => this.onWebGlContextLost(),
      onContextRestored: () => this.onWebGlContextRestored(),
    });
    this.cameraController = new RuntimeCameraController(this.camera, this.controls);
  }

  get scene() {
    return this.sceneController.scene;
  }

  get camera() {
    return this.sceneController.camera;
  }

  get renderer() {
    return this.sceneController.renderer;
  }

  get controls() {
    return this.sceneController.controls;
  }

  get enablePhysics() {
    return this.graphicsController?.physicsEnabled ?? true;
  }

  get fpsCap() {
    return this.graphicsController?.fpsCap ?? 60;
  }

  get speechTimeline() {
    return this.speechController.timeline;
  }

  get lipSyncAmplitude() {
    return this.speechController.amplitude;
  }

  set lipSyncAmplitude(amplitude) {
    this.speechController.setAmplitude(amplitude);
  }

  initEvents() {
    window.addEventListener('resize', this._onWindowResize);
    window.addEventListener('pagehide', this._onPageHide);
    this.attachPointerEvents();

    this._detachRuntimeBridge = installRuntimeBridge({
      executeCommand: createRuntimeCommandDispatcher(this),
      dispose: () => this.dispose(),
      isDisposed: () => this._isDisposed,
    });
  }

  onPointerDown(e) {
    if (e.isPrimary) {
      this.isDragging = true;
      this.dragStartPoint.set(e.clientX, e.clientY);
      this.controlsStartPos.copy(this.controls.target);
    }
  }

  onPointerMove(e) {
    if (!this.isDragging || !e.isPrimary) return;
    this.cameraController.setConstrainedPanTarget({
      deltaX: e.clientX - this.dragStartPoint.x,
      deltaY: e.clientY - this.dragStartPoint.y,
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
      startTarget: this.controlsStartPos,
      modelHeight: this.modelBoundingHeight || 1.6,
    });
  }

  onPointerUp(e) {
    if (!e.isPrimary) return;

    if (this.isDragging) {
      this.isDragging = false;

      // Check if it was a tap or a drag (dist < 10 pixels is a tap)
      const dist = Math.hypot(e.clientX - this.dragStartPoint.x, e.clientY - this.dragStartPoint.y);
      if (dist < 10 && e.type === 'pointerup' && this.currentVrm) {
        this.notifyFlutter('onTap', { x: e.clientX, y: e.clientY });
      } else if (this.cameraController.mode === 'constrained') {
        this.notifyCameraChanged(true);
      }
    }
  }

  attachPointerEvents() {
    this.detachPointerEvents();
    const domElement = this.renderer.domElement;
    this._pointerEventCanvas = domElement;
    domElement.addEventListener('pointerdown', this._onPointerDown);
    domElement.addEventListener('pointermove', this._onPointerMove);
    domElement.addEventListener('pointerup', this._onPointerUp);
    domElement.addEventListener('pointercancel', this._onPointerUp);
  }

  detachPointerEvents() {
    const domElement = this._pointerEventCanvas;
    if (!domElement) return;
    domElement.removeEventListener('pointerdown', this._onPointerDown);
    domElement.removeEventListener('pointermove', this._onPointerMove);
    domElement.removeEventListener('pointerup', this._onPointerUp);
    domElement.removeEventListener('pointercancel', this._onPointerUp);
    this._pointerEventCanvas = null;
  }

  onWindowResize() {
    const width = window.innerWidth;
    const height = window.innerHeight;
    this.sceneController.resize(width, height);

    // Автоматически пересчитываем позицию камеры под новые пропорции экрана (без анимации)
    // Только если пользователь еще не двигал камеру вручную!
    // Передаем resetPosition = false, чтобы избежать сброса физики при открытии клавиатуры
    if (!this.cameraController.hasCustomTransform) {
      this.frameAvatar(0, false);
    }
  }

  setShadows(enabled) {
    this.sceneController.setShadows(enabled);
  }

  async loadModelFromUrl(url) {
    try {
      const loaded = await this.modelLoader.load(url, (progress) => {
        this.notifyFlutter('onModelLoadProgress', progress);
      });
      this._setupLoadedVrm(loaded.gltf, loaded.sourceBytes);
    } catch (error) {
      if (!isRuntimeCanceledError(error)) {
        this.notifyFlutter('onError', {
          message: error instanceof Error ? error.message : String(error),
        });
      }
      throw error;
    }
  }

  cancelModelLoad() {
    this.modelLoader.cancel();
  }

  cancelAnimationLoad() {
    this.animationLoader.cancel();
  }

  _setupLoadedVrm(gltf, sourceBytes) {
    const vrm = gltf.userData.vrm;
    if (!vrm) {
      throw new Error('Failed to parse a VRM model from the glTF container.');
    }
    if (this.currentVrm) this.unloadModel();

    const report = this.modelSession.attach(vrm, {
      sourceBytes,
      lookAtTarget: this.gazeController.target,
      physicsEnabled: this.enablePhysics,
      shadowsEnabled: this.renderer.shadowMap.enabled,
      onAnimationFinished: (event) => {
        this.notifyFlutter('onAnimationFinished', event);
      },
    });
    this.motionController.resetModelState();
    this.modelBoundingHeight = report.height;
    this.frameAvatar(0);

    this.notifyFlutter('onModelLoaded', {
      name: report.name,
      version: report.vrmVersion,
    });
    this.notifyFlutter('onModelReport', report);
  }

  get currentVrm() {
    return this.modelSession?.currentVrm ?? null;
  }

  get mixer() {
    return this.modelSession?.mixer ?? null;
  }

  get modelReport() {
    return this.modelSession?.modelReport ?? null;
  }
  getRuntimeHealth() {
    const runtimeInfo = getRuntimeInfo();
    const capabilities = this.renderer?.capabilities;
    return {
      ...runtimeInfo,
      webGlVersion: capabilities?.isWebGL2 ? 2 : 1,
      maxTextureSize: capabilities?.maxTextureSize || 0,
      maxTextures: capabilities?.maxTextures || 0,
      maxVertexTextures: capabilities?.maxVertexTextures || 0,
      modelLoaded: Boolean(this.currentVrm),
      // A fade-out remains active after currentAction is cleared, until the
      // retiring action has reached the normalized rest pose.
      animationActive: this.motionController.isActive,
      animationPaused: this.motionController.isPaused,
      renderingPaused: Boolean(this._isRenderingPaused),
      contextLost: this.sceneController.contextLost,
    };
  }

  unloadModel() {
    this.cancelAnimationLoad();
    this.cancelSpeech();
    if (!this.currentVrm) return;

    this.clearAllExpressions();
    if (!this.modelSession.detach()) return;
    this.motionController.resetModelState();
    this.cameraController.clearCustomTransform();

    this.gazeController.resetForModel();

    this.notifyFlutter('onModelUnloaded', {});
  }
  async playAnimationFromUrl(url, options = {}) {
    if (!this.currentVrm || !this.mixer) {
      throw new Error('Load a VRM model before playing an animation.');
    }
    try {
      await this.animationLoader.load(url, (gltf) => {
        this.motionController.playLoadedAnimation(gltf, options);
      });
    } catch (error) {
      if (!isRuntimeCanceledError(error)) {
        this.notifyFlutter('onError', {
          message: error instanceof Error ? error.message : String(error),
        });
      }
      throw error;
    }
  }

  getPose() {
    return this.motionController.getPose();
  }

  setPose(pose, fadeDuration) {
    this.motionController.setPose(pose, fadeDuration);
  }

  pauseAnimation() {
    this.motionController.pause();
  }

  resumeAnimation(speed) {
    this.motionController.resume(speed);
  }

  setAnimationSpeed(speed) {
    this.motionController.setSpeed(speed);
  }

  transitionToRest(fadeDuration = 0.5) {
    this.motionController.transitionToRest(fadeDuration);
  }

  finalizeRestPose() {
    if (!this.currentVrm?.humanoid) return;
    this.currentVrm.humanoid.resetNormalizedPose();
    this.currentVrm.update(0);
    this.currentVrm.scene.updateMatrixWorld(true);
  }

  get customBlendShapes() {
    return this.faceController.customBlendShapes;
  }

  get autoBlinkEnabled() {
    return this.faceController.autoBlinkEnabled;
  }

  set autoBlinkEnabled(value) {
    this.faceController.autoBlinkEnabled = value;
  }

  setExpression(expressionName, layerName = 'eyes', targetWeight = 1.0, durationSec = 0.25, disableAutoBlink = false) {
    this.faceController.setExpression(expressionName, layerName, targetWeight, durationSec, disableAutoBlink);
  }

  clearExpressionLayer(layerName) {
    this.faceController.clearExpressionLayer(layerName);
  }

  clearAllExpressions() {
    if (this.faceController.clearAllExpressions()) {
      this.speechController.resetAmplitude();
    }
  }

  setViseme(visemeName, weight = 1.0) {
    this.faceController.setViseme(visemeName, weight);
  }

  enqueueSpeechVisemes(payload) {
    this.speechController.enqueueVisemes(payload);
  }

  enqueueSpeechAmplitudes(payload) {
    this.speechController.enqueueAmplitudes(payload);
  }

  beginSpeech(payload) {
    return this.speechController.begin(payload);
  }

  appendSpeechVisemes(sessionId, frames) {
    this.speechController.appendVisemes(sessionId, frames);
  }

  appendSpeechAmplitudes(sessionId, frames) {
    this.speechController.appendAmplitudes(sessionId, frames);
  }

  finishSpeech(sessionId, audioDurationMs) {
    this.speechController.finish(sessionId, audioDurationMs);
  }

  cancelSpeech(sessionId) {
    return this.speechController.cancel(sessionId);
  }

  // ==========================================
  // ПРЕСЕТЫ И РЕЖИМЫ КАМЕРЫ
  // ==========================================

  frameAvatar(durationMs = 500, resetPosition = true) {
    if (this.cameraController.frameAvatar(
      this.currentVrm,
      this.elapsedTime || 0,
      durationMs,
      resetPosition,
    )) {
      this.notifyCameraChanged(false);
    }
  }

  /**
   * Устанавливает режим управления камерой (characterCreator или free)
   * @param {string} mode Режим камеры
   */
  setCameraMode(mode) {
    this.cameraController.setMode(mode);
  }

  resetCamera(durationMs = 500) {
    if (this.cameraController.reset(
      this.currentVrm,
      durationMs,
      this.elapsedTime || 0,
    )) {
      this.notifyCameraChanged(false);
    }
  }

  setLighting(config) {
    this.sceneController.setLighting(config);
  }


  setPhysics(stiffnessMultiplier = 1.0, gravityMultiplier = 1.0, dragMultiplier = 1.0) {
    if (!this.currentVrm || !this.currentVrm.springBoneManager) return;
    const joints = this.currentVrm.springBoneManager.joints || [];
    for (const joint of joints) {
      if (!joint.userData) joint.userData = {};

      // Save original values on first edit
      if (joint.userData.initialStiffness === undefined) {
        joint.userData.initialStiffness = joint.settings.stiffness || 0;
        joint.userData.initialGravityPower = joint.settings.gravityPower || 0;
        joint.userData.initialDragForce = joint.settings.dragForce || 0;
      }

      joint.settings.stiffness = joint.userData.initialStiffness * stiffnessMultiplier;
      joint.settings.gravityPower = joint.userData.initialGravityPower * gravityMultiplier;
      joint.userData.modifiedGravityPower = joint.settings.gravityPower;
      joint.settings.dragForce = joint.userData.initialDragForce * dragMultiplier;
    }
  }

  setWind(type, direction) {
    if (!this.targetWindVec) {
      this.targetWindVec = new THREE.Vector3(0, 0, 0);
      this.currentWindVec = new THREE.Vector3(0, 0, 0);
      this.targetWindVariation = 0;
      this.currentWindVariation = 0;
    }

    if (type === 'none') {
      this.targetWindVec.set(0, 0, 0);
      this.targetWindVariation = 0;
      return;
    }

    let baseForce = 0;
    let variation = 0;
    switch (type) {
      case 'light': baseForce = 0.05; variation = 0.03; break;
      case 'strong': baseForce = 0.15; variation = 0.1; break;
      case 'storm': baseForce = 0.3; variation = 0.25; break;
    }

    this.targetWindVariation = variation;

    switch (direction) {
      case 'left': this.targetWindVec.set(1, 0, 0); break;
      case 'right': this.targetWindVec.set(-1, 0, 0); break;
      case 'front': this.targetWindVec.set(0, 0, -1); break;
      case 'back': this.targetWindVec.set(0, 0, 1); break;
    }

    this.targetWindVec.multiplyScalar(baseForce);
  }

  stopWind() {
    if (!this.targetWindVec) return;
    this.targetWindVec.set(0, 0, 0);
    this.targetWindVariation = 0;
  }

  setEnvironmentColor(colorHex, intensity = 0.5) {
    this.sceneController.setEnvironmentColor(colorHex, intensity);
  }

  setBackground(colorHex, imageUrl, transparent, hostedImage = false) {
    return this.backgroundController.setBackground(colorHex, imageUrl, transparent, hostedImage);
  }

  setRenderQuality(pixelRatio) {
    // Устаревшая функция, сохранена для обратной совместимости
    this.setGraphicsSettings({ pixelRatio: pixelRatio });
  }

  setGraphicsSettings(settings) {
    this.graphicsController.setSettings(settings);
  }

  setGraphicsPreset(preset) {
    this.graphicsController.setPreset(preset);
  }

  setAdaptiveQuality(settings) {
    this.graphicsController.setAdaptiveQuality(settings);
  }

  getPerformanceSnapshot() {
    return this.graphicsController.getSnapshot();
  }

  onWebGlContextLost() {
    this.notifyFlutter('onWebGLContextChanged', { state: 'lost' });
  }

  onWebGlContextRestored() {
    this.lastTime = performance.now();
    this.graphicsController.resetTiming(this.lastTime);
    this.notifyFlutter('onWebGLContextChanged', { state: 'restored' });
  }

  _recreateRenderer(antialias) {
    if (this._isDisposed) return;
    this.detachPointerEvents();
    try {
      if (this.sceneController.recreateRenderer(antialias)) {
        this.cameraController.replaceControls(this.controls);
      }
    } finally {
      this.attachPointerEvents();
    }
  }

  dispose() {
    if (this._isDisposed) return;
    this._isDisposed = true;
    this.pauseRendering();
    this.cancelModelLoad();
    this.cancelAnimationLoad();
    this.backgroundController.dispose();

    window.removeEventListener('resize', this._onWindowResize);
    window.removeEventListener('pagehide', this._onPageHide);
    this._detachRuntimeBridge?.();
    this._detachRuntimeBridge = null;

    if (this.currentVrm) this.unloadModel();
    this.detachPointerEvents();
    this.sceneController.dispose();
  }

  pauseRendering() {
    this._isRenderingPaused = true;
    if (this._animationFrameId) {
      cancelAnimationFrame(this._animationFrameId);
      this._animationFrameId = null;
    }
  }

  resumeRendering() {
    if (this._isRenderingPaused) {
      this._isRenderingPaused = false;
      this.lastTime = performance.now();
      this.graphicsController.resetTiming(this.lastTime);
      this.animate();
    }
  }

  animate() {
    if (this._isRenderingPaused || this._isDisposed) return;
    this._animationFrameId = requestAnimationFrame(() => this.animate());

    const now = performance.now();
    if (this.sceneController.contextLost) return;
    if (!this.graphicsController.shouldRender(now)) return;

    let delta = (now - this.lastTime) / 1000;
    if (delta > 0.1) delta = 0.1; // Ограничение скачков при лагах (10 fps min)
    this.lastTime = now;
    this.elapsedTime += delta;

    const elapsedTime = this.elapsedTime;

    this.motionController.update(delta);

    if (this.currentVrm) {
      this.speechController.update();
      this.faceController.updateExpressions(delta);
      this.faceController.updateBlink(delta);
      this.gazeController.update(delta);

      // Плавное следование камеры (Pan) за пальцем без изменения угла
      this.cameraController.updatePanFollowing(delta);

      // Wind Simulation
      if (this.currentVrm.springBoneManager && this.enablePhysics) {
        if (!this.currentWindVec) {
          this.currentWindVec = new THREE.Vector3(0, 0, 0);
          this.targetWindVec = new THREE.Vector3(0, 0, 0);
          this.currentWindVariation = 0;
          this.targetWindVariation = 0;
        }

        const windLerpSpeed = 1.5;
        const windLerpFactor = 1.0 - Math.exp(-windLerpSpeed * delta);
        this.currentWindVec.lerp(this.targetWindVec, windLerpFactor);
        this.currentWindVariation += (this.targetWindVariation - this.currentWindVariation) * windLerpFactor;

        this._tmpVec3A.set(0, 0, 0);

        if (this.currentWindVec.lengthSq() > 0.000001 || this.currentWindVariation > 0.001) {
          const time = this.elapsedTime;
          let fluctuation = (
            Math.sin(time * 1.13) * 0.4 +
            Math.sin(time * 2.71) * 0.3 +
            Math.sin(time * 4.33) * 0.2 +
            Math.sin(time * 7.97) * 0.1
          );

          this._tmpVec3B.copy(this.currentWindVec).normalize();
          if (this._tmpVec3B.lengthSq() === 0) {
            this._tmpVec3B.set(1, 0, 0);
          }

          this._tmpVec3B.multiplyScalar(fluctuation * this.currentWindVariation);
          this._tmpVec3A.copy(this.currentWindVec).add(this._tmpVec3B);
        }

        const joints = this.currentVrm.springBoneManager.joints || [];
        for (const joint of joints) {
          if (!joint.userData) joint.userData = {};
          if (joint.userData.initialGravityDir === undefined) {
            joint.userData.initialGravityDir = joint.settings.gravityDir.clone();
            joint.userData.initialGravityPower = joint.settings.gravityPower || 0;
          }

          const currentBasePower = joint.userData.modifiedGravityPower !== undefined ? joint.userData.modifiedGravityPower : joint.userData.initialGravityPower;

          this._tmpVec3C.copy(joint.userData.initialGravityDir).multiplyScalar(currentBasePower);
          this._tmpVec3C.add(this._tmpVec3A);

          if (this._tmpVec3C.lengthSq() > 0.000001) {
            joint.settings.gravityPower = this._tmpVec3C.length();
            joint.settings.gravityDir.copy(this._tmpVec3C).normalize();
          } else {
            joint.settings.gravityPower = 0;
            joint.settings.gravityDir.copy(joint.userData.initialGravityDir);
          }
        }
      }

      this.currentVrm.update(delta);
    }

    this.cameraController.updateAnimation(elapsedTime);

    this.sceneController.updateAndRender();
    this.graphicsController.recordFrame(now);
  }
  getAvatarTransform() {
    if (!this.currentVrm) {
      throw new Error('A VRM model must be loaded before reading camera state.');
    }
    return this.cameraController.getTransform();
  }

  notifyCameraChanged(userInitiated) {
    if (!this.currentVrm) return;
    this.notifyFlutter('onCameraChanged', {
      ...this.getAvatarTransform(),
      userInitiated: Boolean(userInitiated),
    });
  }

  setAvatarTransform(data) {
    this.cameraController.setTransform(data);
  }

  notifyFlutter(eventName, payload) {
    if (this._isDisposed) return;
    postRuntimeEvent(eventName, payload);
  }
}

window.addEventListener('DOMContentLoaded', () => {
  new VrmRunner();
});
