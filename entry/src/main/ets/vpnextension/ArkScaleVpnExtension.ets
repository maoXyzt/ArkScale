import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import bridge from 'libarkscale_bridge.so';

const VPN_PROBE_EVENT = 'com.arkscale.client.VPN_PROBE_STATUS';

export default class ArkScaleVpnExtension extends VpnExtensionAbility {
  private connection?: vpnExtension.VpnConnection;

  onCreate(): void {
    this.publishStatus('ON_CREATE');
    this.startProbe();
  }

  onDestroy(): void {
    this.publishStatus('ON_DESTROY');
    this.stopProbe();
  }

  private async startProbe(): Promise<void> {
    bridge.beginVpnProbe();
    this.publishStatus('PROTECTING');
    try {
      this.connection = vpnExtension.createVpnConnection(this.context);
      await this.connection.protectProcessNet();
      bridge.markVpnProtected();
      this.publishStatus('PROTECTED');

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
    const errorCode = await this.destroyConnection();
    if (errorCode === 0) {
      bridge.stopVpnProbe();
      this.publishStatus('STOPPED');
    } else {
      bridge.failVpnProbe(errorCode);
      this.publishStatus(`STOP FAIL code=${errorCode}`);
    }
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
