import { MapComponent, map, mapCommon, sceneMap } from '@kit.MapKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LedgerLocation } from '../domain/model/LedgerLocation';

/** A non-interactive preview; the original Map Kit detail sheet provides full exploration. */
@Component
export struct EntryLocationMap {
  @Prop location: LedgerLocation | undefined = undefined;
  @Prop merchantName: string = '';
  @Prop addressText: string = '';
  @State private failed: boolean = false;
  @State private loaded: boolean = false;
  @State private opening: boolean = false;
  @State private generation: number = 0;
  private active: boolean = false;
  private controller: map.MapComponentController | undefined = undefined;

  aboutToAppear(): void { this.active = true; }
  aboutToDisappear(): void {
    this.active = false;
    this.removeListeners();
  }

  private removeListeners(): void {
    if (this.controller === undefined) { return; }
    const controller = this.controller;
    this.controller = undefined;
    try {
      controller.getEventManager().off('error');
      controller.getEventManager().off('mapLoad');
    } catch (_) { /* The native map may already have been destroyed with its view. */ }
  }

  private mapPosition(): mapCommon.LatLng {
    return { latitude: (this.location?.latitudeE6 || 0) / 1000000,
      longitude: (this.location?.longitudeE6 || 0) / 1000000 };
  }

  private options(): mapCommon.MapOptions {
    return { position: { target: this.mapPosition(), zoom: 16 },
      scrollGesturesEnabled: false, rotateGesturesEnabled: false,
      zoomGesturesEnabled: false, tiltGesturesEnabled: false,
      zoomControlsEnabled: false, myLocationControlsEnabled: false, compassControlsEnabled: false };
  }

  private async initialize(controller: map.MapComponentController): Promise<void> {
    if (!this.active) { return; }
    this.controller = controller;
    controller.getEventManager().on('error', (_error: BusinessError) => {
      if (this.active && this.controller === controller) { this.failed = true; }
    });
    controller.getEventManager().on('mapLoad', () => {
      if (this.active && this.controller === controller) { this.loaded = true; }
    });
    try {
      await controller.addMarker({ position: this.mapPosition(), title: this.merchantName || '账目位置' });
    } catch (_) {
      if (this.active && this.controller === controller) { this.failed = true; }
    }
  }

  private retry(): void {
    this.removeListeners();
    this.failed = false; this.loaded = false; this.generation++;
  }

  private async openDetails(): Promise<void> {
    if (!this.active || this.opening || this.location === undefined) { return; }
    this.opening = true;
    try {
      await sceneMap.queryLocation(this.getUIContext().getHostContext() as common.UIAbilityContext, {
        location: this.mapPosition(), name: this.merchantName || '账目位置', address: this.addressText,
        showBusiness: false,
        cancelCallback: () => { if (this.active) { this.opening = false; } }
      });
    } catch (_) {
      if (this.active) {
        this.getUIContext().getPromptAction().showToast({ message: '暂时无法打开地图，地址已保留' });
      }
    } finally { if (this.active) { this.opening = false; } }
  }

  build() {
    Column({ space: 0 }) {
      Stack() {
        if (!this.failed && canIUse('SystemCapability.Map.Core')) {
          ForEach([this.generation], (_version: number) => {
            MapComponent({ mapOptions: this.options(),
              mapCallback: (error: BusinessError, controller: map.MapComponentController) => {
                if (!this.active || _version !== this.generation) { return; }
                if (error || controller === undefined) { this.failed = true; return; }
                this.initialize(controller);
              } })
              .width('100%').height(180).hitTestBehavior(HitTestMode.None)
          }, (version: number) => version.toString())
        } else {
          Column({ space: 10 }) {
            Text('地图暂不可用').fontSize('13fp').fontColor($r('app.color.xq_font_secondary'))
            if (canIUse('SystemCapability.Map.Core')) {
              Button('重试', { type: ButtonType.Capsule }).fontSize('12fp')
                .fontColor($r('app.color.xq_font_emphasize')).backgroundColor(Color.Transparent)
                .id('entry-location-map-retry').onClick(() => { this.retry(); })
            }
          }.width('100%').height(180).justifyContent(FlexAlign.Center)
        }
      }.width('100%').height(180).clip(true).borderRadius(12)
        .backgroundColor($r('app.color.xq_app_surface_page')).id('entry-location-map-preview')
        .accessibilityText('查看账目位置地图').onClick(() => { this.openDetails(); })
      Row() {
        Text(this.failed || !canIUse('SystemCapability.Map.Core') ? '地址已保留' : this.loaded ? '点击查看位置' : '地图加载中…')
          .fontSize('12fp').fontColor($r('app.color.xq_font_secondary')).id('entry-location-map-status')
        Blank()
        Button(this.opening ? '打开中' : '查看地图', { type: ButtonType.Capsule })
          .fontSize('12fp').fontColor($r('app.color.xq_font_emphasize')).backgroundColor(Color.Transparent)
          .padding({ left: 0, right: 0 }).height(36).enabled(!this.opening && canIUse('SystemCapability.Map.Core'))
          .id('entry-location-map-open').onClick(() => { this.openDetails(); })
      }.width('100%')
    }.width('100%').padding({ top: 4, bottom: 6 }).id('entry-location-map')
  }
}
