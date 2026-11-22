import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export enum AppearanceMode {
  SYSTEM = 0,
  LIGHT = 1,
  DARK = 2
}

const STORE_NAME = 'app_appearance';
const KEY_COLOR_MODE = 'color_mode';

/** Persisted application appearance; the saved mode is applied to the whole application. */
export class AppearanceSettings {
  private static store: preferences.Preferences | undefined = undefined;
  private static current: AppearanceMode = AppearanceMode.SYSTEM;

  static initialize(context: common.Context): void {
    if (AppearanceSettings.store !== undefined) { return; }
    try {
      const store = preferences.getPreferencesSync(context, { name: STORE_NAME });
      AppearanceSettings.store = store;
      AppearanceSettings.current = AppearanceSettings.parse(store.getSync(KEY_COLOR_MODE, 'system') as string);
    } catch (_) {
      AppearanceSettings.store = undefined;
      AppearanceSettings.current = AppearanceMode.SYSTEM;
    }
  }

  static mode(): AppearanceMode { return AppearanceSettings.current; }

  static apply(context: common.Context, mode: AppearanceMode): void {
    AppearanceSettings.current = mode;
    try {
      AppearanceSettings.store?.putSync(KEY_COLOR_MODE, AppearanceSettings.value(mode));
      AppearanceSettings.store?.flushSync();
    } catch (_) { /* Keep the in-memory choice even when persistence is unavailable. */ }
    AppearanceSettings.applyColorMode(context, mode);
  }

  static applyColorMode(context: common.Context, mode: AppearanceMode = AppearanceSettings.current): void {
    context.getApplicationContext().setColorMode(AppearanceSettings.colorMode(mode));
  }

  private static parse(value: string): AppearanceMode {
    if (value === 'light') { return AppearanceMode.LIGHT; }
    if (value === 'dark') { return AppearanceMode.DARK; }
    return AppearanceMode.SYSTEM;
  }

  private static value(mode: AppearanceMode): string {
    return mode === AppearanceMode.LIGHT ? 'light' : mode === AppearanceMode.DARK ? 'dark' : 'system';
  }

  private static colorMode(mode: AppearanceMode): ConfigurationConstant.ColorMode {
    return mode === AppearanceMode.LIGHT ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      : mode === AppearanceMode.DARK ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }
}
