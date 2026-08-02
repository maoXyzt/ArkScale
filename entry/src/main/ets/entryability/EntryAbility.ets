import { UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want): void {}

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (error) => {
      if (error.code) {
        console.error(`Failed to load ArkScale UI: ${error.code}`);
        return;
      }

      windowStage.getMainWindow((windowError, mainWindow) => {
        if (windowError.code) {
          console.error(`Failed to get ArkScale main window: ${windowError.code}`);
          return;
        }
        mainWindow.setWindowKeepScreenOn(true, (screenError) => {
          if (screenError.code) {
            console.error(`Failed to keep ArkScale screen on: ${screenError.code}`);
          }
        });
      });
    });
  }
}
