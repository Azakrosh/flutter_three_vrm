import {
  AdaptiveQualityController,
  GLTFLoader,
  OrbitControls,
  THREE,
  VRMAnimationLoaderPlugin,
  VRMLookAtQuaternionProxy,
  VRMUtils,
  createVRMAnimationClip,
  createHumanoidAnimationClip,
  createRuntimeCommandDispatcher,
  createRuntimeCanceledError,
  fetchRuntimeResource,
  getRuntimeInfo,
  isRuntimeCanceledError,
  installRuntimeBridge,
  postRuntimeEvent,
  SpeechTimeline,
  RuntimeCameraController,
  VrmModelLoader,
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
    this.scene = null;
    this.camera = null;
    this.renderer = null;
    this.controls = null;
    this.ambientLight = null;
    this.directionalLight = null;
    this.rimLight = null;

    this.pendingRestPoseReset = false;
    this.poseSequence = 0;
    this.modelLoader = new VrmModelLoader();
    this.animationLoadAbortController = null;
    this.backgroundLoadAbortController = null;
    this.animationLoadGeneration = 0;
    this.backgroundLoadGeneration = 0;
    this.backgroundObjectUrl = null;

    // Вместо устаревшего THREE.Clock используем нативный performance.now()
    this.lastTime = performance.now();
    this.elapsedTime = 0;

    // LookAt & Touch Interaction
    this.lookAtTarget = new THREE.Object3D();
    this.defaultLookAtPos = new THREE.Vector3(0, 1.4, 2.1);
    this.desiredLookAtPos = new THREE.Vector3(0, 1.4, 2.1);
    this.lookAtTimer = 0;
    this.saccadeEnabled = true;
    this.saccadeTimer = 0;
    this.targetSaccadeOffset = new THREE.Vector3(0, 0, 0);
    this.currentSaccadeOffset = new THREE.Vector3(0, 0, 0);
    this.lookAtHoldDurationSec = 1.0; // Уменьшил длительность реакции с 1.8 до 1.0
    this.lookAtBodyDeadZoneX = 0.35;

    // Procedural Head Tracking (Additive Blending)
    this.targetHeadYaw = 0;
    this.targetHeadPitch = 0;
    this.proceduralHeadYaw = 0;
    this.proceduralHeadPitch = 0;

    this.neckBaseQuat = new THREE.Quaternion();
    this.headBaseQuat = new THREE.Quaternion();
    this.chestBaseQuat = new THREE.Quaternion(); // Базовая позиция для плеч (груди)
    this.baseBonesSaved = false;

    // Multi-Layer Expressions & Crossfader
    this.activeExpressions = {};
    this.expressionLayers = {
      eyes: { name: null, targetWeight: 0, currentWeight: 0, duration: 0.25 },
      mouth: { name: null, targetWeight: 0, currentWeight: 0, duration: 0.1 },
      brows: { name: null, targetWeight: 0, currentWeight: 0, duration: 0.25 }
    };
    this.customBlendShapes = new Map();

    // Dynamic Bounding Box
    this.modelBoundingWidth = 0.6;
    this.modelBoundingHeight = 1.6;

    // Lip Sync & Audio Amplitude
    this.lipSyncAmplitude = 0.0;
    this.smoothLipSyncAmplitude = 0.0;
    this.speechTimeline = new SpeechTimeline();

    // Micro-movements
    this.autoBlinkEnabled = true;
    this.blinkTimer = 0;
    this.nextBlinkInterval = 3.0;
    this.isBlinking = false;
    this.blinkProgress = 0;

    // Animation Action
    this.isAnimationPaused = false;

    this.windConfig = { type: 'light', direction: 'right' };
    this.currentWindIntensity = 0.0;
    this.targetWindIntensity = 0.0;

    // Pre-allocated temporary objects to avoid per-frame GC pressure
    this._tmpVec3A = new THREE.Vector3();
    this._tmpVec3B = new THREE.Vector3();
    this._tmpVec3C = new THREE.Vector3();
    this._tmpEuler = new THREE.Euler();
    this._tmpQuatAdditive = new THREE.Quaternion();
    this._tmpQuatChest = new THREE.Quaternion();
    this._tmpQuatNeckHead = new THREE.Quaternion();
    // Custom Camera Panning
    this.isDragging = false;
    this.dragStartPoint = new THREE.Vector2();
    this.controlsStartPos = new THREE.Vector3();

    // Head Tracking
    this.targetHeadYaw = 0;
    this.targetHeadPitch = 0;
    this.proceduralHeadYaw = 0;
    this.proceduralHeadPitch = 0;

    this.raycaster = new THREE.Raycaster();

    // Graphics and Performance state
    this.currentAntialias = true;
    this.enablePhysics = true;
    this.fpsCap = 60;
    this.lastFrameTime = 0;
    this.adaptiveQuality = new AdaptiveQualityController();
    this.performanceWindowStart = performance.now();
    this.performanceFrameCount = 0;
    this.lastPerformanceReport = 0;
    this.performanceSnapshot = {
      fps: 0,
      frameTimeMs: 0,
      pixelRatio: Math.min(window.devicePixelRatio, 1.5),
      fpsCap: this.fpsCap,
      physicsEnabled: this.enablePhysics,
      adaptiveQualityEnabled: this.adaptiveQuality.config.enabled,
      drawCalls: 0,
      triangles: 0,
      geometries: 0,
      textures: 0,
      reason: 'initialized',
    };
    this._contextLost = false;
    this._isRenderingPaused = false;
    this._animationFrameId = null;
    this._isDisposed = false;
    this._pointerEventCanvas = null;
    this._rendererEventCanvas = null;
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
    this._onWebGlContextLost = (event) => this.onWebGlContextLost(event);
    this._onWebGlContextRestored = () => this.onWebGlContextRestored();
    this._onPageHide = () => this.dispose();
    this._detachRuntimeBridge = null;

    this.initScene();
    this.modelSession = new VrmModelSession(this.scene);
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
    this.scene = new THREE.Scene();

    const aspect = window.innerWidth / window.innerHeight;

    // Перспективная камера с расширенным углом обзора (FOV = 36), чтобы персонаж аккуратно вписывался в сцену
    this.camera = new THREE.PerspectiveCamera(36, aspect, 0.1, 20.0);
    // Начальная позиция камеры: по умолчанию режим 'upperBody'
    this.camera.position.set(0, 1.05, 1.9);

    // Добавляем невидимый таргет взгляда (LookAt)
    this.scene.add(this.lookAtTarget);
    this.lookAtTarget.position.set(0, 1.4, 2.1);

    // Рендерер WebGL с поддержкой прозрачности (alpha: true), без премультиплицированного альфа-канала (premultipliedAlpha: false) для чистого сглаживания
    this.renderer = new THREE.WebGLRenderer({
      alpha: true,
      antialias: this.currentAntialias,
      premultipliedAlpha: false,
      // ВНИМАНИЕ: preserveDrawingBuffer отключен для повышения производительности (экономит ~20-30% CPU на мобильных).
      // Если понадобится делать скриншоты (toDataURL), раскомментируйте или установите в true.
      preserveDrawingBuffer: false
    });
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;

    this.renderer.shadowMap.enabled = false;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.container.appendChild(this.renderer.domElement);
    this.attachRendererContextEvents();

    // Орбитальный контроллер вращения модели (OrbitControls)
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.target.set(0, 0.95, 0); // Фокус 'upperBody'
    this.attachControlsEvents();
    this.cameraController = new RuntimeCameraController(this.camera, this.controls);

    // Источники света: рассеянный (Ambient), прямой (Directional) и контурный (Rim)
    this.ambientLight = new THREE.AmbientLight(0xffffff, 1.2);
    this.scene.add(this.ambientLight);

    this.directionalLight = new THREE.DirectionalLight(0xffffff, 1.0);
    this.directionalLight.position.set(1.0, 2.0, 1.5);

    // Настройка теней
    this.directionalLight.castShadow = true;
    this.directionalLight.shadow.mapSize.width = 2048;
    this.directionalLight.shadow.mapSize.height = 2048;
    this.directionalLight.shadow.camera.near = 0.5;
    this.directionalLight.shadow.camera.far = 10;
    this.directionalLight.shadow.camera.left = -1.5;
    this.directionalLight.shadow.camera.right = 1.5;
    this.directionalLight.shadow.camera.top = 2.0;
    this.directionalLight.shadow.camera.bottom = -0.5;
    this.directionalLight.shadow.bias = -0.001;
    this.scene.add(this.directionalLight);

    this.rimLight = new THREE.DirectionalLight(0xffffff, 0.6);
    this.rimLight.position.set(-1.0, 1.5, -1.5);
    this.scene.add(this.rimLight);
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

  attachControlsEvents() {
    this.controls.addEventListener('start', this._onControlsStart);
    this.controls.addEventListener('end', this._onControlsEnd);
  }

  detachControlsEvents() {
    if (!this.controls) return;
    this.controls.removeEventListener('start', this._onControlsStart);
    this.controls.removeEventListener('end', this._onControlsEnd);
  }

  onPointerDown(e) {
    if (e.isPrimary) {
      this.isDragging = true;
      this.dragStartPoint.set(e.clientX, e.clientY);
      this.controlsStartPos.copy(this.controls.target);

      // Reset LookAt on drag start
      this.desiredLookAtPos.copy(this.defaultLookAtPos);
      this.lookAtTimer = 0;
      this.targetHeadYaw = 0;
      this.targetHeadPitch = 0;
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
      if (dist < 10) {
        this.handleScreenTap(e.clientX, e.clientY);
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
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(width, height);

    // Автоматически пересчитываем позицию камеры под новые пропорции экрана (без анимации)
    // Только если пользователь еще не двигал камеру вручную!
    // Передаем resetPosition = false, чтобы избежать сброса физики при открытии клавиатуры
    if (!this.cameraController.hasCustomTransform) {
      this.frameAvatar(0, false);
    }
  }

  handleScreenTap(clientX, clientY) {
    if (!this.currentVrm || !this.currentVrm.humanoid) return;

    // Нормализованные координаты экрана от -1 до +1
    const x = (clientX / window.innerWidth) * 2 - 1;
    const y = -(clientY / window.innerHeight) * 2 + 1;

    // Устанавливаем луч из камеры в точку клика
    this.raycaster.setFromCamera(new THREE.Vector2(x, y), this.camera);

    // Получаем мировые позиции головы и груди для создания "мертвой зоны"
    const headNode = this.currentVrm.humanoid.getNormalizedBoneNode('head') || this.currentVrm.humanoid.getRawBoneNode('head');
    const chestNode = this.currentVrm.humanoid.getNormalizedBoneNode('chest') || this.currentVrm.humanoid.getRawBoneNode('chest');

    if (!headNode || !chestNode) return;

    const headPos = new THREE.Vector3();
    headNode.getWorldPosition(headPos);

    // Находим плоскость, параллельную экрану, ТОЧНО на глубине модели
    const plane = new THREE.Plane(new THREE.Vector3(0, 0, 1), -headPos.z);

    const exactIntersect = new THREE.Vector3();
    this.raycaster.ray.intersectPlane(plane, exactIntersect);

    if (!exactIntersect) return;



    // Сдвигаем точку на 1 метр к камере для нативного VRM LookAt, 
    // чтобы избежать сильного косоглазия (Cross-eye)
    const lookTarget = exactIntersect.clone();
    lookTarget.z += 1.0;
    this.desiredLookAtPos.copy(lookTarget);

    this.lookAtTimer = this.lookAtHoldDurationSec;

    // Процедурный поворот: вычисляем углы между головой и точкой клика в 3D
    const deltaX = exactIntersect.x - headPos.x;

    // ИСПРАВЛЕНИЕ УГЛА: headPos.y - это шея/низ головы. Глаза модели находятся выше (примерно на 10см).
    // Чтобы модель смотрела горизонтально при клике на уровне её глаз, 
    // мы считаем вертикальную дельту (deltaY) от уровня глаз, а не от шеи.
    const eyeLevelY = headPos.y + 0.05;
    const deltaY = exactIntersect.y - eyeLevelY;

    // Максимальные углы поворота головы
    const maxYaw = THREE.MathUtils.degToRad(40);
    const maxPitch = THREE.MathUtils.degToRad(30);

    // Рассчитываем углы и ограничиваем их
    // Z-дистанция в наших вычислениях условно 1.0 (сдвиг lookTarget.z)
    let computedYaw = Math.atan2(deltaX, 1.0);
    let computedPitch = Math.atan2(deltaY, 1.0);

    this.targetHeadYaw = Math.max(-maxYaw, Math.min(maxYaw, computedYaw));
    this.targetHeadPitch = Math.max(-maxPitch, Math.min(maxPitch, computedPitch));

    this.notifyFlutter('onTap', { x: clientX, y: clientY });
  }

  setShadows(enabled) {
    if (this.renderer.shadowMap.enabled === enabled) return;

    this.renderer.shadowMap.enabled = enabled;
    if (this.directionalLight) {
      this.directionalLight.castShadow = enabled;
    }

    // Обновляем материалы на всей сцене, чтобы они скомпилировались с поддержкой теней (или без)
    this.scene.traverse((child) => {
      if (child.isMesh) {
        child.castShadow = enabled;
        child.receiveShadow = enabled;
        if (child.material) {
          // Если у меша массив материалов
          if (Array.isArray(child.material)) {
            child.material.forEach(mat => mat.needsUpdate = true);
          } else {
            child.material.needsUpdate = true;
          }
        }
      }
    });

    // Обязательно очищаем кэш шейдеров и перерисовываем, если сцена статична
    this.renderer.clear();
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
    if (this.animationLoadAbortController) this.animationLoadAbortController.abort();
    this.animationLoadAbortController = null;
    this.animationLoadGeneration += 1;
  }

  cancelBackgroundLoad() {
    if (this.backgroundLoadAbortController) this.backgroundLoadAbortController.abort();
    this.backgroundLoadAbortController = null;
    this.backgroundLoadGeneration += 1;
  }

  _setupLoadedVrm(gltf, sourceBytes) {
    const vrm = gltf.userData.vrm;
    if (!vrm) {
      throw new Error('Failed to parse a VRM model from the glTF container.');
    }
    if (this.currentVrm) this.unloadModel();

    const report = this.modelSession.attach(vrm, {
      sourceBytes,
      lookAtTarget: this.lookAtTarget,
      physicsEnabled: this.enablePhysics,
      shadowsEnabled: this.renderer.shadowMap.enabled,
      onAnimationFinished: (event) => {
        this.notifyFlutter('onAnimationFinished', event);
      },
    });
    this.pendingRestPoseReset = false;
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

  get motionTransitions() {
    return this.modelSession?.motionTransitions ?? null;
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
      animationActive: Boolean(this.motionTransitions?.isActive),
      animationPaused: Boolean(this.isAnimationPaused),
      renderingPaused: Boolean(this._isRenderingPaused),
      contextLost: Boolean(this._contextLost),
    };
  }

  unloadModel() {
    this.cancelSpeech();
    if (!this.currentVrm) return;

    this.clearAllExpressions();
    if (!this.modelSession.detach()) return;
    this.pendingRestPoseReset = false;
    this.cameraController.clearCustomTransform();

    this.baseBonesSaved = false;
    this.neckBaseQuat.identity();
    this.headBaseQuat.identity();
    this.chestBaseQuat.identity();
    this.targetHeadYaw = 0;
    this.targetHeadPitch = 0;
    this.proceduralHeadYaw = 0;
    this.proceduralHeadPitch = 0;
    this.lookAtTimer = 0;
    this.desiredLookAtPos.copy(this.defaultLookAtPos);

    this.notifyFlutter('onModelUnloaded', {});
  }
  async playAnimationFromUrl(url, options = {}) {
    if (!this.currentVrm || !this.mixer) {
      throw new Error('Load a VRM model before playing an animation.');
    }
    this.cancelAnimationLoad();
    const generation = ++this.animationLoadGeneration;
    const abortController = new AbortController();
    this.animationLoadAbortController = abortController;
    const loader = new GLTFLoader();
    loader.register((parser) => new VRMAnimationLoaderPlugin(parser));

    try {
      const resource = await fetchRuntimeResource(url, abortController.signal);
      const isJson = resource.contentType.includes('json') || new URL(url).pathname.toLowerCase().endsWith('.gltf');
      const input = isJson ? new TextDecoder().decode(resource.data) : resource.data;
      const gltf = await loader.parseAsync(input, new URL('.', url).href);
      try {
        if (abortController.signal.aborted || generation !== this.animationLoadGeneration) {
          throw createRuntimeCanceledError('Animation loading was canceled.');
        }
        this._playLoadedAnimation(gltf, options);
      } finally {
        if (gltf.scene) VRMUtils.deepDispose(gltf.scene);
      }
    } catch (error) {
      if (abortController.signal.aborted || error?.name === 'AbortError' || error?.code === 'canceled') {
        throw createRuntimeCanceledError('Animation loading was canceled.');
      }
      this.notifyFlutter('onError', {
        message: error instanceof Error ? error.message : String(error),
      });
      throw error;
    } finally {
      if (this.animationLoadAbortController === abortController) {
        this.animationLoadAbortController = null;
      }
    }
  }

  _playLoadedAnimation(gltf, options) {
    const playbackId = options.playbackId;
    if (typeof playbackId !== 'string' || playbackId.length === 0) {
      throw new TypeError('playbackId must be a non-empty string.');
    }
    let clip = null;

    if (gltf.userData.vrmAnimations && gltf.userData.vrmAnimations.length > 0) {
      try {
        // Создаем Proxy для управления глазами, если его еще нет (устраняет предупреждение в консоли)
        if (this.currentVrm && this.currentVrm.lookAt && !this.currentVrm.lookAt.quaternionProxy) {
          this.currentVrm.lookAt.quaternionProxy = new VRMLookAtQuaternionProxy(this.currentVrm.lookAt);
          this.currentVrm.lookAt.quaternionProxy.name = 'lookAtQuaternionProxy';
          this.currentVrm.scene.add(this.currentVrm.lookAt.quaternionProxy);
        }

        clip = createVRMAnimationClip(gltf.userData.vrmAnimations[0], this.currentVrm);
      } catch (vrmaErr) {
        console.warn('createVRMAnimationClip error:', vrmaErr);
      }
    }

    if (!clip && gltf.animations && gltf.animations.length > 0) {
      const sourceClip = options.clipName
        ? THREE.AnimationClip.findByName(gltf.animations, options.clipName)
        : gltf.animations[0];
      if (!sourceClip) {
        throw new Error(`Animation clip was not found: ${options.clipName}`);
      }
      clip = createHumanoidAnimationClip(gltf.scene, sourceClip, this.currentVrm, {
        rootMotion: options.rootMotion,
      });
    }

    if (!clip) {
      throw new Error('No VRMA or glTF animation clip was found.');
    }

    if (!this.motionTransitions) {
      throw new Error('Animation mixer is not initialized.');
    }
    const loop = options.loop !== undefined ? options.loop : true;
    const speed = options.speed || 1.0;
    const fadeDuration = options.fadeDuration ?? 0.5;
    const action = this.motionTransitions.transitionTo(clip, {
      source: 'clip',
      fadeDuration,
      loop,
      speed,
    });
    action._flutterPlaybackId = playbackId;
    action._hasNotifiedFinished = false;
    this.pendingRestPoseReset = false;
    this.isAnimationPaused = false;
    this.resetProceduralMotion();
    this.motionTransitions.update(0);
    this.notifyFlutter('onAnimationStarted', {
      name: clip.name,
      playbackId,
    });
  }

  get currentAction() {
    return this.motionTransitions?.currentAction ?? null;
  }

  transitionToRest(fadeDuration = 0.5) {
    if (!this.currentVrm || !this.motionTransitions) {
      throw new Error('Load a VRM model before stopping its motion.');
    }
    this.motionTransitions.transitionToRest(fadeDuration ?? 0.5);
    this.pendingRestPoseReset = true;
    this.isAnimationPaused = false;
    this.resetProceduralMotion();
    this.motionTransitions.update(0);
    if (!this.motionTransitions.isActive) this.finalizeRestPose();
  }

  finalizeRestPose() {
    if (!this.currentVrm?.humanoid) return;
    this.currentVrm.humanoid.resetNormalizedPose();
    this.pendingRestPoseReset = false;
    this.baseBonesSaved = false;
    this.currentVrm.update(0);
    this.currentVrm.scene.updateMatrixWorld(true);
  }

  resetProceduralMotion() {
    this.baseBonesSaved = false;
    this.neckBaseQuat.identity();
    this.headBaseQuat.identity();
    this.chestBaseQuat.identity();
    this.targetHeadYaw = 0;
    this.targetHeadPitch = 0;
    this.proceduralHeadYaw = 0;
    this.proceduralHeadPitch = 0;
  }


  setExpression(expressionName, layerName = 'eyes', targetWeight = 1.0, durationSec = 0.25, disableAutoBlink = false) {
    if (!this.expressionLayers[layerName]) return;

    // Автоматически включаем или ставим на паузу автоморгание
    this.autoBlinkEnabled = !disableAutoBlink;

    const newName = expressionName.toLowerCase();
    const mainEmotions = ['happy', 'sad', 'angry', 'surprised', 'relaxed', 'neutral'];

    // При вызове новой базовой эмоции плавно уводим все старые эмоции в targetWeight = 0.0 (crossfade out)
    if (mainEmotions.includes(newName)) {
      for (const [name, state] of Object.entries(this.activeExpressions)) {
        if (mainEmotions.includes(name) && name !== newName) {
          state.targetWeight = 0.0;
          state.duration = durationSec;
        }
      }
      for (const layer of Object.values(this.expressionLayers)) {
        if (layer.name && mainEmotions.includes(layer.name) && layer.name !== newName) {
          layer.name = null;
        }
      }
    } else {
      // Для слоевого выражения (например, blink) плавно гасим старое выражение этого слоя
      const oldName = this.expressionLayers[layerName].name;
      if (oldName && oldName !== newName && this.activeExpressions[oldName]) {
        this.activeExpressions[oldName].targetWeight = 0.0;
        this.activeExpressions[oldName].duration = durationSec;
      }
    }

    // Регистрируем новую эмоцию для плавного нарастания (crossfade in)
    if (!this.activeExpressions[newName]) {
      this.activeExpressions[newName] = {
        name: newName,
        currentWeight: 0.0,
        targetWeight: targetWeight,
        duration: durationSec
      };
    } else {
      this.activeExpressions[newName].targetWeight = targetWeight;
      this.activeExpressions[newName].duration = durationSec;
    }

    this.expressionLayers[layerName].name = newName;
    this.notifyFlutter('onExpressionChanged', { expression: expressionName, layer: layerName });
  }

  clearExpressionLayer(layerName) {
    if (!this.expressionLayers[layerName]) return;
    const oldName = this.expressionLayers[layerName].name;

    if (oldName && this.activeExpressions[oldName]) {
      this.activeExpressions[oldName].targetWeight = 0.0;
      this.activeExpressions[oldName].duration = layerName === 'mouth' ? 0.06 : 0.25;
    }

    this.expressionLayers[layerName].name = null;

    if (layerName === 'eyes') {
      this.autoBlinkEnabled = true;
    }
  }

  clearAllExpressions() {
    if (!this.currentVrm || !this.currentVrm.expressionManager) return;

    // Плавно затухаем все активные мимические эмоции
    for (const state of Object.values(this.activeExpressions)) {
      state.targetWeight = 0.0;
      state.duration = 0.25;
    }

    for (const layer of Object.values(this.expressionLayers)) {
      layer.name = null;
    }

    this.customBlendShapes.clear();
    this.lipSyncAmplitude = 0.0;
    this.smoothLipSyncAmplitude = 0.0;
    this.autoBlinkEnabled = true;
  }

  setViseme(visemeName, weight = 1.0) {
    if (!this.currentVrm || !this.currentVrm.expressionManager) return;
    if (visemeName === 'sil' || weight <= 0.001) {
      this.clearExpressionLayer('mouth');
      return;
    }
    const em = this.currentVrm.expressionManager;

    // Zero out all mouth visemes so they don't overlap or accumulate
    const visemes = ['aa', 'ih', 'ou', 'ee', 'oh'];
    for (const v of visemes) {
      try {
        em.setValue(v, 0.0);
      } catch (_) { }
    }

    const targetViseme = VrmRunner.VISEME_MAP[visemeName] || 'aa';
    this.setExpression(targetViseme, 'mouth', weight, 0.1);
  }

  enqueueSpeechVisemes(payload) {
    const frames = payload.frames;
    if (!frames || frames.length === 0) return;
    if (!this.beginSpeech(payload)) return;
    this.appendSpeechVisemes(payload.sessionId, frames);
    const audioDurationMs = frames.reduce((end, frame) => {
      return Math.max(end, Number(frame.timestampMs || 0) + Number(frame.durationMs || 0));
    }, 0);
    this.finishSpeech(payload.sessionId, audioDurationMs);
  }

  enqueueSpeechAmplitudes(payload) {
    const frames = payload.frames;
    if (!frames || frames.length === 0) return;
    if (!this.beginSpeech(payload)) return;
    this.appendSpeechAmplitudes(payload.sessionId, frames);
    const audioDurationMs = frames.reduce((end, frame) => {
      return Math.max(end, Number(frame.timestampMs || 0) + Number(frame.durationMs || 0));
    }, 0);
    this.finishSpeech(payload.sessionId, audioDurationMs);
  }

  beginSpeech(payload) {
    if (!this.speechTimeline.acceptInputRevision(payload.speechRevision)) return false;
    this.speechTimeline.begin({
      sessionId: payload.sessionId,
      mode: payload.mode,
      timelineOriginEpochMs: payload.timelineOriginEpochMs,
      nowMs: performance.now(),
      wallNowEpochMs: Date.now(),
    });
    this.resetSpeechPresentation();
    return true;
  }

  appendSpeechVisemes(sessionId, frames) {
    this.speechTimeline.appendVisemes(sessionId, frames);
  }

  appendSpeechAmplitudes(sessionId, frames) {
    this.speechTimeline.appendAmplitudes(sessionId, frames);
  }

  finishSpeech(sessionId, audioDurationMs) {
    this.speechTimeline.finish(sessionId, audioDurationMs);
  }

  cancelSpeech(sessionId) {
    const canceled = this.speechTimeline.cancel(sessionId);
    if (sessionId !== undefined && !canceled) return false;
    this.resetSpeechPresentation();
    return canceled;
  }

  resetSpeechPresentation() {
    this.lipSyncAmplitude = 0.0;
    this.smoothLipSyncAmplitude = 0.0;
    this.clearExpressionLayer('mouth');
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
    if (config.ambientIntensity !== undefined) this.ambientLight.intensity = config.ambientIntensity;
    if (config.ambientColor) this.ambientLight.color.set(config.ambientColor);
    if (config.directionalIntensity !== undefined) this.directionalLight.intensity = config.directionalIntensity;
    if (config.directionalColor) this.directionalLight.color.set(config.directionalColor);
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
    if (!this.rimLight || !this.ambientLight) return;

    // Set rim light completely to the environment color
    this.rimLight.color.set(colorHex);

    // Tint ambient light to match the environment
    const baseAmbient = new THREE.Color(0xffffff);
    const envColor = new THREE.Color(colorHex);
    this.ambientLight.color.copy(baseAmbient).lerp(envColor, intensity);
  }

  async setBackground(colorHex, imageUrl, transparent, hostedImage = false) {
    this.cancelBackgroundLoad();

    if (!imageUrl || !hostedImage) {
      this.applyBackground(colorHex, imageUrl, transparent);
      this.replaceBackgroundObjectUrl(null);
      return;
    }

    const generation = this.backgroundLoadGeneration;
    const abortController = new AbortController();
    this.backgroundLoadAbortController = abortController;
    let objectUrl = null;

    try {
      const resource = await fetchRuntimeResource(imageUrl, abortController.signal);
      if (abortController.signal.aborted || generation !== this.backgroundLoadGeneration) {
        throw createRuntimeCanceledError('Background loading was canceled.');
      }

      const blob = new Blob([resource.data], {
        type: resource.contentType || 'application/octet-stream',
      });
      objectUrl = URL.createObjectURL(blob);
      if (abortController.signal.aborted || generation !== this.backgroundLoadGeneration) {
        throw createRuntimeCanceledError('Background loading was canceled.');
      }

      this.applyBackground(colorHex, objectUrl, transparent);
      this.replaceBackgroundObjectUrl(objectUrl);
      objectUrl = null;
    } catch (error) {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
      if (
        abortController.signal.aborted ||
        generation !== this.backgroundLoadGeneration ||
        error?.name === 'AbortError' ||
        error?.code === 'canceled'
      ) {
        throw createRuntimeCanceledError('Background loading was canceled.');
      }
      throw error;
    } finally {
      if (this.backgroundLoadAbortController === abortController) {
        this.backgroundLoadAbortController = null;
      }
    }
  }

  replaceBackgroundObjectUrl(nextUrl) {
    const previousUrl = this.backgroundObjectUrl;
    this.backgroundObjectUrl = nextUrl;
    if (previousUrl && previousUrl !== nextUrl) URL.revokeObjectURL(previousUrl);
  }

  applyBackground(colorHex, imageUrl, transparent) {
    if (imageUrl) {
      // Use CSS background on document.body for optimal scaling (cover)
      document.body.style.backgroundColor = colorHex || '#000000';
      document.body.style.backgroundImage = `url(${JSON.stringify(imageUrl)})`;
      document.body.style.backgroundSize = 'cover';
      document.body.style.backgroundPosition = 'center';

      // Make WebGL canvas transparent so the CSS background is visible
      this.renderer.setClearColor(0x000000, 0);
      this.scene.background = null;
    } else {
      document.body.style.backgroundImage = 'none';

      if (transparent) {
        document.body.style.backgroundColor = 'transparent';
        this.renderer.setClearColor(0x000000, 0);
        this.scene.background = null;
      } else {
        document.body.style.backgroundColor = colorHex;
        this.renderer.setClearColor(colorHex, 1);
        this.scene.background = new THREE.Color(colorHex);
      }
    }
  }

  setRenderQuality(pixelRatio) {
    // Устаревшая функция, сохранена для обратной совместимости
    this.setGraphicsSettings({ pixelRatio: pixelRatio });
  }

  setGraphicsSettings(settings) {
    if (!settings) return;

    let needsRendererRecreate = false;

    if (settings.antialias !== undefined && settings.antialias !== this.currentAntialias) {
      this.currentAntialias = settings.antialias;
      needsRendererRecreate = true;
    }

    if (settings.enablePhysics !== undefined) {
      this.enablePhysics = settings.enablePhysics;
      this.modelSession.setPhysicsEnabled(this.enablePhysics);
    }

    if (settings.fpsCap !== undefined) {
      const requestedFps = Number(settings.fpsCap);
      if (!Number.isFinite(requestedFps) || requestedFps < 0) {
        throw new TypeError('fpsCap must be zero or a positive finite number.');
      }
      this.fpsCap = requestedFps === 0 ? 0 : THREE.MathUtils.clamp(Math.round(requestedFps), 1, 120);
      this.lastFrameTime = 0;
    }

    if (needsRendererRecreate) {
      this._recreateRenderer();
    }

    if (settings.pixelRatio !== undefined && this.renderer) {
      const requestedRatio = Number(settings.pixelRatio);
      if (!Number.isFinite(requestedRatio) || requestedRatio <= 0) {
        throw new TypeError('pixelRatio must be a positive finite number.');
      }
      this.renderer.setPixelRatio(THREE.MathUtils.clamp(requestedRatio, 0.5, 3));
      this.renderer.setSize(window.innerWidth, window.innerHeight, false);
    }
  }

  setGraphicsPreset(preset) {
    switch (preset) {
      case 'performance':
        this.setShadows(false);
        this.setGraphicsSettings({ pixelRatio: 1, antialias: false, enablePhysics: true, fpsCap: 30 });
        break;
      case 'balanced':
        this.setShadows(false);
        this.setGraphicsSettings({ pixelRatio: 1.5, antialias: true, enablePhysics: true, fpsCap: 60 });
        break;
      case 'quality':
        this.setShadows(true);
        this.setGraphicsSettings({
          pixelRatio: Math.min(window.devicePixelRatio, 2),
          antialias: true,
          enablePhysics: true,
          fpsCap: 60,
        });
        break;
      default:
        throw new TypeError(`Unknown graphics preset: ${preset}.`);
    }
    if (this.adaptiveQuality.config.enabled) {
      this.setAdaptiveQuality(this.adaptiveQuality.config);
    }
  }

  setAdaptiveQuality(settings) {
    const config = this.adaptiveQuality.configure(settings);
    const ratio = THREE.MathUtils.clamp(
      this.renderer.getPixelRatio(),
      config.minPixelRatio,
      config.maxPixelRatio,
    );
    this.renderer.setPixelRatio(ratio);
    this.renderer.setSize(window.innerWidth, window.innerHeight, false);
    this.performanceSnapshot = this.getPerformanceSnapshot('configurationChanged');
  }

  getPerformanceSnapshot(reason = this.performanceSnapshot?.reason ?? 'sample') {
    const renderInfo = this.renderer?.info;
    return {
      fps: this.performanceSnapshot?.fps ?? 0,
      frameTimeMs: this.performanceSnapshot?.frameTimeMs ?? 0,
      pixelRatio: this.renderer?.getPixelRatio() ?? 0,
      fpsCap: this.fpsCap,
      physicsEnabled: this.enablePhysics,
      adaptiveQualityEnabled: this.adaptiveQuality.config.enabled,
      drawCalls: renderInfo?.render.calls ?? 0,
      triangles: renderInfo?.render.triangles ?? 0,
      geometries: renderInfo?.memory.geometries ?? 0,
      textures: renderInfo?.memory.textures ?? 0,
      reason,
    };
  }

  recordPerformance(now) {
    this.performanceFrameCount += 1;
    const windowDuration = now - this.performanceWindowStart;
    if (windowDuration < 1000) return;

    const fps = this.performanceFrameCount * 1000 / windowDuration;
    const frameTimeMs = windowDuration / this.performanceFrameCount;
    const adjustment = this.adaptiveQuality.evaluate(
      fps,
      this.renderer.getPixelRatio(),
      this.fpsCap,
      now,
    );
    if (adjustment) {
      this.renderer.setPixelRatio(adjustment.pixelRatio);
      this.renderer.setSize(window.innerWidth, window.innerHeight, false);
    }

    this.performanceSnapshot = {
      ...this.getPerformanceSnapshot(adjustment?.reason ?? 'sample'),
      fps,
      frameTimeMs,
    };
    if (adjustment || now - this.lastPerformanceReport >= 2000) {
      this.notifyFlutter('onPerformance', this.performanceSnapshot);
      this.lastPerformanceReport = now;
    }
    this.performanceFrameCount = 0;
    this.performanceWindowStart = now;
  }

  attachRendererContextEvents() {
    this.detachRendererContextEvents();
    const canvas = this.renderer.domElement;
    this._rendererEventCanvas = canvas;
    canvas.addEventListener('webglcontextlost', this._onWebGlContextLost);
    canvas.addEventListener('webglcontextrestored', this._onWebGlContextRestored);
  }

  detachRendererContextEvents() {
    const canvas = this._rendererEventCanvas;
    if (!canvas) return;
    canvas.removeEventListener('webglcontextlost', this._onWebGlContextLost);
    canvas.removeEventListener('webglcontextrestored', this._onWebGlContextRestored);
    this._rendererEventCanvas = null;
  }

  onWebGlContextLost(event) {
    event.preventDefault();
    this._contextLost = true;
    this.notifyFlutter('onWebGLContextChanged', { state: 'lost' });
  }

  onWebGlContextRestored() {
    this._contextLost = false;
    this.lastTime = performance.now();
    this.lastFrameTime = 0;
    this.performanceWindowStart = this.lastTime;
    this.performanceFrameCount = 0;
    this.scene.traverse((child) => {
      if (!child.isMesh || !child.material) return;
      const materials = Array.isArray(child.material) ? child.material : [child.material];
      materials.forEach((material) => { material.needsUpdate = true; });
    });
    this.notifyFlutter('onWebGLContextChanged', { state: 'restored' });
  }

  _recreateRenderer() {
    if (!this.renderer || this._isDisposed) return;

    const shadowsEnabled = this.renderer.shadowMap.enabled;
    const pixelRatio = this.renderer.getPixelRatio();
    const oldCanvas = this.renderer.domElement;
    const oldTarget = this.controls.target.clone();

    this.detachPointerEvents();
    this.detachRendererContextEvents();
    this.detachControlsEvents();
    this.controls.dispose();
    this.renderer.dispose();
    this.renderer.forceContextLoss();
    if (oldCanvas.parentNode === this.container) this.container.removeChild(oldCanvas);

    this.renderer = new THREE.WebGLRenderer({
      alpha: true,
      antialias: this.currentAntialias,
      premultipliedAlpha: false,
      preserveDrawingBuffer: false
    });
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.setPixelRatio(pixelRatio);
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.renderer.shadowMap.enabled = shadowsEnabled;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;

    this.container.appendChild(this.renderer.domElement);
    this.attachRendererContextEvents();

    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.target.copy(oldTarget);
    this.attachControlsEvents();
    this.cameraController.replaceControls(this.controls);

    // Перепривязываем события к новому Canvas
    this.attachPointerEvents();

    // Заставляем материалы перекомпилироваться для нового WebGL контекста
    this.scene.traverse((child) => {
      if (child.isMesh && child.material) {
        if (Array.isArray(child.material)) {
          child.material.forEach(mat => mat.needsUpdate = true);
        } else {
          child.material.needsUpdate = true;
        }
      }
    });

    this.renderer.clear();
  }

  dispose() {
    if (this._isDisposed) return;
    this._isDisposed = true;
    this.pauseRendering();
    this.cancelModelLoad();
    this.cancelAnimationLoad();
    this.cancelBackgroundLoad();
    this.replaceBackgroundObjectUrl(null);
    document.body.style.backgroundImage = 'none';

    window.removeEventListener('resize', this._onWindowResize);
    window.removeEventListener('pagehide', this._onPageHide);
    this._detachRuntimeBridge?.();
    this._detachRuntimeBridge = null;

    if (this.currentVrm) this.unloadModel();
    this.detachPointerEvents();
    this.detachRendererContextEvents();
    this.detachControlsEvents();

    if (this.controls) {
      this.controls.dispose();
      this.controls = null;
    }
    if (this.renderer) {
      const canvas = this.renderer.domElement;
      this.renderer.dispose();
      this.renderer.forceContextLoss();
      if (canvas.parentNode === this.container) this.container.removeChild(canvas);
      this.renderer = null;
    }
    if (this.scene) this.scene.clear();
    this.scene = null;
    this.camera = null;
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
      this.lastFrameTime = 0;
      this.performanceWindowStart = this.lastTime;
      this.performanceFrameCount = 0;
      this.animate();
    }
  }

  animate() {
    if (this._isRenderingPaused || this._isDisposed) return;
    this._animationFrameId = requestAnimationFrame(() => this.animate());

    const now = performance.now();
    if (this._contextLost) return;
    if (this.fpsCap > 0) {
      const frameInterval = 1000 / this.fpsCap;
      const elapsedSinceFrame = now - this.lastFrameTime;
      if (this.lastFrameTime > 0 && elapsedSinceFrame < frameInterval * 0.9) return;
      this.lastFrameTime = now - (elapsedSinceFrame % frameInterval);
    }

    let delta = (now - this.lastTime) / 1000;
    if (delta > 0.1) delta = 0.1; // Ограничение скачков при лагах (10 fps min)
    this.lastTime = now;
    this.elapsedTime += delta;

    const elapsedTime = this.elapsedTime;

    this.restoreBaseBoneRotations();

    if (this.motionTransitions) {
      this.motionTransitions.update(delta);

      if (this.pendingRestPoseReset && !this.motionTransitions.isActive) {
        this.finalizeRestPose();
      }

      // Надежный fallback: если Three.js не отправил событие finished (из-за бага или остановки),
      // отправляем его вручную, когда анимация достигла конца.
      if (this.currentAction && !this.currentAction.isRunning()) {
        const clip = this.currentAction.getClip();
        if (clip && this.currentAction.time >= clip.duration - 0.05) {
          if (!this.currentAction._hasNotifiedFinished) {
            const playbackId = this.currentAction._flutterPlaybackId;
            if (typeof playbackId === 'string' && playbackId.length > 0) {
              this.currentAction._hasNotifiedFinished = true;
              this.notifyFlutter('onAnimationFinished', {
                name: clip.name,
                playbackId,
              });
            }
          }
        }
      }
    }

    if (this.currentVrm) {
      this.updateSpeechTimeline();
      this.updateExpressions(delta);
      this.updateMicroMovements(elapsedTime, delta);

      // Плавное следование камеры (Pan) за пальцем без изменения угла
      this.cameraController.updatePanFollowing(delta);

      this.updateProceduralHeadRotation(delta);

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

    this.controls.update();
    this.renderer.render(this.scene, this.camera);
    this.recordPerformance(now);
  }

  updateSpeechTimeline() {
    const now = performance.now();
    const update = this.speechTimeline.advance(now);

    if (Object.prototype.hasOwnProperty.call(update, 'viseme')) {
      if (update.viseme === null) {
        this.clearExpressionLayer('mouth');
      } else {
        const targetViseme = VrmRunner.VISEME_MAP[update.viseme.viseme] || 'aa';
        const transitionDuration = Math.min(
          0.08,
          Math.max(0.02, update.viseme.durationMs / 4000.0),
        );
        this.setExpression(
          targetViseme,
          'mouth',
          update.viseme.weight,
          transitionDuration,
        );
      }
    }
    if (Object.prototype.hasOwnProperty.call(update, 'amplitude')) {
      this.lipSyncAmplitude = update.amplitude;
    }
    if (update.finishedSessionId !== undefined) {
      this.notifyFlutter('onSpeechFinished', {
        sessionId: update.finishedSessionId,
      });
    }
  }

  updateExpressions(delta) {
    if (!this.currentVrm || !this.currentVrm.expressionManager) return;
    const em = this.currentVrm.expressionManager;

    let blinkWeight = 0;
    if (this.autoBlinkEnabled && this.isBlinking) {
      blinkWeight = Math.sin(Math.min(this.blinkProgress, Math.PI));
    }
    em.setValue('blink', blinkWeight);

    this.smoothLipSyncAmplitude = THREE.MathUtils.lerp(this.smoothLipSyncAmplitude, this.lipSyncAmplitude, 0.25);
    if (this.lipSyncAmplitude > 0.001 || this.smoothLipSyncAmplitude > 0.001) {
      em.setValue('aa', this.smoothLipSyncAmplitude);
    }

    // Плавно интерполируем все активные эмоции (кроссфейд угасания и нарастания)
    for (const [name, state] of Object.entries(this.activeExpressions)) {
      if (name !== 'blink') {
        const step = delta / Math.max(state.duration, 0.01);
        state.currentWeight = THREE.MathUtils.lerp(state.currentWeight, state.targetWeight, step);

        let effectiveWeight = state.currentWeight;
        // Во время автоморгания временно приглушаем эмоцию глаз, чтобы веки закрывались на 100%
        if (this.isBlinking && blinkWeight > 0.01 && (name === 'happy' || name === 'surprised')) {
          effectiveWeight *= (1.0 - blinkWeight);
        }

        em.setValue(name, effectiveWeight);

        // Когда затухающая эмоция полностью угасла (< 0.001), окончательно обнуляем её и удаляем
        if (state.targetWeight === 0.0 && state.currentWeight < 0.001) {
          em.setValue(name, 0.0);
          delete this.activeExpressions[name];
        }
      }
    }

    // Кастомные BlendShapes оптимизация: обновляем только если было изменение (отслеживание состояния можно добавить позже, пока просто перебираем)
    // Но так как перебор Map из 0 элементов дешев, оставим пока так, но можно отфильтровать.
    for (const [name, weight] of this.customBlendShapes.entries()) {
      em.setValue(name, weight);
    }
  }

  updateMicroMovements(elapsedTime, delta) {
    if (this.autoBlinkEnabled && this.currentVrm.expressionManager) {
      this.blinkTimer += delta;
      if (!this.isBlinking && this.blinkTimer >= this.nextBlinkInterval) {
        this.isBlinking = true;
        this.blinkProgress = 0;
        this.blinkTimer = 0;
        this.nextBlinkInterval = 2.0 + Math.random() * 4.0;
      }

      if (this.isBlinking) {
        this.blinkProgress += delta * 8.0;
        if (this.blinkProgress >= Math.PI) {
          this.isBlinking = false;
        }
      }
    }

    // Обновляем базовую позицию взгляда (defaultLookAtPos), чтобы она всегда
    // была ровно перед головой модели, даже если мы ее перетащили (Pan)
    if (this.currentVrm && this.currentVrm.humanoid) {
      const headNode = this.currentVrm.humanoid.getNormalizedBoneNode('head') || this.currentVrm.humanoid.getRawBoneNode('head');
      if (headNode) {
        headNode.getWorldPosition(this.defaultLookAtPos);
        // Смотрим на 2 метра прямо перед собой (по оси Z к камере)
        // Если глаза находятся чуть ниже макушки, вычитаем немного Y, чтобы взгляд был "в глаза"
        this.defaultLookAtPos.y -= 0.05; // -0.05 - опустить взгляд, 0.05 - поднять
        this.defaultLookAtPos.z += 2.0; // 2.0 - ближе, -2.0 - дальше
      }
    }

    // Countdown LookAt hold timer after side tap
    if (this.lookAtTimer > 0) {
      this.lookAtTimer -= delta;
      if (this.lookAtTimer <= 0) {
        // Hold time expired -> smoothly return gaze to default center position!
        this.targetHeadYaw = 0;
        this.targetHeadPitch = 0;
      }
    } else {
      // Если мы не смотрим на клик, постоянно отслеживаем прямую позицию
      this.desiredLookAtPos.copy(this.defaultLookAtPos);
    }

    // Saccades Simulation
    if (this.saccadeEnabled && this.lookAtTimer <= 0) { // Only do saccades if NOT holding a manual lookAt tap
      this.saccadeTimer -= delta;
      if (this.saccadeTimer <= 0) {
        // Next saccade in 0.5 to 2.5 seconds
        this.saccadeTimer = 0.5 + Math.random() * 2.0;
        // Random offset
        this.targetSaccadeOffset.set(
          (Math.random() - 0.5) * 0.4,
          (Math.random() - 0.5) * 0.2,
          0
        );
      }
    } else {
      // Return eyes to normal if manually tapped
      this.targetSaccadeOffset.set(0, 0, 0);
    }

    // Jerky eye movement (high lerp alpha)
    this.currentSaccadeOffset.lerp(this.targetSaccadeOffset, 0.5);

    // Smoothly interpolate lookAtTarget towards (desiredLookAtPos + currentSaccadeOffset)
    const targetX = this.desiredLookAtPos.x + this.currentSaccadeOffset.x;
    const targetY = this.desiredLookAtPos.y + this.currentSaccadeOffset.y;
    const targetZ = this.desiredLookAtPos.z + this.currentSaccadeOffset.z;

    this.lookAtTarget.position.x = THREE.MathUtils.lerp(this.lookAtTarget.position.x, targetX, 0.15);
    this.lookAtTarget.position.y = THREE.MathUtils.lerp(this.lookAtTarget.position.y, targetY, 0.15);
    this.lookAtTarget.position.z = THREE.MathUtils.lerp(this.lookAtTarget.position.z, targetZ, 0.15);
  }

  updateProceduralHeadRotation(delta) {
    if (!this.currentVrm || !this.currentVrm.humanoid) return;

    const chest = this.currentVrm.humanoid.getNormalizedBoneNode('chest');
    const neck = this.currentVrm.humanoid.getNormalizedBoneNode('neck');
    const head = this.currentVrm.humanoid.getNormalizedBoneNode('head');

    // Сохраняем "чистый" результат работы анимации (или T-позы)
    if (chest) this.chestBaseQuat.copy(chest.quaternion);
    if (neck) this.neckBaseQuat.copy(neck.quaternion);
    if (head) this.headBaseQuat.copy(head.quaternion);
    this.baseBonesSaved = true;

    // Сглаживание текущего угла к целевому. 
    const smoothingSpeed = 4.0;
    this.proceduralHeadYaw = THREE.MathUtils.lerp(this.proceduralHeadYaw, this.targetHeadYaw, smoothingSpeed * delta);
    this.proceduralHeadPitch = THREE.MathUtils.lerp(this.proceduralHeadPitch, this.targetHeadPitch, smoothingSpeed * delta);

    // Если углы близки к нулю, не тратим ресурсы на умножение
    if (Math.abs(this.proceduralHeadYaw) < 0.001 && Math.abs(this.proceduralHeadPitch) < 0.001) return;

    // Создаем Эйлеровы углы: Yaw (Y) и Pitch (X)
    this._tmpEuler.set(-this.proceduralHeadPitch, this.proceduralHeadYaw, 0, 'YXZ');
    this._tmpQuatAdditive.setFromEuler(this._tmpEuler);

    // Распределяем вращение по позвоночнику (20% грудь, 40% шея, 40% голова)
    this._tmpQuatChest.identity().slerp(this._tmpQuatAdditive, 0.2);
    this._tmpQuatNeckHead.identity().slerp(this._tmpQuatAdditive, 0.4);

    if (chest) chest.quaternion.multiply(this._tmpQuatChest);
    if (neck) neck.quaternion.multiply(this._tmpQuatNeckHead);
    if (head) head.quaternion.multiply(this._tmpQuatNeckHead);
  }

  updateDragTilt(delta) {
    if (!this.currentVrm || !this.currentVrm.humanoid) return;

    // Сглаживаем скорость для инерции (независимо от FPS)
    const tiltLerpFactor = 1.0 - Math.exp(-12.0 * delta);
    this.smoothDragVelocity.lerp(this.dragVelocity, tiltLerpFactor);

    // Если скорость упала до нуля, не считаем
    if (Math.abs(this.smoothDragVelocity.x) < 0.1 && Math.abs(this.smoothDragVelocity.y) < 0.1) {
      return;
    }

    // Ограничиваем максимальный наклон
    const clampSpeed = (val, max) => Math.max(-max, Math.min(max, val));

    // Переводим пиксели/кадр в угол наклона (радианы). 
    // Чувствительность подбирается экспериментально.
    // Если тащим вправо (+X экрана), модель должна наклониться ВЛЕВО (инерция).
    // Положительный поворот по Z = наклон влево.
    // Если тащим вниз (+Y экрана), модель должна наклониться ВВЕРХ (отклониться назад).
    // Отрицательный поворот по X = наклон назад.
    const maxRoll = 0.2; // ~11 градусов
    const maxPitch = 0.15; // ~8.5 градусов
    const tiltZ = clampSpeed(this.smoothDragVelocity.x * 0.005, maxRoll);
    const tiltX = clampSpeed(this.smoothDragVelocity.y * -0.005, maxPitch);

    this._tmpEuler.set(tiltX, 0, tiltZ, 'YXZ');
    this._tmpQuatAdditive.setFromEuler(this._tmpEuler);

    const chest = this.currentVrm.humanoid.getNormalizedBoneNode('chest');
    const neck = this.currentVrm.humanoid.getNormalizedBoneNode('neck');

    // Распределяем наклон пополам между спиной и шеей
    this._tmpQuatChest.identity().slerp(this._tmpQuatAdditive, 0.5);

    if (chest) chest.quaternion.multiply(this._tmpQuatChest);
    if (neck) neck.quaternion.multiply(this._tmpQuatChest);
  }

  restoreBaseBoneRotations() {
    if (!this.baseBonesSaved || !this.currentVrm || !this.currentVrm.humanoid) return;

    const chest = this.currentVrm.humanoid.getNormalizedBoneNode('chest');
    const neck = this.currentVrm.humanoid.getNormalizedBoneNode('neck');
    const head = this.currentVrm.humanoid.getNormalizedBoneNode('head');

    // Восстанавливаем состояние до процедурного поворота
    if (chest) chest.quaternion.copy(this.chestBaseQuat);
    if (neck) neck.quaternion.copy(this.neckBaseQuat);
    if (head) head.quaternion.copy(this.headBaseQuat);
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

// Static viseme mapping used by direct input and the speech timeline.
VrmRunner.VISEME_MAP = {
  'aa': 'aa', 'ih': 'ih', 'ou': 'ou', 'ee': 'ee', 'oh': 'oh',
  'AA': 'aa', 'IH': 'ih', 'OU': 'ou', 'EE': 'ee', 'OH': 'oh',
  'sil': 'sil'
};

window.addEventListener('DOMContentLoaded', () => {
  new VrmRunner();
});
