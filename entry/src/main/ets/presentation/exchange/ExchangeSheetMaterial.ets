import { uiMaterial } from '@kit.ArkUI';

/** API 26 module: dynamically loaded only when the host supplies supported immersive materials. */
export function createExchangeSheetMaterial(): SystemUiMaterial | undefined {
  if (!uiMaterial.isImmersiveMaterialSupported()) { return undefined; }
  return new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK,
    applyShadow: true, interactive: false });
}
