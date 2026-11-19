import { uiMaterial } from '@kit.ArkUI';
import { FilterMaterials } from './FilterMaterials';

/** Dynamically imported only on API 26+. Do not statically import from older-compatible page modules. */
export function createFilterMaterials(): FilterMaterials | undefined {
  if (!uiMaterial.isImmersiveMaterialSupported()) { return undefined; }
  return {
    // Search title controls use an untinted light material, like the native back control.
    searchControl: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      applyShadow: false, interactive: true, lightEffect: {} }),
    action: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: $r('app.color.xq_app_filter_action_tint'), applyShadow: false, interactive: true, lightEffect: {} }),
    chip: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      materialColor: $r('app.color.xq_app_filter_material_tint'), applyShadow: false, interactive: true, lightEffect: {} }),
    // Follow the official SegmentButton transparent-backplate example; do not reuse the tinted chip material.
    segment: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
      colorInvert: true, applyShadow: false, interactive: true, lightEffect: {} }),
    menu: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THICK,
      applyShadow: true, interactive: true, lightEffect: {} })
  };
}
