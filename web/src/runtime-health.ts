export interface RuntimeHealth {
  readonly runtimeVersion: string;
  readonly threeRevision: string;
  readonly threeVrmVersion: string;
  readonly protocolVersion: number;
  readonly webGlVersion: 1 | 2;
  readonly maxTextureSize: number;
  readonly maxTextures: number;
  readonly maxVertexTextures: number;
  readonly rendererTextureCount: number;
  readonly estimatedTextureMemoryBytes: number;
  readonly lastModelLoadDurationMs: number;
  readonly modelLoaded: boolean;
  readonly animationActive: boolean;
  readonly animationPaused: boolean;
  readonly renderingPaused: boolean;
  readonly contextLost: boolean;
  readonly contextLossCount: number;
}
