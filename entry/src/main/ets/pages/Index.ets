import bridge from 'libarkscale_bridge.so';

@Entry
@Component
struct Index {
  private goSmokePassed: boolean = bridge.runGoSmoke(1000);
  private lifecyclePassed: boolean = bridge.runGoLifecycle(100);
  @State private soakSeconds: number = 0;
  @State private soakStatus: string = 'STARTING';
  private soakStartedAt: number = 0;
  private soakTimer: number = -1;

  aboutToAppear(): void {
    if (!bridge.startGoSmoke()) {
      this.soakStatus = 'FAIL';
      return;
    }
    this.soakStatus = 'RUNNING';
    this.soakStartedAt = Date.now();
    this.soakTimer = setInterval(() => {
      this.soakSeconds = Math.floor((Date.now() - this.soakStartedAt) / 1000);
      if (this.soakSeconds >= 1800) {
        clearInterval(this.soakTimer);
        this.soakTimer = -1;
        const stopped = bridge.stopGoSmoke();
        const ticks = bridge.getGoSmokeTicks();
        this.soakStatus = stopped && ticks >= 17000 ? 'PASS' : `FAIL (${ticks} Go ticks)`;
      }
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.soakTimer !== -1) {
      clearInterval(this.soakTimer);
      this.soakTimer = -1;
      if (!bridge.stopGoSmoke()) {
        this.soakStatus = 'FAIL';
      }
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('ArkScale')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
      Text(bridge.getVersion())
        .fontSize(16)
        .fontColor($r('app.color.secondary_text'))
      Text('P0/P1 validation build')
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
      Text(this.goSmokePassed ? 'Go smoke: PASS' : 'Go smoke: FAIL')
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
      Text(this.lifecyclePassed ? '100 start/stop cycles: PASS' : '100 start/stop cycles: FAIL')
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
      Text(`30 min soak: ${this.soakStatus} (${Math.floor(this.soakSeconds / 60)}m ${this.soakSeconds % 60}s)`)
        .fontSize(14)
        .fontColor($r('app.color.secondary_text'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
