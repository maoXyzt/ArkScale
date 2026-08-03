import { common } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import bridge from 'libarkscale_bridge.so';

const VPN_PROBE_EVENT = 'com.arkscale.client.VPN_PROBE_STATUS';
const VPN_PROBE_COMMAND_EVENT = 'com.arkscale.client.VPN_PROBE_COMMAND';
const ENGINE_EVENT = 'com.arkscale.client.ENGINE_EVENT';
const BUNDLE_NAME = 'com.arkscale.client';

interface EngineEvent {
  schemaVersion: number;
  type: string;
  state?: string;
  url?: string;
  severity?: string;
  message?: string;
}

@Entry
@Component
struct Index {
  private goSmokePassed: boolean = bridge.runGoSmoke(1000);
  private lifecyclePassed: boolean = bridge.runGoLifecycle(100);
  private uiPid: number = bridge.getCurrentPid();
  @State private controlStatus: string = 'NOT REQUESTED';
  @State private extensionStatus: string = 'NO EVENT';
  @State private vpnNativeStatus: string = 'NO EVENT';
  @State private networkStatus: string = 'NOT REGISTERED';
  @State private engineStatus: string = 'NOT STARTED';
  @State private loginUrl: string = '';
  private subscriber?: commonEventManager.CommonEventSubscriber;
  private stopRequested: boolean = false;

  aboutToAppear(): void {
    this.subscribeVpnEvents();
  }

  aboutToDisappear(): void {
    if (this.subscriber !== undefined) {
      commonEventManager.unsubscribe(this.subscriber);
      this.subscriber = undefined;
    }
  }

  onPageShow(): void {
    this.requestStatus();
  }

  private async subscribeVpnEvents(): Promise<void> {
    try {
      const subscriber = await commonEventManager.createSubscriber({
        events: [VPN_PROBE_EVENT, ENGINE_EVENT],
        publisherBundleName: BUNDLE_NAME
      });
      this.subscriber = subscriber;
      commonEventManager.subscribe(subscriber,
        (error: BusinessError, data: commonEventManager.CommonEventData) => {
          if (error?.code) {
            this.extensionStatus = `EVENT ERROR code=${error.code}`;
            return;
          }
          if (data.event === ENGINE_EVENT) {
            if (data.data !== undefined) {
              this.handleEngineEvent(data.data);
            }
            return;
          }
          const payload = data.data;
          if (payload !== undefined) {
            const parts = payload.split('|');
            const status = parts[0];
            const extensionPid = Number(parts[1]);
            this.vpnNativeStatus = parts[2];
            if (status.startsWith('NETWORK ')) {
              this.networkStatus = status.substring(8);
            } else {
              this.extensionStatus = `${status} pid=${extensionPid} process=${extensionPid === this.uiPid ? 'SAME' : 'SEPARATE'}`;
              if (status === 'STOPPED' && this.stopRequested) {
                this.stopRequested = false;
                this.finishVpnStop();
              } else if (status.startsWith('STOP FAIL') && this.stopRequested) {
                this.stopRequested = false;
                this.controlStatus = 'STOP FAILED IN EXTENSION';
              }
            }
          }
        });
      this.requestStatus();
    } catch (error) {
      this.extensionStatus = `SUBSCRIBE FAILED code=${(error as BusinessError).code}`;
    }
  }

  private requestStatus(): void {
    commonEventManager.publish(VPN_PROBE_COMMAND_EVENT, {
      bundleName: BUNDLE_NAME,
      data: 'STATUS'
    }, (error: BusinessError) => {
      if (error?.code) {
        this.extensionStatus = `STATUS REQUEST FAILED code=${error.code}`;
      }
    });
  }

  private async startVpn(): Promise<void> {
    this.stopRequested = false;
    this.networkStatus = 'REGISTERING';
    this.engineStatus = 'STARTING';
    this.loginUrl = '';
    this.controlStatus = 'REQUESTING';
    try {
      await vpnExtension.startVpnExtensionAbility({
        bundleName: BUNDLE_NAME,
        moduleName: 'entry',
        abilityName: 'ArkScaleVpnExtension'
      });
      this.controlStatus = 'START REQUESTED';
    } catch (error) {
      this.controlStatus = `START FAILED code=${(error as BusinessError).code}`;
    }
  }

  private stopVpn(): void {
    if (this.stopRequested) {
      return;
    }
    this.stopRequested = true;
    this.controlStatus = 'STOP REQUESTED';
    try {
      commonEventManager.publish(VPN_PROBE_COMMAND_EVENT, {
        bundleName: BUNDLE_NAME,
        data: 'STOP'
      }, (error: BusinessError) => {
        if (error?.code) {
          this.stopRequested = false;
          this.controlStatus = `STOP COMMAND FAILED code=${error.code}`;
        }
      });
    } catch (error) {
      this.stopRequested = false;
      this.controlStatus = `STOP COMMAND FAILED code=${(error as BusinessError).code}`;
    }
  }

  private async finishVpnStop(): Promise<void> {
    this.controlStatus = 'STOPPING EXTENSION';
    try {
      await vpnExtension.stopVpnExtensionAbility({
        bundleName: BUNDLE_NAME,
        moduleName: 'entry',
        abilityName: 'ArkScaleVpnExtension'
      });
      this.controlStatus = 'STOPPED';
    } catch (error) {
      this.controlStatus = `EXTENSION STOP FAILED code=${(error as BusinessError).code}`;
    }
  }

  private diagnosticText(): string {
    return `${bridge.getVersion()}\n` +
      `${this.goSmokePassed ? 'Go smoke: PASS' : 'Go smoke: FAIL'}\n` +
      `${this.lifecyclePassed ? '100 start/stop cycles: PASS' : '100 start/stop cycles: FAIL'}\n` +
      `Control: ${this.controlStatus}\n` +
      `Extension: ${this.extensionStatus}\n` +
      `Native in VPN process: ${this.vpnNativeStatus}\n` +
      `Backend: ${this.engineStatus}\n` +
      `Network: ${this.networkStatus}`;
  }

  private handleEngineEvent(eventJson: string): void {
    try {
      const event = JSON.parse(eventJson) as EngineEvent;
      if (event.schemaVersion !== 1) {
        throw new Error('unsupported schema');
      }
      if (event.type === 'state' && event.state !== undefined) {
        this.engineStatus = event.state.toUpperCase();
        if (event.state === 'running') {
          this.loginUrl = '';
        }
      } else if (event.type === 'login-url' && event.url !== undefined) {
        this.loginUrl = event.url;
        this.engineStatus = 'LOGIN REQUIRED';
      } else if (event.type === 'health' && event.severity !== undefined && event.message !== undefined) {
        this.engineStatus = `${event.severity.toUpperCase()}: ${event.message}`;
      }
    } catch (error) {
      this.engineStatus = `EVENT ERROR: ${(error as Error).message}`;
    }
  }

  private async openLogin(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined || this.loginUrl.length === 0) {
      return;
    }
    try {
      await (context as common.UIAbilityContext).openLink(this.loginUrl);
    } catch (error) {
      this.engineStatus = `LOGIN OPEN FAILED code=${(error as BusinessError).code ?? -1}`;
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('ArkScale P3')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
      Text(this.diagnosticText())
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
        .copyOption(CopyOptions.LocalDevice)
      Text('Long press the status text to copy')
        .fontSize(12)
        .fontColor($r('app.color.secondary_text'))
      if (this.loginUrl.length > 0) {
        Button('Open Tailscale login')
          .onClick(() => this.openLogin())
      }
      Row({ space: 12 }) {
        Button('Start ArkScale')
          .onClick(() => this.startVpn())
        Button('Stop ArkScale')
          .onClick(() => this.stopVpn())
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
