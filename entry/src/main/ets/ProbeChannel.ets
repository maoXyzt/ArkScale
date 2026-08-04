import bridge from 'libarkscale_bridge.so';

export const COMMAND_KEY = 0;
export const STATUS_KEY = 1;
export const NETWORK_KEY = 2;
export const ENGINE_KEY = 3;

export class ProbeChannel {
  private watchedKeys: Array<number>;
  private watching: boolean = false;
  private latestData: Map<number, string> = new Map();

  constructor(directory: string, watchedKeys: Array<number>) {
    if (!bridge.initProbeChannel(directory)) {
      throw new Error('Unable to initialize probe channel');
    }
    this.watchedKeys = watchedKeys;
  }

  publish(key: number, data: string): Promise<void> {
    // ponytail: slots keep only the latest value; add a queue if sub-250 ms command bursts become real input.
    return bridge.writeProbeChannel(key, data) ? Promise.resolve() : Promise.reject(new Error('Probe channel write failed'));
  }

  read(key: number): string | undefined {
    return this.latestData.get(key);
  }

  start(callback: Callback<number>): void {
    if (this.watching) {
      return;
    }
    let mask = 0;
    this.watchedKeys.forEach((key: number): void => {
      mask |= 1 << key;
    });
    this.watching = bridge.startProbeChannelWatch(mask, (key: number, value: string): void => {
      this.receive(key, value, callback);
    });
    if (!this.watching) {
      throw new Error('Unable to watch probe channel');
    }
  }

  stop(): void {
    if (this.watching) {
      bridge.stopProbeChannelWatch();
      this.watching = false;
    }
  }

  private receive(key: number, value: string, callback: Callback<number>): void {
    this.latestData.set(key, value);
    callback(key);
  }
}
