import {
  AmbientLight,
  Color,
  DirectionalLight,
  Mesh,
  PCFSoftShadowMap,
  PerspectiveCamera,
  Scene,
  SRGBColorSpace,
  WebGLRenderer,
  type Material,
  type Object3D,
  type WebGLRendererParameters,
} from "three";
import { OrbitControls } from "three/addons/controls/OrbitControls.js";

export interface RuntimeViewport {
  readonly width: number;
  readonly height: number;
  readonly pixelRatio: number;
}

export interface RuntimeLightingConfig {
  readonly ambientIntensity?: number;
  readonly ambientColor?: string;
  readonly directionalIntensity?: number;
  readonly directionalColor?: string;
}

export function parseRuntimeLightingConfig(
  value: unknown,
): RuntimeLightingConfig {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TypeError("Lighting settings must be an object.");
  }
  const config = value as Readonly<Record<string, unknown>>;
  const ambientIntensity = readOptionalNonNegativeNumber(
    config.ambientIntensity,
    "ambientIntensity",
  );
  const directionalIntensity = readOptionalNonNegativeNumber(
    config.directionalIntensity,
    "directionalIntensity",
  );
  const ambientColor = readOptionalNonEmptyString(
    config.ambientColor,
    "ambientColor",
  );
  const directionalColor = readOptionalNonEmptyString(
    config.directionalColor,
    "directionalColor",
  );
  return {
    ...(ambientIntensity === undefined ? {} : { ambientIntensity }),
    ...(ambientColor === undefined ? {} : { ambientColor }),
    ...(directionalIntensity === undefined ? {} : { directionalIntensity }),
    ...(directionalColor === undefined ? {} : { directionalColor }),
  };
}

export interface RuntimeSceneControllerOptions {
  readonly container: HTMLElement;
  readonly lookAtTarget: Object3D;
  readonly antialias?: boolean;
  readonly getViewport?: () => RuntimeViewport;
  readonly createRenderer?: (
    parameters: WebGLRendererParameters,
  ) => WebGLRenderer;
  readonly createControls?: (
    camera: PerspectiveCamera,
    domElement: HTMLElement,
  ) => OrbitControls;
  readonly onControlsStart?: () => void;
  readonly onControlsEnd?: () => void;
  readonly onContextLost?: () => void;
  readonly onContextRestored?: () => void;
}

export class RuntimeSceneController {
  public readonly scene: Scene;
  public readonly camera: PerspectiveCamera;
  public readonly ambientLight: AmbientLight;
  public readonly directionalLight: DirectionalLight;
  public readonly rimLight: DirectionalLight;

  private rendererValue: WebGLRenderer;
  private controlsValue: OrbitControls;
  private antialiasValue: boolean;
  private contextLostValue = false;
  private disposed = false;
  private rendererEventCanvas: HTMLCanvasElement | null = null;

  private readonly container: HTMLElement;
  private readonly getViewport: () => RuntimeViewport;
  private readonly createRenderer: (
    parameters: WebGLRendererParameters,
  ) => WebGLRenderer;
  private readonly createControls: (
    camera: PerspectiveCamera,
    domElement: HTMLElement,
  ) => OrbitControls;
  private readonly onControlsStart?: () => void;
  private readonly onControlsEnd?: () => void;
  private readonly onContextLost?: () => void;
  private readonly onContextRestored?: () => void;

  private readonly handleControlsStart = (): void => {
    this.onControlsStart?.();
  };

  private readonly handleControlsEnd = (): void => {
    this.onControlsEnd?.();
  };

  private readonly handleContextLost = (event: Event): void => {
    event.preventDefault();
    this.contextLostValue = true;
    this.onContextLost?.();
  };

  private readonly handleContextRestored = (): void => {
    this.contextLostValue = false;
    this.markMaterialsForUpdate();
    this.onContextRestored?.();
  };

  public constructor(options: RuntimeSceneControllerOptions) {
    this.container = options.container;
    this.antialiasValue = options.antialias ?? true;
    this.getViewport = options.getViewport ?? defaultViewport;
    this.createRenderer =
      options.createRenderer ??
      ((parameters) => new WebGLRenderer(parameters));
    this.createControls =
      options.createControls ??
      ((camera, domElement) => new OrbitControls(camera, domElement));
    this.onControlsStart = options.onControlsStart;
    this.onControlsEnd = options.onControlsEnd;
    this.onContextLost = options.onContextLost;
    this.onContextRestored = options.onContextRestored;

    const viewport = this.getViewport();
    this.scene = new Scene();
    this.camera = new PerspectiveCamera(
      36,
      safeAspect(viewport.width, viewport.height),
      0.1,
      20,
    );
    this.camera.position.set(0, 1.05, 1.9);

    options.lookAtTarget.position.set(0, 1.4, 2.1);
    this.scene.add(options.lookAtTarget);

    this.ambientLight = new AmbientLight(0xffffff, 1.2);
    this.scene.add(this.ambientLight);

    this.directionalLight = new DirectionalLight(0xffffff, 1);
    this.directionalLight.position.set(1, 2, 1.5);
    configureDirectionalShadow(this.directionalLight);
    this.scene.add(this.directionalLight);

    this.rimLight = new DirectionalLight(0xffffff, 0.6);
    this.rimLight.position.set(-1, 1.5, -1.5);
    this.scene.add(this.rimLight);

    const renderer = this.createConfiguredRenderer(
      this.antialiasValue,
      Math.min(viewport.pixelRatio, 1.5),
      false,
      viewport,
    );
    try {
      this.controlsValue = this.createConfiguredControls(renderer.domElement);
    } catch (error) {
      renderer.dispose();
      renderer.forceContextLoss();
      throw error;
    }
    this.rendererValue = renderer;
    this.container.appendChild(this.rendererValue.domElement);
    this.attachRendererEvents(this.rendererValue.domElement);
    this.attachControlsEvents(this.controlsValue);
  }

  public get renderer(): WebGLRenderer {
    return this.rendererValue;
  }

  public get controls(): OrbitControls {
    return this.controlsValue;
  }

  public get antialias(): boolean {
    return this.antialiasValue;
  }

  public get contextLost(): boolean {
    return this.contextLostValue;
  }

  public resize(width: number, height: number): void {
    this.camera.aspect = safeAspect(width, height);
    this.camera.updateProjectionMatrix();
    this.rendererValue.setSize(width, height);
  }

  public setPixelRatio(pixelRatio: number): void {
    if (Math.abs(this.rendererValue.getPixelRatio() - pixelRatio) <= 1e-9) {
      return;
    }
    this.rendererValue.setPixelRatio(pixelRatio);
    const viewport = this.getViewport();
    this.rendererValue.setSize(viewport.width, viewport.height, false);
  }

  public setLighting(config: RuntimeLightingConfig): void {
    config = parseRuntimeLightingConfig(config);
    if (config.ambientIntensity !== undefined) {
      this.ambientLight.intensity = config.ambientIntensity;
    }
    if (config.ambientColor !== undefined) {
      this.ambientLight.color.set(config.ambientColor);
    }
    if (config.directionalIntensity !== undefined) {
      this.directionalLight.intensity = config.directionalIntensity;
    }
    if (config.directionalColor !== undefined) {
      this.directionalLight.color.set(config.directionalColor);
    }
  }

  public setEnvironmentColor(colorHex: string, intensity = 0.5): void {
    this.rimLight.color.set(colorHex);
    this.ambientLight.color
      .set(0xffffff)
      .lerp(new Color(colorHex), intensity);
  }

  public setShadows(enabled: boolean): boolean {
    if (this.rendererValue.shadowMap.enabled === enabled) return false;
    this.rendererValue.shadowMap.enabled = enabled;
    this.directionalLight.castShadow = enabled;
    this.scene.traverse((object) => {
      const mesh = object as Mesh;
      if (!mesh.isMesh) return;
      mesh.castShadow = enabled;
      mesh.receiveShadow = enabled;
      markMaterialForUpdate(mesh.material);
    });
    return true;
  }

  public setCanvasBackground(
    colorHex: string | null,
    transparent: boolean,
  ): void {
    if (transparent || colorHex === null) {
      this.rendererValue.setClearColor(0x000000, 0);
      this.scene.background = null;
      return;
    }
    this.rendererValue.setClearColor(colorHex, 1);
    this.scene.background = new Color(colorHex);
  }

  public recreateRenderer(antialias: boolean): boolean {
    if (this.disposed || antialias === this.antialiasValue) return false;

    const oldRenderer = this.rendererValue;
    const oldControls = this.controlsValue;
    const oldCanvas = oldRenderer.domElement;
    const oldTarget = oldControls.target.clone();
    const viewport = this.getViewport();
    const newRenderer = this.createConfiguredRenderer(
      antialias,
      oldRenderer.getPixelRatio(),
      oldRenderer.shadowMap.enabled,
      viewport,
    );

    let newControls: OrbitControls;
    try {
      newControls = this.createConfiguredControls(newRenderer.domElement);
      newControls.target.copy(oldTarget);
      this.markMaterialsForUpdate();
      // Populate the replacement framebuffer before exposing its canvas.
      newRenderer.render(this.scene, this.camera);
    } catch (error) {
      newRenderer.dispose();
      newRenderer.forceContextLoss();
      throw error;
    }

    this.detachRendererEvents();
    this.detachControlsEvents(oldControls);
    oldControls.dispose();

    // Append the already-rendered canvas before removing the old one so native
    // WebView compositing never observes a container without a valid frame.
    this.container.appendChild(newRenderer.domElement);
    if (oldCanvas.parentNode === this.container) {
      this.container.removeChild(oldCanvas);
    }

    this.antialiasValue = antialias;
    this.contextLostValue = false;
    this.rendererValue = newRenderer;
    this.controlsValue = newControls;
    this.attachRendererEvents(newRenderer.domElement);
    this.attachControlsEvents(newControls);

    oldRenderer.dispose();
    oldRenderer.forceContextLoss();
    return true;
  }

  public updateAndRender(prepareCamera?: () => void): void {
    if (this.disposed || this.contextLostValue) return;
    this.controlsValue.update();
    prepareCamera?.();
    this.rendererValue.render(this.scene, this.camera);
  }

  public dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.detachRendererEvents();
    this.detachControlsEvents(this.controlsValue);
    this.controlsValue.dispose();
    const canvas = this.rendererValue.domElement;
    this.rendererValue.dispose();
    this.rendererValue.forceContextLoss();
    if (canvas.parentNode === this.container) {
      this.container.removeChild(canvas);
    }
    this.scene.clear();
  }

  private createConfiguredRenderer(
    antialias: boolean,
    pixelRatio: number,
    shadowsEnabled: boolean,
    viewport: RuntimeViewport,
  ): WebGLRenderer {
    const renderer = this.createRenderer({
      alpha: true,
      antialias,
      premultipliedAlpha: false,
      preserveDrawingBuffer: false,
    });
    renderer.setSize(viewport.width, viewport.height);
    renderer.setPixelRatio(pixelRatio);
    renderer.outputColorSpace = SRGBColorSpace;
    renderer.shadowMap.enabled = shadowsEnabled;
    renderer.shadowMap.type = PCFSoftShadowMap;
    return renderer;
  }

  private createConfiguredControls(domElement: HTMLElement): OrbitControls {
    const controls = this.createControls(this.camera, domElement);
    controls.target.set(0, 0.95, 0);
    return controls;
  }

  private attachControlsEvents(controls: OrbitControls): void {
    controls.addEventListener("start", this.handleControlsStart);
    controls.addEventListener("end", this.handleControlsEnd);
  }

  private detachControlsEvents(controls: OrbitControls): void {
    controls.removeEventListener("start", this.handleControlsStart);
    controls.removeEventListener("end", this.handleControlsEnd);
  }

  private attachRendererEvents(canvas: HTMLCanvasElement): void {
    this.rendererEventCanvas = canvas;
    canvas.addEventListener("webglcontextlost", this.handleContextLost);
    canvas.addEventListener("webglcontextrestored", this.handleContextRestored);
  }

  private detachRendererEvents(): void {
    const canvas = this.rendererEventCanvas;
    if (canvas === null) return;
    canvas.removeEventListener("webglcontextlost", this.handleContextLost);
    canvas.removeEventListener(
      "webglcontextrestored",
      this.handleContextRestored,
    );
    this.rendererEventCanvas = null;
  }

  private markMaterialsForUpdate(): void {
    this.scene.traverse((object) => {
      const mesh = object as Mesh;
      if (!mesh.isMesh) return;
      markMaterialForUpdate(mesh.material);
    });
  }
}

function readOptionalNonNegativeNumber(
  value: unknown,
  field: string,
): number | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    throw new TypeError(`${field} must be a non-negative finite number.`);
  }
  return value;
}

function readOptionalNonEmptyString(
  value: unknown,
  field: string,
): string | undefined {
  if (value === undefined) return undefined;
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new TypeError(`${field} must be a non-empty string.`);
  }
  return value;
}

function defaultViewport(): RuntimeViewport {
  return {
    width: window.innerWidth,
    height: window.innerHeight,
    pixelRatio: window.devicePixelRatio,
  };
}

function safeAspect(width: number, height: number): number {
  return width > 0 && height > 0 ? width / height : 1;
}

function configureDirectionalShadow(light: DirectionalLight): void {
  light.castShadow = true;
  light.shadow.mapSize.width = 2048;
  light.shadow.mapSize.height = 2048;
  light.shadow.camera.near = 0.5;
  light.shadow.camera.far = 10;
  light.shadow.camera.left = -1.5;
  light.shadow.camera.right = 1.5;
  light.shadow.camera.top = 2;
  light.shadow.camera.bottom = -0.5;
  light.shadow.bias = -0.001;
}

function markMaterialForUpdate(
  material: Material | Material[] | null | undefined,
): void {
  if (material == null) return;
  const materials = Array.isArray(material) ? material : [material];
  for (const entry of materials) entry.needsUpdate = true;
}
