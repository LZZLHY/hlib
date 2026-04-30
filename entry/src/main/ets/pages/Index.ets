/*
 * Index.ets — 已废弃，不再列入 main_pages.json。
 * 保留文件仅为兼容 cpp/libentry.so 的示例引用；真正入口在 SplashPage.ets。
 */

@Component
struct Index {
  build() {
    Column() {
      Text('Index 已迁移至 SplashPage')
        .fontSize($r('app.float.fs_body'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}

