import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { VRMLoaderPlugin, VRMUtils } from '@pixiv/three-vrm';
import { VRMAnimationLoaderPlugin, createVRMAnimationClip, VRMLookAtQuaternionProxy } from '@pixiv/three-vrm-animation';

// Подавляем безвредные предупреждения от @pixiv/three-vrm-animation для старых vrma файлов
const originalConsoleWarn = console.warn;
console.warn = function (...args) {
  if (typeof args[0] === 'string' && args[0].includes('Unknown VRMC_vrm_animation spec version')) {
    return; // Игнорируем это предупреждение
  }
  originalConsoleWarn.apply(console, args);
};

class VrmCache {
  constructor(dbName = 'VRMCacheDB', storeName = 'models') {
    this.dbName = dbName;
    this.storeName = storeName;
    this.db = null;
  }

  async init() {
    if (this.db) return this.db;
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName, 1);
      request.onupgradeneeded = (e) => {
        const db = e.target.result;
        if (!db.objectStoreNames.contains(this.storeName)) {
          db.createObjectStore(this.storeName);
        }
      };
      request.onsuccess = (e) => {
        this.db = e.target.result;
        resolve(this.db);
      };
      request.onerror = (e) => reject(e.target.error);
    });
  }

  async get(key) {
    await this.init();
    return new Promise((resolve, reject) => {
      const tx = this.db.transaction(this.storeName, 'readonly');
      const store = tx.objectStore(this.storeName);
      const request = store.get(key);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  async set(key, blob) {
    await this.init();
    return new Promise((resolve, reject) => {
      const tx = this.db.transaction(this.storeName, 'readwrite');
      const store = tx.objectStore(this.storeName);
      const request = store.put(blob, key);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
  }

  async clear() {
    await this.init();
    return new Promise((resolve, reject) => {
      const tx = this.db.transaction(this.storeName, 'readwrite');
      const store = tx.objectStore(this.storeName);
      const request = store.clear();
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
  }
}
const vrmCache = new VrmCache();

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

    this.currentVrm = null;
    this.mixer = null;

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
    this.visemeQueue = [];
    this.speechEpochMs = null;
    this.speechEndTimeMs = null;
    this.speechIsFinishing = false;
    this.speechFinishedNotified = false;

    // Micro-movements
    this.autoBlinkEnabled = true;
    this.blinkTimer = 0;
    this.nextBlinkInterval = 3.0;
    this.isBlinking = false;
    this.blinkProgress = 0;

    // Camera Presets
    this.cameraMode = 'preset'; // or 'characterCreator', doesn't matter since we auto-set
    this.currentPresetName = 'upperBody';
    this.targetCameraPos = new THREE.Vector3();
    this.targetCameraTarget = new THREE.Vector3();
    this.isCameraAnimating = false;
    this.cameraAnimDuration = 0.5;
    this.cameraAnimStartTime = 0;
    this.startCameraPos = new THREE.Vector3();
    this.startCameraTarget = new THREE.Vector3();

    // Animation Action
    this.currentAction = null;
    this.isAnimationPaused = false;
    this._lastLoadPercent = -1;

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
    this.cameraStartPos = new THREE.Vector3();
    this.controlsStartPos = new THREE.Vector3();
    this.targetCameraTarget = new THREE.Vector3(0, 0.95, 0);

    // Head Tracking
    this.targetHeadYaw = 0;
    this.targetHeadPitch = 0;
    this.proceduralHeadYaw = 0;
    this.proceduralHeadPitch = 0;

    // Animation state
    this.startCameraPos = new THREE.Vector3();
    this.startCameraTarget = new THREE.Vector3();
    this.targetCameraPos = new THREE.Vector3();

    this.raycaster = new THREE.Raycaster();

    // Graphics and Performance state
    this.currentAntialias = true;
    this.enablePhysics = true;
    this.fpsCap = 0;
    this.lastFrameTime = 0;

    this.initScene();
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
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;

    this.renderer.shadowMap.enabled = false;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    this.container.appendChild(this.renderer.domElement);

    // Орбитальный контроллер вращения модели (OrbitControls)
    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.target.set(0, 0.95, 0); // Фокус 'upperBody'
    this.controls.addEventListener('start', () => {
      this.hasCustomCameraTransform = true;
    });
    this.setupCharacterCreatorControls();

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

  setupCharacterCreatorControls() {
    this.controls.enablePan = false;
    this.controls.enableRotate = false;
    this.controls.enableZoom = true;

    // Fix the camera angle to look straight ahead
    this.controls.minPolarAngle = Math.PI / 2;
    this.controls.maxPolarAngle = Math.PI / 2;
    this.controls.minAzimuthAngle = 0;
    this.controls.maxAzimuthAngle = 0;

    // Zoom limits (от максимального приближения до отдаления)
    this.controls.minDistance = 0.5;
    this.controls.maxDistance = 6.6; // Ограничили минимальный размер модели в 1.5 раза (было 10.0)

    this.controls.enableDamping = true;
    this.controls.dampingFactor = 0.08;
    this.controls.update();
  }

  initEvents() {
    window.addEventListener('resize', () => this.onWindowResize());
    this.attachPointerEvents();

    window.addEventListener('message', (event) => {
      try {
        const data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
        if (data && data.action) {
          this.handleFlutterCommand(data.action, data.payload);
        }
      } catch (err) {
        console.error('Message handler error:', err);
      }
    });

    window.flutterVrmInvoke = (action, payloadJson) => {
      try {
        const payload = payloadJson ? JSON.parse(payloadJson) : {};
        this.handleFlutterCommand(action, payload);
      } catch (err) {
        console.error('flutterVrmInvoke error:', err);
      }
    };
  }

  onPointerDown(e) {
    if (e.isPrimary) {
      this.isDragging = true;
      this.dragStartPoint.set(e.clientX, e.clientY);
      this.cameraStartPos.copy(this.camera.position);
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

    const deltaX = e.clientX - this.dragStartPoint.x;
    const deltaY = e.clientY - this.dragStartPoint.y;

    const distance = this.controls.getDistance();
    const vFov = (this.camera.fov * Math.PI) / 180;
    const heightAtDepth = 2 * Math.tan(vFov / 2) * distance;
    const widthAtDepth = heightAtDepth * this.camera.aspect;

    const worldDeltaX = (deltaX / window.innerWidth) * widthAtDepth;
    const worldDeltaY = -(deltaY / window.innerHeight) * heightAtDepth;

    // ВЫЧИТАЕМ дельту из камеры. Свайп вправо (worldDeltaX > 0) должен двигать камеру влево.
    let targetX = this.controlsStartPos.x - worldDeltaX;
    let targetY = this.controlsStartPos.y - worldDeltaY;

    // Лимиты по X (камера не должна улетать далеко от центра модели X=0)
    const clampX = (widthAtDepth / 2) + 0.2;

    // Лимиты по Y. Модель стоит в Y=0 (ступни), макушка на Y=modelHeight.
    const modelHeight = this.modelBoundingHeight || 1.6;

    // Чтобы посмотреть на макушку, нужно поднять фокус камеры (targetY) вверх.
    const maxY = modelHeight + 0.2 + (heightAtDepth / 2);

    // Чтобы посмотреть на ступни, нужно опустить фокус камеры (targetY) вниз.
    const minY = -0.7 - (heightAtDepth / 2);

    targetX = Math.max(-clampX, Math.min(clampX, targetX));
    targetY = Math.max(minY, Math.min(maxY, targetY));

    // Вычисляем абсолютный таргет фокуса камеры
    this.targetCameraTarget.set(targetX, targetY, this.controlsStartPos.z);
  }

  onPointerUp(e) {
    if (!e.isPrimary) return;

    if (this.isDragging) {
      this.isDragging = false;

      // Check if it was a tap or a drag (dist < 10 pixels is a tap)
      const dist = Math.hypot(e.clientX - this.dragStartPoint.x, e.clientY - this.dragStartPoint.y);
      if (dist < 10) {
        this.handleScreenTap(e.clientX, e.clientY);
      }
    }
  }

  attachPointerEvents() {
    const domElement = this.renderer.domElement;
    domElement.addEventListener('pointerdown', (e) => this.onPointerDown(e));
    domElement.addEventListener('pointermove', (e) => this.onPointerMove(e));
    domElement.addEventListener('pointerup', (e) => this.onPointerUp(e));
    domElement.addEventListener('pointercancel', (e) => this.onPointerUp(e));
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
    if (!this.hasCustomCameraTransform) {
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

  handleFlutterCommand(action, payload) {
    switch (action) {
      case 'loadModelFromUrl':
        this.loadModelFromUrl(payload.url);
        break;
      case 'clearCache':
        vrmCache.clear().then(() => console.log('[VRM Cache] Cleared'));
        break;
      case 'unloadModel':
        this.unloadModel();
        break;
      case 'playAnimationFromUrl':
        this.playAnimationFromUrl(payload.url, payload.options);
        break;
      case 'pauseAnimation':
        this.isAnimationPaused = true;
        if (this.mixer) this.mixer.timeScale = 0;
        break;
      case 'resumeAnimation':
        this.isAnimationPaused = false;
        if (this.mixer) this.mixer.timeScale = payload.speed || 1.0;
        break;
      case 'pauseRendering':
        this.pauseRendering();
        break;
      case 'resumeRendering':
        this.resumeRendering();
        break;
      case 'stopAnimation':
        if (this.mixer) {
          this.mixer.stopAllAction();
        }
        this.currentAction = null;
        this.isAnimationPaused = false;
        if (this.mixer) this.mixer.timeScale = 1.0;

        if (this.currentVrm && this.currentVrm.humanoid) {
          this.currentVrm.humanoid.resetNormalizedPose();

          // Принудительно сбрасываем normalized кости головы, чтобы 100% избавиться от залипаний
          const neck = this.currentVrm.humanoid.getNormalizedBoneNode('neck');
          const head = this.currentVrm.humanoid.getNormalizedBoneNode('head');
          const chest = this.currentVrm.humanoid.getNormalizedBoneNode('chest');
          if (neck) neck.quaternion.identity();
          if (head) head.quaternion.identity();
          if (chest) chest.quaternion.identity();

          // ВАЖНО: После ручного изменения костей (resetPose), мировые матрицы устаревают!
          // Если их не обновить прямо сейчас, компонент VRMLookAt на следующем кадре 
          // рассчитает поворот головы опираясь на старую позу, что приведет к "зависанию" головы в странной позе!
          this.currentVrm.scene.updateMatrixWorld(true);
        }

        // Принудительно обнуляем память аддитивного поворота
        this.baseBonesSaved = false;
        if (this.neckBaseQuat) this.neckBaseQuat.identity();
        if (this.headBaseQuat) this.headBaseQuat.identity();
        if (this.chestBaseQuat) this.chestBaseQuat.identity();

        this.targetHeadYaw = 0;
        this.targetHeadPitch = 0;
        this.proceduralHeadYaw = 0;
        this.proceduralHeadPitch = 0;
        break;
      case 'setAnimationSpeed':
        if (this.mixer) this.mixer.timeScale = payload.speed;
        break;
      case 'setShadows':
        this.setShadows(payload.enabled);
        break;
      case 'setExpression':
        this.setExpression(
          payload.expression,
          payload.layer,
          payload.weight,
          payload.duration,
          payload.disableAutoBlink
        );
        break;
      case 'clearExpressionLayer':
        this.clearExpressionLayer(payload.layer);
        break;
      case 'clearAllExpressions':
        this.clearAllExpressions();
        break;
      case 'setCustomBlendShape':
        this.customBlendShapes.set(payload.name, payload.weight);
        break;
      case 'setLipSyncAmplitude':
        this.lipSyncAmplitude = payload.amplitude;
        break;
      case 'setViseme':
        this.setViseme(payload.viseme, payload.weight);
        break;
      case 'enqueueSpeechVisemes':
        if (payload.frames && Array.isArray(payload.frames)) {
          this.enqueueSpeechVisemes(payload.frames);
        }
        break;
      case 'beginSpeech':
        this.beginSpeech(payload.startDelayMs);
        break;
      case 'appendSpeechVisemes':
        if (payload.frames && Array.isArray(payload.frames)) {
          this.appendSpeechVisemes(payload.frames);
        }
        break;
      case 'finishSpeech':
        this.finishSpeech(payload.audioDurationMs);
        break;
      case 'cancelSpeech':
        this.cancelSpeech();
        break;
      case 'setAutoBlink':
        this.autoBlinkEnabled = payload.enabled;
        break;
      case 'setLookAtTarget':
        this.desiredLookAtPos.set(-payload.x, payload.y, payload.z || 2.1);
        this.lookAtTimer = this.lookAtHoldDurationSec;
        break;
      case 'setAutoSaccades':
        this.saccadeEnabled = payload.enabled;
        if (!payload.enabled) this.targetSaccadeOffset.set(0, 0, 0);
        break;
      case 'setLookAtConfig':
        if (payload.deadZoneX !== undefined) this.lookAtBodyDeadZoneX = payload.deadZoneX;
        if (payload.holdDurationSec !== undefined) this.lookAtHoldDurationSec = payload.holdDurationSec;
        break;
      case 'setCameraMode':
        this.setCameraMode(payload.mode);
        break;
      case 'setLighting':
        this.setLighting(payload);
        break;

      case 'setBackground':
        this.setBackground(payload.color, payload.imageUrl, payload.transparent);
        break;
      case 'setPhysics':
        this.setPhysics(payload.stiffness, payload.gravity, payload.drag);
        break;
      case 'stopWind':
        this.stopWind();
        break;
      case 'setWind':
        this.setWind(payload.type, payload.direction);
        break;
      case 'setEnvironmentColor':
        this.setEnvironmentColor(payload.color, payload.intensity);
        break;
      case 'setGraphicsSettings':
        this.setGraphicsSettings(payload.settings);
        break;
      case 'setRenderQuality':
        this.setRenderQuality(payload.pixelRatio);
        break;
      default:
        console.warn('Unknown action:', action);
    }
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
    this._lastLoadPercent = -1;
    this.unloadModel();

    let objectUrl = null;
    let finalUrl = url;

    try {
      // 1. Попытка загрузить из кэша
      let blob = await vrmCache.get(url);

      if (blob) {
        console.log('[VRM Cache] Model loaded from IndexedDB');
        objectUrl = URL.createObjectURL(blob);
        finalUrl = objectUrl;

        // Сразу отправляем 100% прогресс, так как загружено из кэша локально
        this.notifyFlutter('onModelLoadProgress', { percent: 100, loaded: blob.size, total: blob.size });
      } else {
        console.log('[VRM Cache] Downloading model from network');
        const response = await fetch(url);

        if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);

        const total = parseInt(response.headers.get('content-length'), 10) || 0;
        let loaded = 0;

        // Используем Streams API для отслеживания прогресса скачивания вручную
        const reader = response.body.getReader();
        const chunks = [];

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          chunks.push(value);
          loaded += value.length;

          if (total > 0) {
            const percent = Math.round((loaded / total) * 100);
            if (percent !== this._lastLoadPercent) {
              this._lastLoadPercent = percent;
              this.notifyFlutter('onModelLoadProgress', {
                percent: percent,
                loaded: loaded,
                total: total,
              });
            }
          }
        }

        blob = new Blob(chunks);

        // 2. Сохраняем в кэш
        try {
          await vrmCache.set(url, blob);
          console.log('[VRM Cache] Saved to IndexedDB');
        } catch (e) {
          console.warn('[VRM Cache] Failed to save to IndexedDB', e);
        }

        objectUrl = URL.createObjectURL(blob);
        finalUrl = objectUrl;
      }

      // Загрузка в Three.js
      const loader = new GLTFLoader();
      loader.register((parser) => new VRMLoaderPlugin(parser));

      loader.load(
        finalUrl,
        (gltf) => {
          this._setupLoadedVrm(gltf);
          if (objectUrl) URL.revokeObjectURL(objectUrl);
        },
        undefined, // Прогресс уже был обработан при скачивании
        (err) => {
          this._lastLoadPercent = -1;
          this.notifyFlutter('onError', { message: err?.message || 'GLTF load error' });
          if (objectUrl) URL.revokeObjectURL(objectUrl);
        }
      );

    } catch (err) {
      this._lastLoadPercent = -1;
      this.notifyFlutter('onError', { message: err?.message || 'Network or Cache load error' });
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    }
  }

  _setupLoadedVrm(gltf) {
    const vrm = gltf.userData.vrm;
    if (!vrm) {
      this.notifyFlutter('onError', { message: 'Failed to parse VRM model from GLTF' });
      return;
    }

    // Выгружаем предыдущую модель и очищаем память WebGL перед добавлением новой
    if (this.currentVrm) {
      this.unloadModel();
    }

    try {
      if (VRMUtils.removeUnnecessaryVertices) {
        VRMUtils.removeUnnecessaryVertices(gltf.scene);
      }
      if (VRMUtils.rotateVRM0) {
        VRMUtils.rotateVRM0(vrm);
      }
    } catch (utilsErr) {
      console.warn('VRMUtils warning:', utilsErr);
    }

    this.currentVrm = vrm;
    this.scene.add(vrm.scene);

    if (vrm.lookAt) {
      vrm.lookAt.target = this.lookAtTarget;
    }

    if (!this.enablePhysics && vrm.springBoneManager) {
      this._cachedSpringBoneManager = vrm.springBoneManager;
      vrm.springBoneManager = null;
    }

    // Включаем тени для всех мешей модели в зависимости от настроек рендерера
    const shadowsEnabled = this.renderer.shadowMap.enabled;
    vrm.scene.traverse((obj) => {
      if (obj.isMesh) {
        obj.castShadow = shadowsEnabled;
        obj.receiveShadow = shadowsEnabled;
      }
    });

    this.mixer = new THREE.AnimationMixer(vrm.scene);

    // Вычисляем реальный рост модели через кости скелета (надежнее, чем габариты сетки)
    let dynamicHeight = 1.6; // Значение по умолчанию
    try {
      // Обязательно обновляем мировые матрицы перед чтением позиций
      vrm.scene.updateMatrixWorld(true);
      const headBone = vrm.humanoid.getNormalizedBoneNode('head');

      if (headBone) {
        const headPos = new THREE.Vector3();
        headBone.getWorldPosition(headPos);
        // Базовая позиция макушки = позиция кости головы (основание шеи) + примерно 15-20 см головы
        dynamicHeight = headPos.y + 0.15;
      }
    } catch (e) {
      console.warn("Could not calculate exact VRM height from bones, using default 1.6m", e);
    }
    this.modelBoundingHeight = dynamicHeight;

    this.frameAvatar(0);

    // Подписываемся на завершение анимации
    this._onAnimationFinished = (e) => {
      // Игнорируем события от старых/остановленных экшенов, если они почему-то приходят
      // И разрешаем отправку только если экшен совпадает с currentAction ИЛИ если currentAction уже очищен.
      if (!e.action || e.action._hasNotifiedFinished) return;
      e.action._hasNotifiedFinished = true;
      this.notifyFlutter('onAnimationFinished', { name: e.action.getClip().name });
    };
    this.mixer.addEventListener('finished', this._onAnimationFinished);

    this.notifyFlutter('onModelLoaded', {
      name: vrm.meta?.name || 'VRM Model',
      version: vrm.meta?.metaVersion || '1.0'
    });
  }



  unloadModel() {
    if (this.currentVrm) {
      if (this.mixer) {
        if (this._onAnimationFinished) {
          this.mixer.removeEventListener('finished', this._onAnimationFinished);
          this._onAnimationFinished = null;
        }
        this.mixer.stopAllAction();
        this.mixer.uncacheRoot(this.currentVrm.scene);
      }
      this.clearAllExpressions();

      // Усиленная ручная очистка WebGL ресурсов (Geometry, Material, Texture) 
      // для защиты от утечек памяти при частой смене аватаров
      this.currentVrm.scene.traverse((object) => {
        if (object.geometry) object.geometry.dispose();
        if (object.material) {
          if (Array.isArray(object.material)) {
            object.material.forEach(m => this.disposeMaterial(m));
          } else {
            this.disposeMaterial(object.material);
          }
        }
      });

      this.scene.remove(this.currentVrm.scene);
      VRMUtils.deepDispose(this.currentVrm.scene);
      this.currentVrm = null;
      this.mixer = null;
      this.currentAction = null;

      // Сбрасываем переменные аддитивного поворота, чтобы при загрузке новой модели голова не принимала ошибочную позу
      this.baseBonesSaved = false;
      if (this.neckBaseQuat) this.neckBaseQuat.identity();
      if (this.headBaseQuat) this.headBaseQuat.identity();
      if (this.chestBaseQuat) this.chestBaseQuat.identity();
      this.targetHeadYaw = 0;
      this.targetHeadPitch = 0;
      this.proceduralHeadYaw = 0;
      this.proceduralHeadPitch = 0;
      this.lookAtTimer = 0;
      if (this.desiredLookAtPos && this.defaultLookAtPos) {
        this.desiredLookAtPos.copy(this.defaultLookAtPos);
      }

      this.notifyFlutter('onModelUnloaded', {});
    }
  }

  disposeMaterial(material) {
    if (material.map) material.map.dispose();
    if (material.lightMap) material.lightMap.dispose();
    if (material.bumpMap) material.bumpMap.dispose();
    if (material.normalMap) material.normalMap.dispose();
    if (material.specularMap) material.specularMap.dispose();
    if (material.envMap) material.envMap.dispose();
    material.dispose();
  }

  playAnimationFromUrl(url, options = {}) {
    if (!this.currentVrm || !this.mixer) return;

    const loader = new GLTFLoader();
    loader.register((parser) => new VRMAnimationLoaderPlugin(parser));

    loader.load(
      url,
      (gltf) => {
        this._playLoadedAnimation(gltf, options);
      },
      undefined,
      (err) => {
        this.notifyFlutter('onError', { message: err?.message || 'VRMA load error' });
      }
    );
  }

  _playLoadedAnimation(gltf, options) {
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
      clip = this.bindAnimationClipToVRM(gltf.animations[0]);
    }

    if (!clip) {
      this.notifyFlutter('onError', { message: 'No VRMA or GLTF animation clip found in file' });
      return;
    }

    if (this.mixer) {
      const newAction = this.mixer.clipAction(clip);

      const loop = options.loop !== undefined ? options.loop : true;
      const speed = options.speed || 1.0;
      const fadeDuration = options.fadeDuration || 0.5;

      newAction.setLoop(loop ? THREE.LoopRepeat : THREE.LoopOnce);
      newAction.clampWhenFinished = !loop;
      newAction.timeScale = speed;
      newAction.reset();

      if (this.currentAction) {
        const oldAction = this.currentAction;

        // Плавный переход (Crossfade) от старой анимации к новой
        newAction.play();
        this.notifyFlutter('onAnimationStarted', { name: clip.name });
        oldAction.crossFadeTo(newAction, fadeDuration, true);

        // Ждем завершения перехода + небольшой запас (100мс), затем безопасно выгружаем старую анимацию из памяти (Memory Cleanup)
        setTimeout(() => {
          if (this.mixer && oldAction !== this.currentAction) {
            const oldClip = oldAction.getClip();
            oldAction.stop();
            this.mixer.uncacheClip(oldClip);
            this.mixer.uncacheAction(oldAction);
          }
        }, fadeDuration * 1000 + 100);

      } else {
        newAction.play();
        this.notifyFlutter('onAnimationStarted', { name: clip.name });
      }

      this.currentAction = newAction;
    }
  }


  bindAnimationClipToVRM(clip) {
    if (!clip || !this.currentVrm || !this.currentVrm.humanoid) return clip;

    const tracks = [];
    const boneNameMap = {
      'hips': 'hips', 'spine': 'spine', 'chest': 'chest', 'upperchest': 'upperChest',
      'neck': 'neck', 'head': 'head', 'lefteye': 'leftEye', 'righteye': 'rightEye',
      'jaw': 'jaw', 'leftshoulder': 'leftShoulder', 'leftupperarm': 'leftUpperArm',
      'leftlowerarm': 'leftLowerArm', 'lefthand': 'leftHand', 'rightshoulder': 'rightShoulder',
      'rightupperarm': 'rightUpperArm', 'rightlowerarm': 'rightLowerArm',
      'righthand': 'rightHand', 'leftupperleg': 'leftUpperLeg', 'leftlowerleg': 'leftLowerLeg',
      'leftfoot': 'leftFoot', 'lefttoes': 'leftToes', 'rightupperleg': 'rightUpperLeg',
      'rightlowerleg': 'rightLowerLeg', 'rightfoot': 'rightFoot', 'righttoes': 'rightToes',
      'leftthumbproximal': 'leftThumbProximal', 'leftthumbintermediate': 'leftThumbIntermediate',
      'leftthumbdistal': 'leftThumbDistal', 'leftindexproximal': 'leftIndexProximal',
      'leftindexintermediate': 'leftIndexIntermediate', 'leftindexdistal': 'leftIndexDistal',
      'leftmiddleproximal': 'leftMiddleProximal', 'leftmiddleintermediate': 'leftMiddleIntermediate',
      'leftmiddledistal': 'leftMiddleDistal', 'leftringproximal': 'leftRingProximal',
      'leftringintermediate': 'leftRingIntermediate', 'leftringdistal': 'leftRingDistal',
      'leftlittleproximal': 'leftLittleProximal', 'leftlittleintermediate': 'leftLittleIntermediate',
      'leftlittledistal': 'leftLittleDistal', 'rightthumbproximal': 'rightThumbProximal',
      'rightthumbintermediate': 'rightThumbIntermediate', 'rightthumbdistal': 'rightThumbDistal',
      'rightindexproximal': 'rightIndexProximal', 'rightindexintermediate': 'rightIndexIntermediate',
      'rightindexdistal': 'rightIndexDistal', 'rightmiddleproximal': 'rightMiddleProximal',
      'rightmiddleintermediate': 'rightMiddleIntermediate', 'rightmiddledistal': 'rightMiddleDistal',
      'rightringproximal': 'rightRingProximal', 'rightringintermediate': 'rightRingIntermediate',
      'rightringdistal': 'rightRingDistal', 'rightlittleproximal': 'rightLittleProximal',
      'rightlittleintermediate': 'rightLittleIntermediate', 'rightlittledistal': 'rightLittleDistal'
    };

    for (const track of clip.tracks) {
      const parts = track.name.split('.');
      const trackNodeName = parts[0];
      const propertyName = parts.slice(1).join('.');

      const lowerName = trackNodeName.toLowerCase();
      const humanoidBoneName = boneNameMap[lowerName] || lowerName;

      let boneNode = null;
      try {
        boneNode = this.currentVrm.humanoid.getNormalizedBoneNode(humanoidBoneName) ||
          this.currentVrm.humanoid.getRawBoneNode(humanoidBoneName);
      } catch (_) { }

      if (!boneNode) {
        boneNode = this.scene.getObjectByName(trackNodeName);
      }

      if (boneNode) {
        const newTrackName = `${boneNode.name}.${propertyName}`;
        const clonedTrack = track.clone();
        clonedTrack.name = newTrackName;

        // Принудительно фиксируем высоту бёдер Y к истинной высоте кости бёдер текущей модели (boneNode.position.y),
        // чтобы ЛЮБЫЕ анимации (VRMA_01, VRMA_02, LookAround, Thinking, Sad) не проваливали и не поднимали персонажа!
        if (propertyName.includes('position') && (humanoidBoneName === 'hips' || lowerName.includes('hips'))) {
          const values = clonedTrack.values;
          if (values && values.length >= 3) {
            const modelHipsY = boneNode.position.y;
            for (let i = 1; i < values.length; i += 3) {
              values[i] = modelHipsY;
            }
          }
        }

        tracks.push(clonedTrack);
      }
    }

    return new THREE.AnimationClip(clip.name || 'vrmAnimation', clip.duration, tracks);
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

  enqueueSpeechVisemes(frames) {
    if (!frames || frames.length === 0) return;
    this.beginSpeech(0);
    this.appendSpeechVisemes(frames);
    const audioDurationMs = frames.reduce((end, frame) => {
      return Math.max(end, Number(frame.timestampMs || 0) + Number(frame.durationMs || 0));
    }, 0);
    this.finishSpeech(audioDurationMs);
  }

  beginSpeech(startDelayMs = 180) {
    this.visemeQueue = [];
    this.speechEpochMs = performance.now() + Math.max(0, Number(startDelayMs || 0));
    this.speechEndTimeMs = null;
    this.speechIsFinishing = false;
    this.speechFinishedNotified = false;
    this.lipSyncAmplitude = 0.0;
    this.smoothLipSyncAmplitude = 0.0;
    this.clearExpressionLayer('mouth');
  }

  appendSpeechVisemes(frames) {
    if (!frames || frames.length === 0) return;
    if (this.speechEpochMs === null) this.beginSpeech(0);

    const appendedFrames = frames.map(frame => ({
      viseme: frame.viseme || 'sil',
      weight: Math.max(0.0, Math.min(1.0, Number(frame.weight ?? 1.0))),
      timestampMs: Math.max(0, Number(frame.timestampMs || 0)),
      durationMs: Math.max(0, Number(frame.durationMs || 0)),
      targetTime: this.speechEpochMs + Math.max(0, Number(frame.timestampMs || 0))
    }));

    this.visemeQueue.push(...appendedFrames);
    this.visemeQueue.sort((a, b) => a.targetTime - b.targetTime);
  }

  finishSpeech(audioDurationMs = 0) {
    if (this.speechEpochMs === null) this.beginSpeech(0);
    const durationMs = Math.max(0, Number(audioDurationMs || 0));
    this.speechEndTimeMs = this.speechEpochMs + durationMs;
    this.speechIsFinishing = true;
    this.appendSpeechVisemes([{
      viseme: 'sil',
      weight: 0.0,
      timestampMs: durationMs,
      durationMs: 0
    }]);
  }

  cancelSpeech() {
    this.visemeQueue = [];
    this.speechEpochMs = null;
    this.speechEndTimeMs = null;
    this.speechIsFinishing = false;
    this.speechFinishedNotified = false;
    this.lipSyncAmplitude = 0.0;
    this.smoothLipSyncAmplitude = 0.0;
    this.clearExpressionLayer('mouth');
  }

  // ==========================================
  // ПРЕСЕТЫ И РЕЖИМЫ КАМЕРЫ
  // ==========================================

  /**
   * Переключает камеру на один из готовых пресетов (fullBody, upperBody, faceCloseUp)
   * @param {string} presetName Имя пресета
   * @param {number} durationMs Длительность плавного перехода в миллисекундах
   */

  getBoneWorldY(boneName, defaultY) {
    if (!this.currentVrm || !this.currentVrm.humanoid) return defaultY;
    const node = this.currentVrm.humanoid.getNormalizedBoneNode(boneName) ||
      this.currentVrm.humanoid.getRawBoneNode(boneName);
    if (!node) return defaultY;

    const vec = new THREE.Vector3();
    node.getWorldPosition(vec);
    return vec.y;
  }

  frameAvatar(durationMs = 500, resetPosition = true) {
    if (!this.currentVrm || !this.currentVrm.humanoid) return;

    if (resetPosition) {
      this.currentVrm.scene.position.set(0, 0, 0);
      if (this.currentVrm.springBoneManager) {
        this.currentVrm.springBoneManager.reset();
      }
    }
    this.currentVrm.scene.updateMatrixWorld(true);

    this.controls.enabled = false;

    // Calculate model height (head bone + small offset for hair)
    // If the model was moved by Pan, getBoneWorldY will include that offset.
    // So we calculate relative to the model's local space to get pure height.
    const headNode = this.currentVrm.humanoid.getNormalizedBoneNode('head') || this.currentVrm.humanoid.getRawBoneNode('head');
    let modelHeight = 1.45; // Fallback
    if (headNode) {
      const vec = new THREE.Vector3();
      headNode.getWorldPosition(vec);
      // Subtract current scene Y to get the raw height of the avatar
      modelHeight = (vec.y - this.currentVrm.scene.position.y) + 0.15; // +15cm for top of head
    }

    const centerY = modelHeight / 2;

    // We want the model to occupy 80% of the screen height (10% padding top and bottom)
    const targetFrustumHeight = modelHeight / 0.8;
    const vFov = (this.camera.fov * Math.PI) / 180;
    let distance = (targetFrustumHeight / 2) / Math.tan(vFov / 2);

    // If screen is very narrow (portrait), we might need to fit by width instead of height
    const targetFrustumWidth = modelHeight * 0.5; // roughly avatar width
    const aspect = this.camera.aspect;
    if (aspect < 1.0) {
      // if width-constrained
      const distanceForWidth = (targetFrustumWidth / 2) / (Math.tan(vFov / 2) * aspect);
      distance = Math.max(distance, distanceForWidth);
    }

    // Set starting states for animation
    this.startCameraPos.copy(this.camera.position);
    this.startCameraTarget.copy(this.controls.target);

    // Target positions
    if (!this.hasCustomCameraTransform) {
      this.targetCameraTarget.set(0, centerY, 0);
      this.targetCameraPos.set(0, centerY, distance);
    }

    if (durationMs <= 0) {
      this.camera.position.copy(this.targetCameraPos);
      this.controls.target.copy(this.targetCameraTarget);
      this.controls.enabled = true;
      this.setupCharacterCreatorControls();
    } else {
      this.isCameraAnimating = true;
      this.cameraAnimDuration = durationMs / 1000.0;
      this.cameraAnimStartTime = this.elapsedTime || 0;
    }

    this.notifyFlutter('onCameraChanged', { preset: 'fullBodyCentered' });
  }

  /**
   * Устанавливает режим управления камерой (characterCreator или free)
   * @param {string} mode Режим камеры
   */
  setCameraMode(mode) {
    this.cameraMode = mode;
    if (mode === 'characterCreator') {
      this.controls.enabled = true;
      this.setupCharacterCreatorControls();
    } else if (mode === 'free') {
      this.controls.enabled = true;
      this.controls.enablePan = true;
      this.controls.minPolarAngle = 0;
      this.controls.maxPolarAngle = Math.PI;
    } else if (mode === 'preset') {
      this.controls.enabled = false;
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

  setBackground(colorHex, imageUrl, transparent) {
    if (imageUrl) {
      // Use CSS background on document.body for optimal scaling (cover)
      document.body.style.backgroundColor = colorHex || '#000000';
      document.body.style.backgroundImage = `url("${imageUrl}")`;
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
      if (this.currentVrm) {
        if (!this.enablePhysics) {
          // Выключаем физику: сбрасываем кости и временно удаляем менеджер
          if (this.currentVrm.springBoneManager) {
            this.currentVrm.springBoneManager.reset();
            this._cachedSpringBoneManager = this.currentVrm.springBoneManager;
            this.currentVrm.springBoneManager = null;
          }
        } else {
          // Включаем физику обратно
          if (this._cachedSpringBoneManager) {
            this.currentVrm.springBoneManager = this._cachedSpringBoneManager;
            this.currentVrm.springBoneManager.reset();
            this._cachedSpringBoneManager = null;
          }
        }
      }
    }

    if (settings.fpsCap !== undefined) {
      this.fpsCap = settings.fpsCap;
    }

    if (needsRendererRecreate) {
      this._recreateRenderer();
    }

    if (settings.pixelRatio !== undefined && this.renderer) {
      this.renderer.setPixelRatio(settings.pixelRatio);
    }
  }

  _recreateRenderer() {
    if (!this.renderer) return;

    const shadowsEnabled = this.renderer.shadowMap.enabled;
    const pixelRatio = this.renderer.getPixelRatio();

    this.renderer.dispose();
    this.container.removeChild(this.renderer.domElement);

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

    const oldTarget = this.controls.target.clone();
    this.controls.dispose();

    this.controls = new OrbitControls(this.camera, this.renderer.domElement);
    this.controls.target.copy(oldTarget);
    this.controls.addEventListener('start', () => {
      this.hasCustomCameraTransform = true;
    });
    this.setupCharacterCreatorControls();

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
      this.lastTime = performance.now(); // Сброс таймера при возобновлении
      this.animate();
    }
  }

  animate() {
    if (this._isRenderingPaused) return;
    this._animationFrameId = requestAnimationFrame(() => this.animate());

    const now = performance.now();
    let delta = (now - this.lastTime) / 1000;
    if (delta > 0.1) delta = 0.1; // Ограничение скачков при лагах (10 fps min)
    this.lastTime = now;
    this.elapsedTime += delta;

    const elapsedTime = this.elapsedTime;

    this.restoreBaseBoneRotations();

    if (this.mixer) {
      this.mixer.update(delta);

      // Надежный fallback: если Three.js не отправил событие finished (из-за бага или остановки),
      // отправляем его вручную, когда анимация достигла конца.
      if (this.currentAction && !this.currentAction.isRunning()) {
        const clip = this.currentAction.getClip();
        if (clip && this.currentAction.time >= clip.duration - 0.05) {
          if (!this.currentAction._hasNotifiedFinished) {
            this.currentAction._hasNotifiedFinished = true;
            this.notifyFlutter('onAnimationFinished', { name: clip.name });
          }
        }
      }
    }

    if (this.currentVrm) {
      this.updateLipSyncQueue();
      this.updateExpressions(delta);
      this.updateMicroMovements(elapsedTime, delta);

      // Плавное следование камеры (Pan) за пальцем без изменения угла
      if (!this.isCameraAnimating) {
        this._tmpVec3C.copy(this.targetCameraTarget).sub(this.controls.target);
        if (this._tmpVec3C.lengthSq() > 0.000001) {
          const lerpFactor = 1.0 - Math.exp(-25.0 * delta);
          this._tmpVec3C.multiplyScalar(lerpFactor);
          this.camera.position.add(this._tmpVec3C);
          this.controls.target.add(this._tmpVec3C);
        }
      }

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

    if (this.isCameraAnimating) {
      this.updateCameraAnimation(elapsedTime);
    }

    this.controls.update();
    this.renderer.render(this.scene, this.camera);
  }

  updateLipSyncQueue() {
    const now = performance.now();

    while (this.visemeQueue && this.visemeQueue.length > 0 && this.visemeQueue[0].targetTime <= now) {
      const frame = this.visemeQueue.shift();

      const targetViseme = VrmRunner.VISEME_MAP[frame.viseme] || 'aa';

      if (targetViseme === 'sil') {
        this.clearExpressionLayer('mouth');
      } else {
        let transitionDuration = Math.min(0.08, Math.max(0.02, frame.durationMs / 4000.0));
        if (this.visemeQueue.length > 0) {
          const nextFrame = this.visemeQueue[0];
          const timeToNext = Math.max(10, nextFrame.targetTime - now);
          transitionDuration = Math.min(transitionDuration, (timeToNext / 1000.0) * 0.8);
        }

        this.setExpression(targetViseme, 'mouth', frame.weight, transitionDuration);
      }

    }

    if (this.speechIsFinishing &&
        this.visemeQueue.length === 0 &&
        this.speechEndTimeMs !== null &&
        now >= this.speechEndTimeMs &&
        !this.speechFinishedNotified) {
      this.clearExpressionLayer('mouth');
      this.speechFinishedNotified = true;
      this.speechIsFinishing = false;
      this.notifyFlutter('onSpeechFinished', {});
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

  updateCameraAnimation(elapsedTime) {
    const progress = Math.min((elapsedTime - this.cameraAnimStartTime) / this.cameraAnimDuration, 1.0);
    const easeProgress = 0.5 - Math.cos(progress * Math.PI) / 2;

    this.camera.position.lerpVectors(this.startCameraPos, this.targetCameraPos, easeProgress);
    this.controls.target.lerpVectors(this.startCameraTarget, this.targetCameraTarget, easeProgress);

    // Обязательно заставляем камеру смотреть на новую интерполируемую цель во время полета
    this.camera.lookAt(this.controls.target);

    if (progress >= 1.0) {
      this.isCameraAnimating = false;
      this.camera.position.copy(this.targetCameraPos);
      this.controls.target.copy(this.targetCameraTarget);
      this.controls.enabled = true;
      this.setupCharacterCreatorControls();
    }
  }

  notifyFlutter(event, payload) {
    const message = JSON.stringify({ event, payload });
    if (window.FlutterBridge && window.FlutterBridge.postMessage) {
      window.FlutterBridge.postMessage(message);
    } else if (window.chrome && window.chrome.webview) {
      window.chrome.webview.postMessage(message);
    } else if (window.parent) {
      window.parent.postMessage(message, '*');
    }
  }
}

// Static viseme mapping used in setViseme() and updateLipSyncQueue()
VrmRunner.VISEME_MAP = {
  'aa': 'aa', 'ih': 'ih', 'ou': 'ou', 'ee': 'ee', 'oh': 'oh',
  'AA': 'aa', 'IH': 'ih', 'OU': 'ou', 'EE': 'ee', 'OH': 'oh',
  'sil': 'sil'
};

window.addEventListener('DOMContentLoaded', () => {
  window.vrmRunner = new VrmRunner();

  // Export Global Bridge Methods for Flutter
  window.getAvatarTransform = () => {
    if (!window.vrmRunner || !window.vrmRunner.currentVrm) {
      return JSON.stringify({ x: 0, y: 0, zoom: 0 });
    }
    // Поскольку теперь модель всегда в (0,0,0), мы берем координаты цели камеры.
    // Для обратной совместимости: если раньше модель смещали вправо (x > 0), 
    // теперь мы смещаем камеру влево (target.x < 0).
    const target = window.vrmRunner.targetCameraTarget;
    const zoom = window.vrmRunner.controls.getDistance();

    const equivalentX = -target.x;
    const equivalentY = 0.95 - target.y; // 0.95 - дефолтная высота цели камеры

    return JSON.stringify({ x: equivalentX, y: equivalentY, zoom: zoom });
  };

  window.setAvatarTransform = (jsonString) => {
    if (!window.vrmRunner) return;
    try {
      const data = JSON.parse(jsonString);

      window.vrmRunner.hasCustomCameraTransform = true;

      if (data.x !== undefined && data.y !== undefined) {
        // Конвертируем обратно: эквивалентные координаты модели в координаты цели камеры
        const targetX = -data.x;
        const targetY = 0.95 - data.y;

        window.vrmRunner.targetCameraTarget.set(targetX, targetY, 0);
        window.vrmRunner.controls.target.set(targetX, targetY, 0);
      }
      if (data.zoom !== undefined && data.zoom > 0) {
        const target = window.vrmRunner.controls.target;
        window.vrmRunner.camera.position.set(target.x, target.y, target.z + data.zoom);
        window.vrmRunner.controls.update();
      }
    } catch (e) {
      console.error('Failed to setAvatarTransform', e);
    }
  };
});
