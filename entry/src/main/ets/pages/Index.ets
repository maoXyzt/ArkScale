import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import bridge from 'libarkscale_bridge.so';

const VPN_PROBE_EVENT = 'com.arkscale.client.VPN_PROBE_STATUS';

@Entry
@Component
struct Index {
  private goSmokePassed: boolean = bridge.runGoSmoke(1000);
  private lifecyclePassed: boolean = bridge.runGoLifecycle(100);
  private uiPid: number = bridge.getCurrentPid();
  @State private controlStatus: string = 'NOT REQUESTED';
  @State private extensionStatus: string = 'NO EVENT';
  @State private vpnNativeStatus: string = 'NO EVENT';
  private subscriber?: commonEventManager.CommonEventSubscriber;

  aboutToAppear(): void {
    this.subscribeVpnEvents();
  }

  aboutToDisappear(): void {
    if (this.subscriber !== undefined) {
      commonEventManager.unsubscribe(this.subscriber);
      this.subscriber = undefined;
    }
  }

  private async subscribeVpnEvents(): Promise<void> {
    try {
      const subscriber = await commonEventManager.createSubscriber({ events: [VPN_PROBE_EVENT] });
      this.subscriber = subscriber;
      commonEventManager.subscribe(subscriber,
        (error: BusinessError, data: commonEventManager.CommonEventData) => {
          if (error?.code) {
            this.extensionStatus = `EVENT ERROR code=${error.code}`;
            return;
          }
          const payload = data.data;
          if (payload !== undefined) {
            const parts = payload.split('|');
            const status = parts[0];
            const extensionPid = Number(parts[1]);
            this.extensionStatus = `${status} pid=${extensionPid} process=${extensionPid === this.uiPid ? 'SAME' : 'SEPARATE'}`;
            this.vpnNativeStatus = parts[2];
          }
        });
    } catch (error) {
      this.extensionStatus = `SUBSCRIBE FAILED code=${(error as BusinessError).code}`;
    }
  }

  private async startVpn(): Promise<void> {
    this.controlStatus = 'REQUESTING';
    try {
      await vpnExtension.startVpnExtensionAbility({
        bundleName: 'com.arkscale.client',
        moduleName: 'entry',
        abilityName: 'ArkScaleVpnExtension'
      });
      this.controlStatus = 'START REQUESTED';
    } catch (error) {
      this.controlStatus = `START FAILED code=${(error as BusinessError).code}`;
    }
  }

  private async stopVpn(): Promise<void> {
    this.controlStatus = 'STOPPING';
    try {
      await vpnExtension.stopVpnExtensionAbility({
        bundleName: 'com.arkscale.client',
        moduleName: 'entry',
        abilityName: 'ArkScaleVpnExtension'
      });
      this.controlStatus = 'STOP REQUESTED';
    } catch (error) {
      this.controlStatus = `STOP FAILED code=${(error as BusinessError).code}`;
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('ArkScale P2')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
      Text(bridge.getVersion())
        .fontSize(16)
        .fontColor($r('app.color.secondary_text'))
      Text(this.goSmokePassed ? 'Go smoke: PASS' : 'Go smoke: FAIL')
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
      Text(this.lifecyclePassed ? '100 start/stop cycles: PASS' : '100 start/stop cycles: FAIL')
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
      Text(`Control: ${this.controlStatus}`)
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
      Text(`Extension: ${this.extensionStatus}`)
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
      Text(`Native in VPN process: ${this.vpnNativeStatus}`)
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
      Row({ space: 12 }) {
        Button('Start VPN probe')
          .onClick(() => this.startVpn())
        Button('Stop VPN probe')
          .onClick(() => this.stopVpn())
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
