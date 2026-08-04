import { common, contextConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { connection, socket, vpnExtension } from '@kit.NetworkKit';
import bridge from 'libarkscale_bridge.so';
import { COMMAND_KEY, ENGINE_KEY, NETWORK_KEY, ProbeChannel, STATUS_KEY } from '../ProbeChannel';

const BUNDLE_NAME = 'com.arkscale.client';

interface EngineEvent {
  schemaVersion: number;
  type: string;
  state?: string;
  url?: string;
  severity?: string;
  message?: string;
  target?: string;
  ok?: boolean;
  nodeName?: string;
  path?: string;
  latencyMs?: number;
  dnsName?: string;
  error?: string;
  process?: ProcessStats;
}

interface ProcessStats {
  rssKb: number;
  openFds: number;
  threads: number;
  goroutines: number;
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
  @State private peerTarget: string = '';
  @State private peerStatus: string = 'NOT TESTED';
  @State private tcpStatus: string = 'NOT TESTED';
  @State private magicDnsTarget: string = '';
  @State private magicDnsStatus: string = 'NOT TESTED';
  @State private resourceStatus: string = 'NOT MEASURED';
  private channel?: ProbeChannel;
  private channelSubscribed: boolean = false;
  private stopRequested: boolean = false;
  private logoutRequested: boolean = false;
  private channelChanged = (key: number): void => {
    const payload = this.channel?.read(key);
    if (payload === undefined) {
      return;
    }
    if (key === ENGINE_KEY) {
      this.handleEngineEvent(payload);
    } else if (key === STATUS_KEY || key === NETWORK_KEY) {
      this.handleVpnStatus(payload);
    }
  };

  aboutToAppear(): void {
    this.subscribeVpnEvents();
  }

  aboutToDisappear(): void {
    if (this.channel !== undefined && this.channelSubscribed) {
      this.channel.stop();
      this.channelSubscribed = false;
    }
  }

  onPageShow(): void {
    this.requestStatus();
  }

  private async subscribeVpnEvents(): Promise<void> {
    try {
      const channel = await this.getChannel();
      if (!this.channelSubscribed) {
        channel.start(this.channelChanged);
        this.channelSubscribed = true;
      }
      this.requestStatus();
    } catch (error) {
      this.extensionStatus = `SUBSCRIBE FAILED code=${(error as BusinessError).code}`;
    }
  }

  private async getChannel(): Promise<ProbeChannel> {
    if (this.channel !== undefined) {
      return this.channel;
    }
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      throw new Error('UI context unavailable');
    }
    this.channel = new ProbeChannel(
      context.createAreaModeContext(contextConstant.AreaMode.EL1).filesDir,
      [STATUS_KEY, NETWORK_KEY, ENGINE_KEY]);
    return this.channel;
  }

  private async requestStatus(): Promise<void> {
    try {
      await (await this.getChannel()).publish(COMMAND_KEY, 'STATUS');
    } catch (error) {
      this.extensionStatus = `STATUS REQUEST FAILED code=${(error as BusinessError).code ?? -1}`;
    }
  }

  private handleVpnStatus(payload: string): void {
    const parts = payload.split('|');
    const status = parts[0];
    const extensionPid = Number(parts[1]);
    const uptimeMinutes = Number(parts[3]);
    this.vpnNativeStatus = parts[2];
    if (status.startsWith('NETWORK ')) {
      this.networkStatus = status.substring(8);
    } else {
      this.extensionStatus = `${status} uptimeMin=${uptimeMinutes} pid=${extensionPid} process=${extensionPid === this.uiPid ? 'SAME' : 'SEPARATE'}`;
      if (status === 'STOPPED' && this.stopRequested) {
        this.stopRequested = false;
        this.finishVpnStop('STOPPED');
      } else if (status.startsWith('STOP FAIL') && this.stopRequested) {
        this.stopRequested = false;
        this.controlStatus = 'STOP FAILED IN EXTENSION';
      } else if (status === 'LOGGED_OUT' && this.logoutRequested) {
        this.logoutRequested = false;
        this.finishVpnStop('LOGGED OUT');
      } else if (status.startsWith('LOGOUT FAIL') && this.logoutRequested) {
        this.logoutRequested = false;
        this.controlStatus = 'LOGOUT FAILED IN EXTENSION';
      }
    }
  }

  private async startVpn(): Promise<void> {
    this.stopRequested = false;
    this.logoutRequested = false;
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

  private async stopVpn(): Promise<void> {
    if (this.stopRequested || this.logoutRequested) {
      return;
    }
    this.stopRequested = true;
    this.controlStatus = 'STOP REQUESTED';
    try {
      await (await this.getChannel()).publish(COMMAND_KEY, 'STOP');
    } catch (error) {
      this.stopRequested = false;
      this.controlStatus = `STOP COMMAND FAILED code=${(error as BusinessError).code}`;
    }
  }

  private async logoutVpn(): Promise<void> {
    if (this.stopRequested || this.logoutRequested) {
      return;
    }
    this.logoutRequested = true;
    this.controlStatus = 'LOGOUT REQUESTED';
    try {
      await (await this.getChannel()).publish(COMMAND_KEY, 'LOGOUT');
    } catch (error) {
      this.logoutRequested = false;
      this.controlStatus = `LOGOUT COMMAND FAILED code=${(error as BusinessError).code ?? -1}`;
    }
  }

  private async finishVpnStop(status: string): Promise<void> {
    this.controlStatus = 'STOPPING EXTENSION';
    try {
      await vpnExtension.stopVpnExtensionAbility({
        bundleName: BUNDLE_NAME,
        moduleName: 'entry',
        abilityName: 'ArkScaleVpnExtension'
      });
      this.controlStatus = status;
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
      `Network: ${this.networkStatus}\n` +
      `Peer: ${this.peerStatus}\n` +
      `TCP: ${this.tcpStatus}\n` +
      `MagicDNS: ${this.magicDnsStatus}\n` +
      `Resources: ${this.resourceStatus}`;
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
      } else if (event.type === 'peer-probe' && event.target !== undefined && event.path !== undefined) {
        this.magicDnsTarget = (event.dnsName ?? '').replace(/\.$/, '');
        if (event.process !== undefined) {
          this.resourceStatus = `rss=${event.process.rssKb}KB fds=${event.process.openFds} threads=${event.process.threads} goroutines=${event.process.goroutines}`;
        }
        this.peerStatus = event.ok ?
          `PASS ${event.nodeName ?? event.target} ${(event.latencyMs ?? 0).toFixed(1)}ms ${event.path}` :
          `FAIL ${event.nodeName ?? event.target} ${event.error ?? 'unknown error'} path=${event.path}`;
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

  private async probePeer(): Promise<void> {
    const target = this.peerTarget.trim();
    if (target.length === 0 || target.length > 128) {
      this.peerStatus = 'INVALID IP';
      return;
    }
    this.peerStatus = 'PROBING';
    try {
      await (await this.getChannel()).publish(COMMAND_KEY, `PING|${target}`);
    } catch (error) {
      this.peerStatus = `REQUEST FAILED code=${(error as BusinessError).code ?? -1}`;
    }
  }

  private async probeMagicDns(): Promise<void> {
    const target = this.magicDnsTarget.trim();
    if (target.length === 0 || target.length > 253) {
      this.magicDnsStatus = 'INVALID HOSTNAME';
      return;
    }
    this.magicDnsStatus = 'RESOLVING';
    try {
      const addresses = await connection.getAddressesByName(target);
      this.magicDnsStatus = addresses.length > 0 ?
        `PASS ${target} -> ${addresses.map((address: connection.NetAddress): string => address.address).join(',')}` :
        `FAIL ${target} no addresses`;
    } catch (error) {
      this.magicDnsStatus = `FAIL ${target} code=${(error as BusinessError).code ?? -1}`;
    }
  }

  private async probeSshPort(): Promise<void> {
    const target = this.peerTarget.trim();
    if (target.length === 0) {
      this.tcpStatus = 'INVALID TARGET';
      return;
    }
    const client = socket.constructTCPSocketInstance();
    const startedAt = Date.now();
    this.tcpStatus = `CONNECTING ${target}:22`;
    try {
      await client.connect({ address: { address: target, family: target.includes(':') ? 2 : 1, port: 22 }, timeout: 5000 });
      this.tcpStatus = `PASS ${target}:22 ${Date.now() - startedAt}ms`;
    } catch (error) {
      this.tcpStatus = `FAIL ${target}:22 code=${(error as BusinessError).code ?? -1}`;
    }
    try {
      await client.close();
    } catch (error) {
    }
  }

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text('ArkScale P5')
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
        TextInput({ placeholder: 'Peer Tailscale IP', text: this.peerTarget })
          .width('80%')
          .onChange((value: string) => this.peerTarget = value)
        Button('Probe peer')
          .onClick(() => this.probePeer())
        Button('Probe TCP 22')
          .onClick(() => this.probeSshPort())
        TextInput({ placeholder: 'MagicDNS hostname', text: this.magicDnsTarget })
          .width('80%')
          .onChange((value: string) => this.magicDnsTarget = value)
        Button('Resolve MagicDNS')
          .onClick(() => this.probeMagicDns())
        Row({ space: 12 }) {
          Button('Start ArkScale')
            .onClick(() => this.startVpn())
          Button('Stop ArkScale')
            .onClick(() => this.stopVpn())
        }
        Button('Log out and forget identity')
          .onClick(() => this.logoutVpn())
      }
      .width('100%')
      .padding({ top: 24, bottom: 24 })
    }
    .width('100%')
    .height('100%')
  }
}
