import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { connection, VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import bridge from 'libarkscale_bridge.so';

const VPN_PROBE_EVENT = 'com.arkscale.client.VPN_PROBE_STATUS';
const VPN_PROBE_COMMAND_EVENT = 'com.arkscale.client.VPN_PROBE_COMMAND';

export default class ArkScaleVpnExtension extends VpnExtensionAbility {
  private connection?: vpnExtension.VpnConnection;
  private commandSubscriber?: commonEventManager.CommonEventSubscriber;
  private networkMonitor?: connection.NetConnection;
  private networkMonitoring: boolean = false;
  private networkBearer: string = 'UNKNOWN';
  private networkSwitches: number = 0;
  private stopping: boolean = false;
  private stopCompleted: boolean = false;

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
      const subscriber = await commonEventManager.createSubscriber({ events: [VPN_PROBE_COMMAND_EVENT] });
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
          }
        });
      this.publishStatus('ON_CREATE');
      await this.startProbe();
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

      const tunFd = await this.connection.create({
        addresses: [{
          address: { address: '192.0.2.1', family: 1 },
          prefixLength: 32
        }],
        routes: [{
          interface: 'vpn-tun',
          destination: {
            address: { address: '192.0.2.2', family: 1 },
            prefixLength: 32
          },
          gateway: { address: '0.0.0.0', family: 1 },
          hasGateway: false,
          isDefaultRoute: false
        }],
        mtu: 1280,
        isIPv4Accepted: true,
        isIPv6Accepted: false,
        isBlocking: false
      });
      if (!bridge.attachVpnTun(tunFd)) {
        throw new Error('Unable to duplicate TUN file descriptor');
      }
      this.publishStatus('READY');
    } catch (error) {
      await this.destroyConnection();
      const errorCode = (error as BusinessError).code ?? -1;
      bridge.failVpnProbe(errorCode);
      this.publishStatus(`FAIL code=${errorCode}`);
    }
  }

  private async stopProbe(): Promise<void> {
    this.stopNetworkProbe();
    const errorCode = await this.destroyConnection();
    if (errorCode === 0) {
      bridge.stopVpnProbe();
      this.stopCompleted = true;
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

  private publishStatus(status: string): void {
    commonEventManager.publish(VPN_PROBE_EVENT, {
      data: `${status}|${bridge.getCurrentPid()}|${bridge.getVpnProbeStatus()}`
    }, (error: BusinessError) => {
      if (error?.code) {
        console.error(`VPN probe event publish failed: ${error.code}`);
      }
    });
  }
}
