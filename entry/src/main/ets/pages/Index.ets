import { common, contextConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { connection, socket, vpnExtension } from '@kit.NetworkKit';
import bridge from 'libarkscale_bridge.so';
import { COMMAND_KEY, ENGINE_KEY, NETWORK_KEY, PEERS_KEY, ProbeChannel, STATUS_KEY } from '../ProbeChannel';

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

interface PeerSummary {
  id: string;
  name: string;
  dnsName: string;
  address: string;
  os: string;
  online: boolean;
  onlineKnown: boolean;
}

interface PeerListEvent {
  schemaVersion: number;
  type: string;
  total: number;
  peers: Array<PeerSummary>;
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
  @State private peers: Array<PeerSummary> = [];
  @State private peerTotal: number = 0;
  @State private peersLoaded: boolean = false;
  @State private peerListFailed: boolean = false;
  @State private diagnosticsExpanded: boolean = false;
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
    } else if (key === PEERS_KEY) {
      this.handlePeerList(payload);
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
      [STATUS_KEY, NETWORK_KEY, ENGINE_KEY, PEERS_KEY]);
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
    this.extensionStatus = 'STARTING';
    this.vpnNativeStatus = 'STARTING';
    this.networkStatus = 'REGISTERING';
    this.engineStatus = 'STARTING';
    this.loginUrl = '';
    this.peerStatus = 'NOT TESTED';
    this.tcpStatus = 'NOT TESTED';
    this.magicDnsStatus = 'NOT TESTED';
    this.resourceStatus = 'NOT MEASURED';
    this.clearPeers();
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

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.logout_dialog_title'),
      message: $r('app.string.logout_dialog_message'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.cancel'),
        defaultFocus: true,
        action: (): void => {}
      },
      secondaryButton: {
        value: $r('app.string.logout'),
        action: (): void => {
          this.logoutVpn();
        }
      }
    });
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
        } else if (event.state === 'stopped' || event.state === 'logged-out') {
          this.clearPeers();
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

  private handlePeerList(eventJson: string): void {
    try {
      const event = JSON.parse(eventJson) as PeerListEvent;
      if (event.schemaVersion !== 1 || event.type !== 'peer-list' || !Array.isArray(event.peers) ||
        event.peers.length > 50 || event.total < event.peers.length || event.total > 100000 ||
        !event.peers.every((peer: PeerSummary): boolean => this.validPeer(peer))) {
        throw new Error('invalid peer list');
      }
      this.peers = event.peers;
      this.peerTotal = event.total;
      this.peersLoaded = true;
      this.peerListFailed = false;
    } catch (error) {
      this.peers = [];
      this.peerTotal = 0;
      this.peersLoaded = false;
      this.peerListFailed = true;
    }
  }

  private validPeer(peer: PeerSummary): boolean {
    return typeof peer.id === 'string' && peer.id.length <= 128 &&
      typeof peer.name === 'string' && peer.name.length > 0 && peer.name.length <= 253 &&
      typeof peer.dnsName === 'string' && peer.dnsName.length <= 253 &&
      typeof peer.address === 'string' && peer.address.length <= 64 &&
      typeof peer.os === 'string' && peer.os.length <= 64 &&
      typeof peer.online === 'boolean' && typeof peer.onlineKnown === 'boolean';
  }

  private clearPeers(): void {
    this.peers = [];
    this.peerTotal = 0;
    this.peersLoaded = false;
    this.peerListFailed = false;
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

  private isConnected(): boolean {
    return this.engineStatus === 'RUNNING' && this.extensionStatus.startsWith('READY');
  }

  private isStopping(): boolean {
    return this.stopRequested || this.logoutRequested || this.controlStatus === 'STOPPING EXTENSION';
  }

  private isBusy(): boolean {
    if (this.isStopping()) {
      return true;
    }
    if (this.isConnected() || this.loginUrl.length > 0 || this.hasError()) {
      return false;
    }
    return this.engineStatus === 'STARTING' || this.controlStatus === 'REQUESTING' ||
      this.controlStatus === 'START REQUESTED';
  }

  private hasError(): boolean {
    return this.controlStatus.includes('FAIL') || this.extensionStatus.includes('FAIL') ||
      this.vpnNativeStatus.includes('FAIL') || this.engineStatus.includes('ERROR');
  }

  private hasPeerTarget(): boolean {
    const length = this.peerTarget.trim().length;
    return length > 0 && length <= 128;
  }

  private hasMagicDnsTarget(): boolean {
    const length = this.magicDnsTarget.trim().length;
    return length > 0 && length <= 253;
  }

  private selectPeerAndProbe(peer: PeerSummary): void {
    if (!this.isConnected() || peer.address.length === 0) {
      return;
    }
    this.peerTarget = peer.address;
    this.magicDnsTarget = peer.dnsName;
    this.probePeer();
  }

  private peerStatusText(peer: PeerSummary): ResourceStr {
    if (!peer.onlineKnown) {
      return $r('app.string.peer_unknown');
    }
    return peer.online ? $r('app.string.peer_online') : $r('app.string.peer_offline');
  }

  private peerStatusColor(peer: PeerSummary): ResourceColor {
    return peer.onlineKnown && peer.online ? $r('app.color.status_success') : $r('app.color.status_idle');
  }

  private connectionColor(): ResourceColor {
    if (this.hasError()) {
      return $r('app.color.status_error');
    }
    if (this.isStopping() || this.isBusy() || this.loginUrl.length > 0) {
      return $r('app.color.tunnel_accent');
    }
    if (this.isConnected()) {
      return $r('app.color.status_success');
    }
    return $r('app.color.status_idle');
  }

  private backendSummary(): ResourceStr {
    if (this.engineStatus === 'RUNNING') {
      return $r('app.string.state_running');
    }
    if (this.engineStatus === 'STARTING') {
      return $r('app.string.state_starting');
    }
    if (this.engineStatus === 'LOGIN REQUIRED') {
      return $r('app.string.state_login_required');
    }
    if (this.engineStatus === 'STOPPED' || this.engineStatus === 'NOT STARTED') {
      return $r('app.string.state_stopped');
    }
    return this.engineStatus.includes('ERROR') ? $r('app.string.state_attention') : $r('app.string.state_idle');
  }

  private networkSummary(): ResourceStr {
    if (this.networkStatus.includes('->WIFI') || this.networkStatus.includes('bearer=WIFI')) {
      return $r('app.string.network_wifi');
    }
    if (this.networkStatus.includes('->CELLULAR') || this.networkStatus.includes('bearer=CELLULAR')) {
      return $r('app.string.network_cellular');
    }
    if (this.networkStatus === 'REGISTERING') {
      return $r('app.string.state_registering');
    }
    if (this.networkStatus === 'NOT REGISTERED') {
      return $r('app.string.state_not_registered');
    }
    return this.networkStatus.includes('FAIL') ? $r('app.string.state_attention') : $r('app.string.state_idle');
  }

  private vpnServiceSummary(): ResourceStr {
    if (this.extensionStatus.startsWith('READY')) {
      return $r('app.string.state_ready');
    }
    if (this.extensionStatus === 'STARTING') {
      return $r('app.string.state_starting');
    }
    if (this.extensionStatus.startsWith('STOPPED')) {
      return $r('app.string.state_stopped');
    }
    if (this.extensionStatus.includes('FAIL')) {
      return $r('app.string.state_attention');
    }
    return $r('app.string.state_idle');
  }

  @Builder
  private overviewRow(label: ResourceStr, kind: number) {
    Row({ space: 16 }) {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Text(kind === 0 ? this.backendSummary() : kind === 1 ? this.networkSummary() : this.vpnServiceSummary())
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.End)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  private peerRow(peer: PeerSummary) {
    Row({ space: 12 }) {
      Text('●')
        .fontSize(11)
        .fontColor(this.peerStatusColor(peer))
      Column({ space: 3 }) {
        Text(peer.name)
          .width('100%')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(peer.os.length > 0 ? `${peer.address} · ${peer.os}` : peer.address)
          .width('100%')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.peerStatusText(peer))
          .width('100%')
          .fontSize(11)
          .fontColor(this.peerStatusColor(peer))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Button($r('app.string.action_probe_peer_short'))
        .width(72)
        .height(44)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r('app.color.control_secondary'))
        .borderRadius(10)
        .enabled(this.isConnected() && peer.address.length > 0 && this.peerStatus !== 'PROBING')
        .onClick(() => this.selectPeerAndProbe(peer))
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  build() {
    Scroll() {
      Column({ space: 16 }) {
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text($r('app.string.app_name'))
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.app_tagline'))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
          Text($r('app.string.self_deployed'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.tunnel_accent'))
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor($r('app.color.accent_surface'))
            .borderRadius(12)
        }
        .width('100%')

        Column({ space: 16 }) {
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              Text('●')
                .fontSize(12)
                .fontColor(this.connectionColor())
              if (this.hasError()) {
                Text($r('app.string.connection_attention'))
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.status_error'))
              } else if (this.isStopping()) {
                Text($r('app.string.connection_disconnecting'))
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.tunnel_accent'))
              } else if (this.loginUrl.length > 0) {
                Text($r('app.string.connection_login_required'))
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.tunnel_accent'))
              } else if (this.isConnected()) {
                Text($r('app.string.connection_connected'))
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.status_success'))
              } else if (this.isBusy()) {
                Text($r('app.string.connection_connecting'))
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.tunnel_accent'))
              } else {
                Text($r('app.string.connection_disconnected'))
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
              }
            }
            if (this.hasError()) {
              Text($r('app.string.connection_hint_error'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            } else if (this.isStopping()) {
              Text($r('app.string.connection_hint_disconnecting'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            } else if (this.loginUrl.length > 0) {
              Text($r('app.string.connection_hint_login'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            } else if (this.isConnected()) {
              Text($r('app.string.connection_hint_connected'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            } else if (this.isBusy()) {
              Text($r('app.string.connection_hint_connecting'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            } else {
              Text($r('app.string.connection_hint_disconnected'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            }
          }
          .alignItems(HorizontalAlign.Center)
          .width('100%')

          Column({ space: 6 }) {
            Row() {
              Text('●')
                .fontSize(12)
                .fontColor(this.connectionColor())
              Blank()
                .layoutWeight(1)
                .height(2)
                .backgroundColor(this.connectionColor())
              Text('●')
                .fontSize(18)
                .fontColor(this.connectionColor())
              Blank()
                .layoutWeight(1)
                .height(2)
                .backgroundColor(this.isConnected() ? this.connectionColor() : $r('app.color.border_soft'))
              Text('●')
                .fontSize(12)
                .fontColor(this.isConnected() ? this.connectionColor() : $r('app.color.status_idle'))
            }
            .width('100%')
            Row() {
              Text($r('app.string.rail_device'))
                .fontSize(10)
                .fontColor($r('app.color.text_muted'))
              Blank()
              Text($r('app.string.rail_tunnel'))
                .fontSize(10)
                .fontColor($r('app.color.text_muted'))
              Blank()
              Text($r('app.string.rail_tailnet'))
                .fontSize(10)
                .fontColor($r('app.color.text_muted'))
            }
            .width('100%')
          }

          if (this.isStopping()) {
            Button(this.logoutRequested ? $r('app.string.action_signing_out') : $r('app.string.action_disconnecting'))
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontColor($r('app.color.text_muted'))
              .backgroundColor($r('app.color.control_disabled'))
              .borderRadius(12)
              .enabled(false)
          } else if (this.loginUrl.length > 0) {
            Button($r('app.string.action_sign_in'))
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.tunnel_accent'))
              .borderRadius(12)
              .onClick(() => this.openLogin())
          } else if (this.isConnected()) {
            Button($r('app.string.action_disconnect'))
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.status_success'))
              .borderRadius(12)
              .onClick(() => this.stopVpn())
          } else if (this.isBusy()) {
            Button($r('app.string.action_connecting'))
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontColor($r('app.color.text_muted'))
              .backgroundColor($r('app.color.control_disabled'))
              .borderRadius(12)
              .enabled(false)
          } else {
            Button($r('app.string.action_connect'))
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.tunnel_accent'))
              .borderRadius(12)
              .onClick(() => this.startVpn())
          }
        }
        .width('100%')
        .padding(20)
        .backgroundColor($r('app.color.surface_primary'))
        .border({ width: 1, color: $r('app.color.border_standard') })
        .borderRadius(16)

        Column() {
          Row() {
            Text($r('app.string.connection_overview'))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text(bridge.getVersion())
              .fontSize(11)
              .fontColor($r('app.color.text_muted'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
          .padding({ bottom: 8 })
          this.overviewRow($r('app.string.overview_backend'), 0)
          Divider()
            .color($r('app.color.border_soft'))
          this.overviewRow($r('app.string.overview_network'), 1)
          Divider()
            .color($r('app.color.border_soft'))
          this.overviewRow($r('app.string.overview_vpn_service'), 2)
        }
        .width('100%')
        .padding(20)
        .backgroundColor($r('app.color.surface_primary'))
        .border({ width: 1, color: $r('app.color.border_standard') })
        .borderRadius(16)

        Column({ space: 12 }) {
          Row() {
            Text($r('app.string.devices_title'))
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Blank()
            if (this.peersLoaded) {
              Text(this.peerTotal > this.peers.length ? `${this.peers.length}/${this.peerTotal}` : `${this.peerTotal}`)
                .fontSize(12)
                .fontColor($r('app.color.text_muted'))
            }
          }
          .width('100%')

          if (!this.isConnected()) {
            Text($r('app.string.devices_connect_hint'))
              .width('100%')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          } else if (this.peerListFailed) {
            Text($r('app.string.devices_load_failed'))
              .width('100%')
              .fontSize(13)
              .fontColor($r('app.color.status_error'))
          } else if (!this.peersLoaded) {
            Text($r('app.string.devices_loading'))
              .width('100%')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          } else if (this.peers.length === 0) {
            Text($r('app.string.devices_empty'))
              .width('100%')
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
          } else {
            ForEach(this.peers, (peer: PeerSummary, index: number) => {
              if (index > 0) {
                Divider()
                  .color($r('app.color.border_soft'))
              }
              this.peerRow(peer)
            }, (peer: PeerSummary): string => `${peer.id}|${peer.address}`)
          }
        }
        .width('100%')
        .padding(20)
        .backgroundColor($r('app.color.surface_primary'))
        .border({ width: 1, color: $r('app.color.border_standard') })
        .borderRadius(16)

        Column({ space: 16 }) {
          Row() {
            Column({ space: 3 }) {
              Text($r('app.string.diagnostics_title'))
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text($r('app.string.diagnostics_subtitle'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')

          Button(this.diagnosticsExpanded ? $r('app.string.diagnostics_hide') : $r('app.string.diagnostics_show'))
            .width('100%')
            .height(44)
            .fontSize(14)
            .fontColor($r('app.color.tunnel_accent'))
            .backgroundColor($r('app.color.accent_surface'))
            .borderRadius(10)
            .onClick(() => this.diagnosticsExpanded = !this.diagnosticsExpanded)

          if (this.diagnosticsExpanded) {
            Divider()
              .color($r('app.color.border_soft'))

            Column({ space: 10 }) {
              Text($r('app.string.peer_tools_title'))
                .width('100%')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              TextInput({ placeholder: $r('app.string.peer_ip_placeholder'), text: this.peerTarget })
                .width('100%')
                .height(46)
                .fontColor($r('app.color.text_primary'))
                .placeholderColor($r('app.color.text_muted'))
                .backgroundColor($r('app.color.surface_inset'))
                .border({ width: 1, color: $r('app.color.border_standard') })
                .borderRadius(10)
                .maxLength(128)
                .accessibilityText($r('app.string.peer_ip_accessibility'))
                .onChange((value: string) => this.peerTarget = value)
              Row({ space: 10 }) {
                Button(this.peerStatus === 'PROBING' ? $r('app.string.action_testing') : $r('app.string.action_probe_peer'))
                  .layoutWeight(1)
                  .height(42)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.control_secondary'))
                  .borderRadius(10)
                  .enabled(this.isConnected() && this.hasPeerTarget() && this.peerStatus !== 'PROBING')
                  .onClick(() => this.probePeer())
                Button(this.tcpStatus.startsWith('CONNECTING') ? $r('app.string.action_testing') : $r('app.string.action_probe_tcp'))
                  .layoutWeight(1)
                  .height(42)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.control_secondary'))
                  .borderRadius(10)
                  .enabled(this.isConnected() && this.hasPeerTarget() && !this.tcpStatus.startsWith('CONNECTING'))
                  .onClick(() => this.probeSshPort())
              }
              .width('100%')
              Text($r('app.string.peer_result'))
                .width('100%')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_muted'))
              Text(this.peerStatus)
                .width('100%')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
              Text($r('app.string.tcp_result'))
                .width('100%')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_muted'))
              Text(this.tcpStatus)
                .width('100%')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')

            Divider()
              .color($r('app.color.border_soft'))

            Column({ space: 10 }) {
              Text($r('app.string.magicdns_title'))
                .width('100%')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              TextInput({ placeholder: $r('app.string.magicdns_placeholder'), text: this.magicDnsTarget })
                .width('100%')
                .height(46)
                .fontColor($r('app.color.text_primary'))
                .placeholderColor($r('app.color.text_muted'))
                .backgroundColor($r('app.color.surface_inset'))
                .border({ width: 1, color: $r('app.color.border_standard') })
                .borderRadius(10)
                .maxLength(253)
                .accessibilityText($r('app.string.magicdns_accessibility'))
                .onChange((value: string) => this.magicDnsTarget = value)
              Button(this.magicDnsStatus === 'RESOLVING' ? $r('app.string.action_resolving') : $r('app.string.action_resolve_magicdns'))
                .width('100%')
                .height(42)
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.control_secondary'))
                .borderRadius(10)
                .enabled(this.isConnected() && this.hasMagicDnsTarget() && this.magicDnsStatus !== 'RESOLVING')
                .onClick(() => this.probeMagicDns())
              Text($r('app.string.magicdns_result'))
                .width('100%')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_muted'))
              Text(this.magicDnsStatus)
                .width('100%')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
            }
            .width('100%')

            Divider()
              .color($r('app.color.border_soft'))

            Column({ space: 6 }) {
              Text($r('app.string.raw_status_title'))
                .width('100%')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text(this.diagnosticText())
                .width('100%')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .copyOption(CopyOptions.LocalDevice)
              Text($r('app.string.raw_status_copy_hint'))
                .width('100%')
                .fontSize(11)
                .fontColor($r('app.color.text_muted'))
            }
            .width('100%')
            .padding(12)
            .backgroundColor($r('app.color.surface_inset'))
            .borderRadius(10)
          }
        }
        .width('100%')
        .padding(20)
        .backgroundColor($r('app.color.surface_primary'))
        .border({ width: 1, color: $r('app.color.border_standard') })
        .borderRadius(16)

        Column({ space: 10 }) {
          Text($r('app.string.identity_title'))
            .width('100%')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.identity_logout_hint'))
            .width('100%')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Button($r('app.string.action_logout_forget'))
            .width('100%')
            .height(44)
            .fontSize(14)
            .fontColor($r('app.color.status_error'))
            .backgroundColor($r('app.color.error_surface'))
            .border({ width: 1, color: $r('app.color.status_error') })
            .borderRadius(10)
            .enabled(!this.isBusy())
            .onClick(() => this.confirmLogout())
        }
        .width('100%')
        .padding(20)
        .backgroundColor($r('app.color.surface_primary'))
        .border({ width: 1, color: $r('app.color.border_standard') })
        .borderRadius(16)
      }
      .width('100%')
      .constraintSize({ maxWidth: 680 })
      .padding({ left: 16, right: 16, top: 20, bottom: 36 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.canvas'))
  }
}
