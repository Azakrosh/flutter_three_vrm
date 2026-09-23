import {
  createRuntimeCommandDispatcher,
  getRuntimeInfo,
  isRuntimeCanceledError,
  installRuntimeBridge,
  postRuntimeEvent,
  RuntimeSpeechController,
  RuntimeFaceController,
  RuntimeGazeController,
  RuntimeWindPhysicsController,
  RuntimePointerController,
  RuntimeFrameScheduler,
  RuntimePageLifecycle,
  RuntimeMotionController,
  RuntimeCameraController,
  RuntimeSceneController,
  RuntimeBackgroundController,
  RuntimeGraphicsController,
  VrmModelLoader,
  VrmAnimationLoader,
  VrmModelSession,
} from "./main";
import type {
  LoadedVrm,
  RuntimeCommandHost,
  RuntimeCommandPayload,
  RuntimeEventName,
  RuntimeGraphicsSettings,
  RuntimeGraphicsPreset,
  RuntimeLightingConfig,
  RuntimeCameraMode,
  RuntimeCameraTransform,
  RuntimePerformanceSnapshot,
  RuntimePose,
  AdaptiveQualityConfig,
  RuntimeRecord,
} from "./main";
import type { RuntimeFrame } from "./frame-scheduler";
import type {
  SpeechAmplitudeFrame,
  SpeechVisemeFrame,
} from "./speech-timeline";
// Подавляем безвредные предупреждения от @pixiv/three-vrm-animation для старых vrma файлов
const originalConsoleWarn = console.warn;
console.warn = function (...args) {
  if (typeof args[0] === 'string' && args[0].includes('Unknown VRMC_vrm_animation spec version')) {
    return; // Игнорируем это предупреждение
  }
  originalConsoleWarn.apply(console, args);
};

class VrmRunner implements RuntimeCommandHost {
  private readonly container!: HTMLElement;
  private readonly modelLoader!: VrmModelLoader;
  private readonly animationLoader!: VrmAnimationLoader;
  private readonly motionController!: RuntimeMotionController;
  public readonly gazeController!: RuntimeGazeController;
  private readonly windPhysicsController!: RuntimeWindPhysicsController;
  private readonly faceController!: RuntimeFaceController;
  private readonly speechController!: RuntimeSpeechController;
  private readonly pointerController!: RuntimePointerController;
  private readonly backgroundController!: RuntimeBackgroundController;
  private readonly modelSession!: VrmModelSession;
  private readonly graphicsController!: RuntimeGraphicsController;
  private readonly frameScheduler!: RuntimeFrameScheduler;
  private readonly pageLifecycle!: RuntimePageLifecycle;
  private sceneController!: RuntimeSceneController;
  private cameraController!: RuntimeCameraController;
  private modelBoundingHeight = 1.6;
  private readonly _onControlsStart!: () => void;
  private readonly _onControlsEnd!: () => void;
  private _detachRuntimeBridge: (() => void) | null = null;

  constructor() {
    if (!this.isWebGLAvailable()) {
      this.notifyFlutter('onError', { message: 'WebGL not supported on this device/webview.' });
      return;
    }

    const container = document.getElementById("canvas-container");
    if (container === null) {
      this.notifyFlutter("onError", {
        message: "Runtime canvas container was not found.",
      });
      return;
    }
    this.container = container;

    this.modelLoader = new VrmModelLoader();
    this.animationLoader = new VrmAnimationLoader();
    this.motionController = new RuntimeMotionController({
      getVrm: () => this.currentVrm,
      getTransitions: () => this.modelSession?.motionTransitions ?? null,
      finalizeRestPose: () => this.finalizeRestPose(),
      onStarted: (event) => this.notifyFlutter('onAnimationStarted', event),
      onFinished: (event) => this.notifyFlutter('onAnimationFinished', event),
    });
    const startTime = performance.now();

    // Explicit eye gaze and automatic saccades are independent of pointer input.
    this.gazeController = new RuntimeGazeController(() => this.currentVrm);
    this.windPhysicsController = new RuntimeWindPhysicsController({
      getManager: () => this.modelSession?.springBoneManager ?? null,
      isPhysicsEnabled: () => this.enablePhysics,
    });

    this.faceController = new RuntimeFaceController({
      getVrm: () => this.currentVrm,
      applySpeechAmplitude: (manager) => this.speechController.applyAmplitude(manager),
      onExpressionChanged: (name, layer) =>
        this.notifyFlutter('onExpressionChanged', { expression: name, layer }),
    });

    // Lip Sync & Audio Amplitude
    this.speechController = new RuntimeSpeechController({
      clearMouth: () => this.clearExpressionLayer('mouth'),
      setMouthExpression: (name, weight, duration) =>
        this.setExpression(name, 'mouth', weight, duration),
      onFinished: (sessionId) =>
        this.notifyFlutter('onSpeechFinished', { sessionId }),
    });

    // Graphics and Performance state
    this._onControlsStart = () => {
      this.cameraController.markCustomTransform();
    };
    this._onControlsEnd = () => {
      this.cameraController.captureControlsTransform();
      if (this.cameraController.mode === 'constrained') this.notifyCameraChanged(true);
    };
    this.initScene();
    this.pointerController = new RuntimePointerController({
      camera: this.cameraController,
      getControlsTarget: () => this.controls.target,
      getModelHeight: () => this.modelBoundingHeight || 1.6,
      hasModel: () => Boolean(this.currentVrm),
      getViewport: () => ({ width: window.innerWidth, height: window.innerHeight }),
      onTap: (x, y) => this.notifyFlutter('onTap', { x, y }),
      onCameraChanged: () => this.notifyCameraChanged(true),
    });
    this.backgroundController = new RuntimeBackgroundController({
      style: document.body.style,
      setCanvasBackground: (colorHex, transparent) =>
        this.sceneController.setCanvasBackground(colorHex, transparent),
    });
    this.modelSession = new VrmModelSession(this.scene);
    this.graphicsController = new RuntimeGraphicsController({
      scene: this.sceneController,
      recreateRenderer: (antialias) => this.recreateRenderer(antialias),
      setPhysicsEnabled: (enabled) => this.modelSession.setPhysicsEnabled(enabled),
      onPerformance: (snapshot) => this.notifyFlutter('onPerformance', snapshot),
      devicePixelRatio: () => window.devicePixelRatio,
    }, startTime);
    this.frameScheduler = new RuntimeFrameScheduler({
      now: () => performance.now(),
      requestFrame: (callback) => window.requestAnimationFrame(callback),
      cancelFrame: (id) => window.cancelAnimationFrame(id),
      shouldRender: (now) => this.graphicsController.shouldRender(now),
      isContextLost: () => this.sceneController.contextLost,
      resetGraphicsTiming: (now) => this.graphicsController.resetTiming(now),
      onFrame: (frame) => this.renderFrame(frame),
    }, startTime);
    this.pageLifecycle = new RuntimePageLifecycle({
      page: window,
      getViewport: () => ({ width: window.innerWidth, height: window.innerHeight }),
      resizeScene: (width, height) => this.sceneController.resize(width, height),
      hasCustomCameraTransform: () => this.cameraController.hasCustomTransform,
      frameAvatar: () => this.frameAvatar(0, false),
      cleanupSteps: [
        () => this.frameScheduler.dispose(),
        () => this.cancelModelLoad(),
        () => this.cancelAnimationLoad(),
        () => this.backgroundController.dispose(),
        () => {
          this._detachRuntimeBridge?.();
          this._detachRuntimeBridge = null;
        },
        () => { if (this.currentVrm) this.unloadModel(); },
        () => this.pointerController.detach(),
        () => this.sceneController.dispose(),
      ],
    });
    this.initEvents();
    this.frameScheduler.start();

    this.notifyFlutter('onStateChanged', { state: 'initialized' });
  }

  private isWebGLAvailable(): boolean {
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
  private initScene(): void {
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

  get elapsedTime() {
    return this.frameScheduler?.elapsedTime ?? 0;
  }

  get isDisposed() {
    return this.pageLifecycle?.isDisposed ?? false;
  }

  get speechTimeline() {
    return this.speechController.timeline;
  }

  get lipSyncAmplitude() {
    return this.speechController.amplitude;
  }

  public set lipSyncAmplitude(amplitude: number) {
    this.speechController.setAmplitude(amplitude);
  }

  private initEvents(): void {
    this.pageLifecycle.attach();
    this.pointerController.attach(this.renderer.domElement);

    this._detachRuntimeBridge = installRuntimeBridge({
      executeCommand: createRuntimeCommandDispatcher(this),
      dispose: () => this.dispose(),
      isDisposed: () => this.isDisposed,
    });
  }

  public setShadows(enabled: boolean): void {
    this.sceneController.setShadows(enabled);
  }

  public async loadModelFromUrl(url: string): Promise<void> {
    try {
      const loaded = await this.modelLoader.load(url, (progress) => {
        this.notifyFlutter('onModelLoadProgress', progress);
      });
      this.setupLoadedVrm(loaded.vrm, loaded.sourceBytes);
    } catch (error) {
      if (!isRuntimeCanceledError(error)) {
        this.notifyFlutter('onError', {
          message: error instanceof Error ? error.message : String(error),
        });
      }
      throw error;
    }
  }

  public cancelModelLoad(): void {
    this.modelLoader.cancel();
  }

  public cancelAnimationLoad(): void {
    this.animationLoader.cancel();
  }

  private setupLoadedVrm(vrm: LoadedVrm, sourceBytes: number): void {
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
  public getRuntimeHealth(): RuntimeRecord {
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
      renderingPaused: this.frameScheduler.isPaused,
      contextLost: this.sceneController.contextLost,
    };
  }

  public unloadModel(): void {
    this.cancelAnimationLoad();
    this.cancelSpeech();
    if (!this.currentVrm) return;

    this.clearAllExpressions();
    if (!this.modelSession.detach()) return;
    this.motionController.resetModelState();
    this.cameraController.clearCustomTransform();

    this.gazeController.resetForModel();
    this.windPhysicsController.resetForModel();

    this.notifyFlutter('onModelUnloaded', {});
  }
  public async playAnimationFromUrl(
    url: string,
    options: RuntimeRecord = {},
  ): Promise<void> {
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

  public getPose(): RuntimePose {
    return this.motionController.getPose();
  }

  public setPose(pose: RuntimePose, fadeDuration: number): void {
    this.motionController.setPose(pose, fadeDuration);
  }

  public pauseAnimation(): void {
    this.motionController.pause();
  }

  public resumeAnimation(speed: number): void {
    this.motionController.resume(speed);
  }

  public setAnimationSpeed(speed: number): void {
    this.motionController.setSpeed(speed);
  }

  public transitionToRest(fadeDuration = 0.5): void {
    this.motionController.transitionToRest(fadeDuration);
  }

  private finalizeRestPose(): void {
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

  public set autoBlinkEnabled(value: boolean) {
    this.faceController.autoBlinkEnabled = value;
  }

  public setExpression(
    expressionName: string,
    layerName = "eyes",
    targetWeight = 1,
    durationSec = 0.25,
    disableAutoBlink = false,
  ): void {
    this.faceController.setExpression(expressionName, layerName, targetWeight, durationSec, disableAutoBlink);
  }

  public clearExpressionLayer(layerName: string): void {
    this.faceController.clearExpressionLayer(layerName);
  }

  public clearAllExpressions(): void {
    if (this.faceController.clearAllExpressions()) {
      this.speechController.resetAmplitude();
    }
  }

  public setViseme(visemeName: string, weight = 1): void {
    this.faceController.setViseme(visemeName, weight);
  }

  public enqueueSpeechVisemes(
    payload: RuntimeCommandPayload<"enqueueSpeechVisemes">,
  ): void {
    this.speechController.enqueueVisemes(payload);
  }

  public enqueueSpeechAmplitudes(
    payload: RuntimeCommandPayload<"enqueueSpeechAmplitudes">,
  ): void {
    this.speechController.enqueueAmplitudes(payload);
  }

  public beginSpeech(
    payload: RuntimeCommandPayload<"beginSpeech">,
  ): boolean {
    return this.speechController.begin(payload);
  }

  public appendSpeechVisemes(
    sessionId: string,
    frames: readonly SpeechVisemeFrame[],
  ): void {
    this.speechController.appendVisemes(sessionId, frames);
  }

  public appendSpeechAmplitudes(
    sessionId: string,
    frames: readonly SpeechAmplitudeFrame[],
  ): void {
    this.speechController.appendAmplitudes(sessionId, frames);
  }

  public finishSpeech(sessionId: string, audioDurationMs: number): void {
    this.speechController.finish(sessionId, audioDurationMs);
  }

  public cancelSpeech(sessionId?: string): void {
    this.speechController.cancel(sessionId);
  }

  // ==========================================
  // ПРЕСЕТЫ И РЕЖИМЫ КАМЕРЫ
  // ==========================================

  private frameAvatar(durationMs = 500, resetPosition = true): void {
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
  public setCameraMode(mode: RuntimeCameraMode): void {
    this.cameraController.setMode(mode);
  }

  public resetCamera(durationMs = 500): void {
    if (this.cameraController.reset(
      this.currentVrm,
      durationMs,
      this.elapsedTime || 0,
    )) {
      this.notifyCameraChanged(false);
    }
  }

  public setLighting(config: RuntimeRecord): void {
    this.sceneController.setLighting(config as RuntimeLightingConfig);
  }


  public setPhysics(
    stiffnessMultiplier = 1,
    gravityMultiplier = 1,
    dragMultiplier = 1,
  ): void {
    this.windPhysicsController.setPhysics(stiffnessMultiplier, gravityMultiplier, dragMultiplier);
  }

  public setWind(type: string, direction: string): void {
    this.windPhysicsController.setWind(type, direction);
  }

  public stopWind(): void {
    this.windPhysicsController.stopWind();
  }

  public setEnvironmentColor(colorHex: string, intensity = 0.5): void {
    this.sceneController.setEnvironmentColor(colorHex, intensity);
  }

  public setBackground(
    colorHex: string,
    imageUrl: string | null | undefined,
    transparent: boolean,
    hostedImage = false,
  ): Promise<void> {
    return this.backgroundController.setBackground(colorHex, imageUrl, transparent, hostedImage);
  }

  public setRenderQuality(pixelRatio: number): void {
    // Устаревшая функция, сохранена для обратной совместимости
    this.setGraphicsSettings({ pixelRatio: pixelRatio });
  }

  public setGraphicsSettings(settings: RuntimeGraphicsSettings): void {
    this.graphicsController.setSettings(settings);
  }

  public setGraphicsPreset(preset: RuntimeGraphicsPreset): void {
    this.graphicsController.setPreset(preset);
  }

  public setAdaptiveQuality(
    settings: Partial<AdaptiveQualityConfig>,
  ): void {
    this.graphicsController.setAdaptiveQuality(settings);
  }

  public getPerformanceSnapshot(): RuntimePerformanceSnapshot {
    return this.graphicsController.getSnapshot();
  }

  private onWebGlContextLost(): void {
    this.notifyFlutter('onWebGLContextChanged', { state: 'lost' });
  }

  private onWebGlContextRestored(): void {
    this.frameScheduler.resetTiming();
    this.notifyFlutter('onWebGLContextChanged', { state: 'restored' });
  }

  private recreateRenderer(antialias: boolean): void {
    if (this.isDisposed) return;
    this.pointerController.detach();
    try {
      if (this.sceneController.recreateRenderer(antialias)) {
        this.cameraController.replaceControls(this.controls);
      }
    } finally {
      this.pointerController.attach(this.renderer.domElement);
    }
  }

  private dispose(): void {
    this.pageLifecycle.dispose();
  }

  public pauseRendering(): void {
    this.frameScheduler.pause();
  }

  public resumeRendering(): void {
    this.frameScheduler.resume();
  }

  private renderFrame({ now, delta, elapsedTime }: RuntimeFrame): void {
    this.motionController.update(delta);

    if (this.currentVrm) {
      this.speechController.update();
      this.faceController.updateExpressions(delta);
      this.faceController.updateBlink(delta);
      this.gazeController.update(delta);

      // Плавное следование камеры (Pan) за пальцем без изменения угла
      this.cameraController.updatePanFollowing(delta);

      this.windPhysicsController.update(delta, elapsedTime);

      this.currentVrm.update(delta);
    }

    this.cameraController.updateAnimation(elapsedTime);

    this.sceneController.updateAndRender();
    this.graphicsController.recordFrame(now);
  }

  public getAvatarTransform(): RuntimeCameraTransform {
    if (!this.currentVrm) {
      throw new Error('A VRM model must be loaded before reading camera state.');
    }
    return this.cameraController.getTransform();
  }

  private notifyCameraChanged(userInitiated: boolean): void {
    if (!this.currentVrm) return;
    this.notifyFlutter('onCameraChanged', {
      ...this.getAvatarTransform(),
      userInitiated: Boolean(userInitiated),
    });
  }

  public setAvatarTransform(data: RuntimeCameraTransform): void {
    this.cameraController.setTransform(data);
  }

  private notifyFlutter(
    eventName: RuntimeEventName,
    payload: object,
  ): void {
    if (this.isDisposed) return;
    postRuntimeEvent(
      eventName,
      payload as Readonly<Record<string, unknown>>,
    );
  }
}

window.addEventListener('DOMContentLoaded', () => {
  new VrmRunner();
});
