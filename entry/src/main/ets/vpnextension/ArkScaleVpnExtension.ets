import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { connection, VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import bridge from 'libarkscale_bridge.so';

const VPN_PROBE_EVENT = 'com.arkscale.client.VPN_PROBE_STATUS';
const VPN_PROBE_COMMAND_EVENT = 'com.arkscale.client.VPN_PROBE_COMMAND';
const ENGINE_EVENT = 'com.arkscale.client.ENGINE_EVENT';
const BUNDLE_NAME = 'com.arkscale.client';

interface EnginePrefix {
  ip: string;
  prefixLength: number;
  family: number;
}

interface EngineEvent {
  schemaVersion: number;
  type: string;
  state?: string;
  url?: string;
  severity?: string;
  message?: string;
  generation?: number;
  localAddrs?: Array<EnginePrefix>;
  routes?: Array<EnginePrefix>;
  localRoutes?: Array<EnginePrefix>;
  nameservers?: Array<string>;
  searchDomains?: Array<string>;
  mtu?: number;
}

export default class ArkScaleVpnExtension extends VpnExtensionAbility {
  private connection?: vpnExtension.VpnConnection;
  private commandSubscriber?: commonEventManager.CommonEventSubscriber;
  private networkMonitor?: connection.NetConnection;
  private networkMonitoring: boolean = false;
  private networkBearer: string = 'UNKNOWN';
  private networkSwitches: number = 0;
  private stopping: boolean = false;
  private stopCompleted: boolean = false;
  private engineStarted: boolean = false;
  private tunActive: boolean = false;
  private appliedGeneration: number = 0;
  private startWork: Promise<void> = Promise.resolve();
  private configWork: Promise<void> = Promise.resolve();
  private pendingConfig?: EngineEvent;
  private configApplying: boolean = false;
  private lastStatus: string = 'ON_CREATE';
  private lastNetworkStatus?: string;
  private lastEngineEvent?: string;

  onCreate(): void {
    this.initializeProbe();
  }

  onDestroy(): void {
    if (this.commandSubscriber !== undefined) {
      commonEventManager.unsubscribe(this.commandSubscriber);
      this.commandSubscriber = undefined;
    }
    if (!this.stopCompleted && !this.stopping) {
      this.stopping = true;
      this.publishStatus('ON_DESTROY');
      this.stopProbe();
    }
  }

  private async initializeProbe(): Promise<void> {
    try {
      const subscriber = await commonEventManager.createSubscriber({
        events: [VPN_PROBE_COMMAND_EVENT],
        publisherBundleName: BUNDLE_NAME
      });
      this.commandSubscriber = subscriber;
      commonEventManager.subscribe(subscriber,
        (error: BusinessError, data: commonEventManager.CommonEventData) => {
          if (error?.code) {
            this.publishStatus(`COMMAND ERROR code=${error.code}`);
            return;
          }
          if (data.data === 'STOP' && !this.stopping) {
            this.stopping = true;
            this.stopProbe();
          } else if (data.data === 'STATUS') {
            this.publishSnapshot();
          }
        });
      this.publishStatus('ON_CREATE');
      this.startWork = this.startProbe();
      await this.startWork;
    } catch (error) {
      const errorCode = (error as BusinessError).code ?? -1;
      bridge.failVpnProbe(errorCode);
      this.publishStatus(`COMMAND SUBSCRIBE FAIL code=${errorCode}`);
    }
  }

  private async startProbe(): Promise<void> {
    bridge.beginVpnProbe();
    this.publishStatus('PROTECTING');
    try {
      this.connection = vpnExtension.createVpnConnection(this.context);
      await this.connection.protectProcessNet();
      bridge.markVpnProtected();
      this.publishStatus('PROTECTED');
      this.startNetworkProbe();
      await bridge.startEngine(JSON.stringify({ schemaVersion: 1, stateDir: this.context.filesDir }),
        (eventJson: string) => this.handleEngineEvent(eventJson));
      this.engineStarted = true;
      this.publishStatus('BACKEND READY');
    } catch (error) {
      if (this.engineStarted) {
        try {
          await bridge.stopEngine();
        } catch (stopError) {
          console.error(`Backend cleanup failed: ${(stopError as BusinessError).code ?? -1}`);
        }
        this.engineStarted = false;
      }
      await this.destroyConnection();
      const errorCode = (error as BusinessError).code ?? -1;
      bridge.failVpnProbe(errorCode);
      this.publishStatus(`FAIL code=${errorCode}`);
    }
  }

  private async stopProbe(): Promise<void> {
    this.stopNetworkProbe();
    await this.startWork;
    await this.configWork;
    this.pendingConfig = undefined;
    let engineErrorCode = 0;
    if (this.engineStarted) {
      try {
        await bridge.stopEngine();
      } catch (error) {
        engineErrorCode = (error as BusinessError).code ?? -1;
      }
      this.engineStarted = false;
    }
    const destroyErrorCode = await this.destroyConnection();
    this.tunActive = false;
    const errorCode = engineErrorCode !== 0 ? engineErrorCode : destroyErrorCode;
    if (errorCode === 0) {
      bridge.stopVpnProbe();
      this.stopCompleted = true;
      this.publishEngineEvent(JSON.stringify({ schemaVersion: 1, type: 'state', state: 'stopped' }));
      this.publishStatus('STOPPED');
    } else {
      bridge.failVpnProbe(errorCode);
      this.stopping = false;
      this.publishStatus(`STOP FAIL code=${errorCode}`);
    }
  }

  private startNetworkProbe(): void {
    try {
      const defaultNet = connection.getDefaultNetSync();
      this.networkBearer = this.physicalBearer(connection.getNetCapabilitiesSync(defaultNet).bearerTypes);
      this.networkMonitor = connection.createNetConnection();
      this.networkMonitoring = true;
      this.networkMonitor.on('netCapabilitiesChange', (info: connection.NetCapabilityInfo) => {
        if (!this.networkMonitoring) {
          return;
        }
        bridge.networkChanged();
        const nextBearer = this.physicalBearer(info.netCap.bearerTypes);
        if (nextBearer === 'UNKNOWN' || nextBearer === this.networkBearer) {
          return;
        }
        if (this.networkBearer === 'UNKNOWN') {
          this.networkBearer = nextBearer;
          this.publishStatus(`NETWORK READY bearer=${nextBearer} netId=${info.netHandle.netId} switches=0`);
          return;
        }
        const previousBearer = this.networkBearer;
        this.networkBearer = nextBearer;
        this.networkSwitches++;
        this.publishStatus(`NETWORK SWITCH PASS ${previousBearer}->${nextBearer} netId=${info.netHandle.netId} switches=${this.networkSwitches}`);
      });
      this.networkMonitor.register((error: BusinessError) => {
        if (error?.code) {
          this.networkMonitoring = false;
          this.publishStatus(`NETWORK FAIL code=${error.code}`);
          return;
        }
        this.publishStatus(`NETWORK READY bearer=${this.networkBearer} netId=${defaultNet.netId} switches=0`);
      });
    } catch (error) {
      this.networkMonitoring = false;
      this.publishStatus(`NETWORK FAIL code=${(error as BusinessError).code ?? -1}`);
    }
  }

  private stopNetworkProbe(): void {
    this.networkMonitoring = false;
    const monitor = this.networkMonitor;
    this.networkMonitor = undefined;
    if (monitor !== undefined) {
      try {
        monitor.unregister((error: BusinessError) => {
          if (error?.code) {
            console.error(`Network monitor unregister failed: ${error.code}`);
          }
        });
      } catch (error) {
        console.error(`Network monitor unregister failed: ${(error as BusinessError).code ?? -1}`);
      }
    }
  }

  private physicalBearer(bearerTypes: Array<connection.NetBearType>): string {
    return bearerTypes.includes(connection.NetBearType.BEARER_WIFI) ? 'WIFI' :
      bearerTypes.includes(connection.NetBearType.BEARER_CELLULAR) ? 'CELLULAR' : 'UNKNOWN';
  }

  private async destroyConnection(): Promise<number> {
    if (this.connection !== undefined) {
      const connection = this.connection;
      this.connection = undefined;
      try {
        await connection.destroy();
      } catch (error) {
        return (error as BusinessError).code ?? -1;
      }
    }
    return 0;
  }

  private handleEngineEvent(eventJson: string): void {
    if (this.stopping) {
      return;
    }
    try {
      const event = JSON.parse(eventJson) as EngineEvent;
      if (event.schemaVersion !== 1) {
        throw new Error('Unsupported engine event schema');
      }
      if (event.type === 'vpn-config') {
        if (this.pendingConfig === undefined || (event.generation ?? 0) > (this.pendingConfig.generation ?? 0)) {
          this.pendingConfig = event;
        }
        if (!this.configApplying) {
          this.configApplying = true;
          this.configWork = this.applyPendingConfigs();
        }
      } else if (event.type === 'login-url') {
        if (event.url === undefined || !event.url.startsWith('https://login.tailscale.com/') || event.url.length > 2048) {
          throw new Error('Invalid Tailscale login URL');
        }
        this.publishEngineEvent(eventJson);
      } else if (event.type === 'state' || event.type === 'health') {
        this.publishEngineEvent(eventJson);
      }
    } catch (error) {
      bridge.failVpnProbe(-1);
      this.publishStatus(`ENGINE EVENT FAIL ${(error as Error).message}`);
    }
  }

  private async applyPendingConfigs(): Promise<void> {
    while (!this.stopping && this.pendingConfig !== undefined) {
      const event = this.pendingConfig;
      this.pendingConfig = undefined;
      try {
        await this.applyVpnConfig(event);
      } catch (error) {
        bridge.failVpnProbe(-1);
        this.publishStatus(`CONFIG FAIL ${(error as Error).message}`);
      }
    }
    this.configApplying = false;
  }

  private async applyVpnConfig(event: EngineEvent): Promise<void> {
    const generation = event.generation;
    const localAddrs = event.localAddrs;
    const routes = event.routes;
    const nameservers = event.nameservers;
    const searchDomains = event.searchDomains;
    const mtu = event.mtu;
    if (generation === undefined || generation <= this.appliedGeneration || generation % 1 !== 0) {
      return;
    }
    if (localAddrs === undefined || localAddrs.length === 0 || !localAddrs.every((prefix: EnginePrefix) =>
      this.validPrefix(prefix))) {
      throw new Error('Invalid local addresses');
    }
    if (routes === undefined || routes.length === 0 || routes.length > 1024 || !routes.every((prefix: EnginePrefix) =>
      this.validPrefix(prefix))) {
      throw new Error('Invalid routes');
    }
    if (nameservers === undefined || nameservers.some((address: string) => address.length === 0) ||
      searchDomains === undefined || searchDomains.some((domain: string) => domain.length === 0) ||
      mtu === undefined || mtu < 1280 || mtu > 9000) {
      throw new Error('Invalid DNS or MTU');
    }

    const config: vpnExtension.VpnConfig = {
      addresses: localAddrs.map((address: EnginePrefix): connection.LinkAddress => ({
        address: { address: address.ip, family: address.family },
        prefixLength: address.prefixLength
      })),
      routes: routes.map((route: EnginePrefix): connection.RouteInfo => ({
        interface: 'vpn-tun',
        destination: {
          address: { address: route.ip, family: route.family },
          prefixLength: route.prefixLength
        },
        gateway: { address: route.family === 1 ? '0.0.0.0' : '::', family: route.family },
        hasGateway: false,
        isDefaultRoute: route.prefixLength === 0
      })),
      dnsAddresses: nameservers,
      searchDomains: searchDomains,
      mtu: mtu,
      isIPv4Accepted: localAddrs.some((address: EnginePrefix) => address.family === 1),
      isIPv6Accepted: localAddrs.some((address: EnginePrefix) => address.family === 2),
      isBlocking: false
    };

    if (this.tunActive) {
      if (!bridge.suspendVpnTun()) {
        throw new Error('Unable to suspend old TUN');
      }
      const destroyError = await this.destroyConnection();
      this.tunActive = false;
      if (destroyError !== 0) {
        throw new Error(`Unable to destroy old TUN: ${destroyError}`);
      }
    }
    if (this.connection === undefined) {
      this.connection = vpnExtension.createVpnConnection(this.context);
    }
    let tunFd: number;
    try {
      tunFd = await this.connection.create(config);
    } catch (error) {
      throw new Error(`Unable to create TUN: ${(error as BusinessError).code ?? -1}`);
    }
    if (!bridge.attachVpnTun(tunFd)) {
      await this.destroyConnection();
      throw new Error('Unable to attach new TUN');
    }
    this.tunActive = true;
    this.appliedGeneration = generation;
    this.publishStatus(`READY configGen=${generation}`);
  }

  private validPrefix(prefix: EnginePrefix): boolean {
    return prefix.ip.length > 0 && (prefix.family === 1 || prefix.family === 2) &&
      prefix.prefixLength >= 0 && prefix.prefixLength <= (prefix.family === 1 ? 32 : 128);
  }

  private publishEngineEvent(eventJson: string): void {
    this.lastEngineEvent = eventJson;
    commonEventManager.publish(ENGINE_EVENT, { bundleName: BUNDLE_NAME, data: eventJson }, (error: BusinessError) => {
      if (error?.code) {
        console.error(`Engine event publish failed: ${error.code}`);
      }
    });
  }

  private publishStatus(status: string): void {
    if (status.startsWith('NETWORK ')) {
      this.lastNetworkStatus = status;
    } else {
      this.lastStatus = status;
    }
    commonEventManager.publish(VPN_PROBE_EVENT, {
      bundleName: BUNDLE_NAME,
      data: `${status}|${bridge.getCurrentPid()}|${bridge.getVpnProbeStatus()}`
    }, (error: BusinessError) => {
      if (error?.code) {
        console.error(`VPN probe event publish failed: ${error.code}`);
      }
    });
  }

  private publishSnapshot(): void {
    this.publishStatus(this.lastStatus);
    if (this.lastNetworkStatus !== undefined) {
      this.publishStatus(this.lastNetworkStatus);
    }
    if (this.lastEngineEvent !== undefined) {
      this.publishEngineEvent(this.lastEngineEvent);
    }
  }
}
