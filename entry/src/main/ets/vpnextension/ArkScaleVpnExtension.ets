import { BusinessError } from '@kit.BasicServicesKit';
import { VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import bridge from 'libarkscale_bridge.so';

export default class ArkScaleVpnExtension extends VpnExtensionAbility {
  private connection?: vpnExtension.VpnConnection;

  onCreate(): void {
    this.startProbe();
  }

  onDestroy(): void {
    this.stopProbe();
  }

  private async startProbe(): Promise<void> {
    bridge.beginVpnProbe();
    try {
      this.connection = vpnExtension.createVpnConnection(this.context);
      await this.connection.protectProcessNet();
      bridge.markVpnProtected();

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
    } catch (error) {
      await this.destroyConnection();
      bridge.failVpnProbe((error as BusinessError).code ?? -1);
    }
  }

  private async stopProbe(): Promise<void> {
    const errorCode = await this.destroyConnection();
    if (errorCode === 0) {
      bridge.stopVpnProbe();
    } else {
      bridge.failVpnProbe(errorCode);
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
}
