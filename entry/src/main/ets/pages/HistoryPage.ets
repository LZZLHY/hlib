/*
 * HistoryPage.ets — 下载历史（P1.5 Navigation 占位；P4 完整实现）
 */

import { AppColors } from '../theme/AppColors';
import { AppFontSize } from '../theme/AppTextStyles';
import { AppRouter } from '../utils/AppRouter';

@Component
export struct HistoryPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  build() {
    NavDestination() {
      Column({ space: 16 }) {
        Blank().height(this.statusBarHeight)
        Row() {
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.ic_back')).width(22).height(22);
          }
          .width(40)
          .height(40)
          .backgroundColor(AppColors.surfaceAlt)
          .onClick(() => AppRouter.pop());

          Blank().layoutWeight(1);
        }
        .width('100%')
        .padding({ top: 12, left: 12, right: 12 });

        Text($r('app.string.settings_history'))
          .fontSize(AppFontSize.headline)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppColors.textPrimary);

        Text('HistoryPage · P4 待实现')
          .fontSize(AppFontSize.body)
          .fontColor(AppColors.textSecondary);
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .backgroundColor(AppColors.bgCanvas);
    }
    .hideTitleBar(true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }
}
