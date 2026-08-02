import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import bridge from 'libarkscale_bridge.so';

@Entry
@Component
struct Index {
  private goSmokePassed: boolean = bridge.runGoSmoke(1000);
  private lifecyclePassed: boolean = bridge.runGoLifecycle(100);
  @State private vpnStatus: string = 'IDLE';
  private statusTimer: number = -1;

  aboutToAppear(): void {
    this.statusTimer = setInterval(() => {
      this.vpnStatus = bridge.getVpnProbeStatus();
    }, 500);
  }

  aboutToDisappear(): void {
    if (this.statusTimer !== -1) {
      clearInterval(this.statusTimer);
      this.statusTimer = -1;
    }
  }

  private async startVpn(): Promise<void> {
    this.vpnStatus = 'REQUESTING VPN PERMISSION';
    try {
      await vpnExtension.startVpnExtensionAbility({
        bundleName: 'com.arkscale.client',
        moduleName: 'entry',
        abilityName: 'ArkScaleVpnExtension'
      });
    } catch (error) {
      this.vpnStatus = `START FAILED: ${(error as BusinessError).code}`;
    }
  }

  private async stopVpn(): Promise<void> {
    try {
      await vpnExtension.stopVpnExtensionAbility({
        bundleName: 'com.arkscale.client',
        moduleName: 'entry',
        abilityName: 'ArkScaleVpnExtension'
      });
    } catch (error) {
      this.vpnStatus = `STOP FAILED: ${(error as BusinessError).code}`;
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
      Text(`VPN probe: ${this.vpnStatus}`)
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
