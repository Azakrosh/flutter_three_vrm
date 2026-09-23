import type { VRM } from "@pixiv/three-vrm";
import { MathUtils } from "three";
import type {
  RuntimeExpressionLayer,
  RuntimeExpressionName,
} from "./interaction-protocol-codec";

type ExpressionManager = NonNullable<VRM["expressionManager"]>;

interface ExpressionState {
  readonly name: string;
  currentWeight: number;
  targetWeight: number;
  duration: number;
}

interface ExpressionLayer {
  name: string | null;
  targetWeight: number;
  currentWeight: number;
  duration: number;
}

export interface RuntimeFaceDependencies {
  readonly getVrm: () => VRM | null;
  readonly applySpeechAmplitude: (manager: ExpressionManager) => void;
  readonly onExpressionChanged: (
    name: RuntimeExpressionName,
    layer: RuntimeExpressionLayer,
  ) => void;
  readonly random?: () => number;
}

const baseEmotions = new Set([
  "happy", "sad", "angry", "surprised", "relaxed", "neutral",
]);
const directVisemes = ["aa", "ih", "ou", "ee", "oh"] as const;
const visemeMap: Readonly<Record<string, RuntimeExpressionName>> = {
  aa: "aa", ih: "ih", ou: "ou", ee: "ee", oh: "oh",
  AA: "aa", IH: "ih", OU: "ou", EE: "ee", OH: "oh",
};

export class RuntimeFaceController {
  public readonly customBlendShapes = new Map<string, number>();
  private readonly activeExpressions: Record<string, ExpressionState> = {};
  private readonly layers: Record<RuntimeExpressionLayer, ExpressionLayer> = {
    eyes: { name: null, targetWeight: 0, currentWeight: 0, duration: 0.25 },
    mouth: { name: null, targetWeight: 0, currentWeight: 0, duration: 0.1 },
    brows: { name: null, targetWeight: 0, currentWeight: 0, duration: 0.25 },
  };
  public autoBlinkEnabled = true;
  private blinkTimer = 0;
  private nextBlinkInterval = 3;
  private isBlinking = false;
  private blinkProgress = 0;

  public constructor(private readonly dependencies: RuntimeFaceDependencies) {}

  public setExpression(
    expressionName: RuntimeExpressionName,
    layerName: string = "eyes",
    targetWeight = 1,
    durationSec = 0.25,
    disableAutoBlink = false,
  ): void {
    if (!isLayerName(layerName)) return;
    this.autoBlinkEnabled = !disableAutoBlink;
    const newName = expressionName;
    if (baseEmotions.has(newName)) {
      for (const [name, state] of Object.entries(this.activeExpressions)) {
        if (baseEmotions.has(name) && name !== newName) {
          state.targetWeight = 0;
          state.duration = durationSec;
        }
      }
      for (const layer of Object.values(this.layers)) {
        if (layer.name && baseEmotions.has(layer.name) && layer.name !== newName) {
          layer.name = null;
        }
      }
    } else {
      const oldName = this.layers[layerName].name;
      if (oldName && oldName !== newName && this.activeExpressions[oldName]) {
        this.activeExpressions[oldName].targetWeight = 0;
        this.activeExpressions[oldName].duration = durationSec;
      }
    }
    if (!this.activeExpressions[newName]) {
      this.activeExpressions[newName] = {
        name: newName,
        currentWeight: 0,
        targetWeight,
        duration: durationSec,
      };
    } else {
      this.activeExpressions[newName].targetWeight = targetWeight;
      this.activeExpressions[newName].duration = durationSec;
    }
    this.layers[layerName].name = newName;
    this.dependencies.onExpressionChanged(expressionName, layerName);
  }

  public clearExpressionLayer(layerName: string): void {
    if (!isLayerName(layerName)) return;
    const oldName = this.layers[layerName].name;
    if (oldName && this.activeExpressions[oldName]) {
      this.activeExpressions[oldName].targetWeight = 0;
      this.activeExpressions[oldName].duration =
        layerName === "mouth" ? 0.06 : 0.25;
    }
    this.layers[layerName].name = null;
    if (layerName === "eyes") this.autoBlinkEnabled = true;
  }

  public clearAllExpressions(): boolean {
    if (!this.dependencies.getVrm()?.expressionManager) return false;
    for (const state of Object.values(this.activeExpressions)) {
      state.targetWeight = 0;
      state.duration = 0.25;
    }
    for (const layer of Object.values(this.layers)) layer.name = null;
    this.customBlendShapes.clear();
    this.autoBlinkEnabled = true;
    return true;
  }

  public setViseme(visemeName: string, weight = 1): void {
    const manager = this.dependencies.getVrm()?.expressionManager;
    if (!manager) return;
    if (visemeName === "sil" || weight <= 0.001) {
      this.clearExpressionLayer("mouth");
      return;
    }
    for (const viseme of directVisemes) {
      try {
        manager.setValue(viseme, 0);
      } catch {
        // Some VRM models omit one or more preset mouth expressions.
      }
    }
    this.setExpression(visemeMap[visemeName] ?? "aa", "mouth", weight, 0.1);
  }

  public updateExpressions(delta: number): void {
    const manager = this.dependencies.getVrm()?.expressionManager;
    if (!manager) return;
    let blinkWeight = 0;
    if (this.autoBlinkEnabled && this.isBlinking) {
      blinkWeight = Math.sin(Math.min(this.blinkProgress, Math.PI));
    }
    manager.setValue("blink", blinkWeight);
    this.dependencies.applySpeechAmplitude(manager);

    for (const [name, state] of Object.entries(this.activeExpressions)) {
      if (name === "blink") continue;
      const step = delta / Math.max(state.duration, 0.01);
      state.currentWeight = MathUtils.lerp(
        state.currentWeight,
        state.targetWeight,
        step,
      );
      let effectiveWeight = state.currentWeight;
      if (
        this.isBlinking && blinkWeight > 0.01 &&
        (name === "happy" || name === "surprised")
      ) {
        effectiveWeight *= 1 - blinkWeight;
      }
      manager.setValue(name, effectiveWeight);
      if (state.targetWeight === 0 && state.currentWeight < 0.001) {
        manager.setValue(name, 0);
        delete this.activeExpressions[name];
      }
    }
    for (const [name, weight] of this.customBlendShapes) {
      manager.setValue(name, weight);
    }
  }

  public updateBlink(delta: number): void {
    if (!this.autoBlinkEnabled || !this.dependencies.getVrm()?.expressionManager) {
      return;
    }
    this.blinkTimer += delta;
    if (!this.isBlinking && this.blinkTimer >= this.nextBlinkInterval) {
      this.isBlinking = true;
      this.blinkProgress = 0;
      this.blinkTimer = 0;
      this.nextBlinkInterval = 2 + (this.dependencies.random?.() ?? Math.random()) * 4;
    }
    if (this.isBlinking) {
      this.blinkProgress += delta * 8;
      if (this.blinkProgress >= Math.PI) this.isBlinking = false;
    }
  }
}

function isLayerName(value: string): value is RuntimeExpressionLayer {
  return value === "eyes" || value === "mouth" || value === "brows";
}
