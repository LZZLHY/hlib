# HLib 沉浸光感适配方案

> 基于 HarmonyOS 6.x (API 23+) 沉浸光感 (Immersive Material) 与悬浮导航能力，
> 对鸿蒙书馆 (HLib) 项目进行视觉质感升级。

---

## 一、技术背景

### 1.1 什么是沉浸光感

沉浸光感不是简单的"毛玻璃"，而是 HarmonyOS 系统级的光影材质计算引擎。
它通过模拟物理世界的光线折射与漫反射，使 UI 组件呈现真实的"悬浮感"与"层级感"。

### 1.2 核心 API 清单

| API | 作用 | 适用场景 |
|-----|------|----------|
| `backgroundBlurStyle(BlurStyle.*)` | 背景模糊（毛玻璃） | TabBar、顶部导航、对话框 |
| `backgroundBrightness({ rate, lightUpDegree })` | 亮度调节，增强通透感 | 搭配模糊使用 |
| `backgroundMaterial(MaterialStyle.*)` | HDS 材质效果（API 23+） | 自定义组件 |
| `expandSafeArea([SafeAreaType.SYSTEM], [...])` | 延伸到系统安全区 | 底部栏沉浸 |
| `setWindowLayoutFullScreen(true)` | 窗口全屏布局 | Ability 全局前置 |
| `setWindowSystemBarProperties(...)` | 状态栏/导航栏透明 | Ability 全局前置 |
| `barOverlap(true)` | TabBar 与内容层叠 | 底部Tab悬浮 |
| `BlurStyle` 枚举 | `Thin` / `Regular` / `Thick` / `BACKGROUND_THIN` 等 | 按层级选用 |

### 1.3 项目兼容性

- **当前 SDK**: `targetSdkVersion: 6.1.0(23)` ✅ 完全兼容
- **无需三方依赖**: 所有 API 均为系统内置

---

## 二、适配清单

### ⭐ 优先级说明

- **P0** — 视觉提升最大、改动最小，建议首批实施
- **P1** — 需要一定布局重构，效果显著
- **P2** — 锦上添花，可后续迭代

---

### 2.1 [P0] 底部 TabBar 毛玻璃悬浮

**当前状态**: 实色 `bgCanvas` 背景的固定 TabBar  
**目标效果**: 半透明毛玻璃底栏，内容可从底部透出

**改动位置**: `MainPage.ets`

**实现方案**:

```typescript
// 1. Tabs 组件开启内容与 TabBar 重叠
Tabs({ barPosition: BarPosition.End, ... })
  .barOverlap(true)                    // 内容延伸到 TabBar 下方
  .barBackgroundBlurStyle(BlurStyle.Thin) // TabBar 毛玻璃
  .barBackgroundColor(Color.Transparent)  // 背景透明
  // ...

// 2. bottomTab Builder 中移除实色背景
@Builder
private bottomTab(...) {
  Column({ space: 2 }) { ... }
    .height(64)
    .justifyContent(FlexAlign.Center)
    // 不再设置 backgroundColor
}
```

**关键补充**: 各 Tab 内容页 (HomeTab / SearchTab / FavoritesTab / DownloadsTab) 底部需要增加安全区占位：

```typescript
// 在每个 Tab 的 List / Scroll 末尾追加底部留白
ListItem().height(80)  // 已有的保留，确保不被 TabBar 遮挡
```

同时需要在内容容器上添加：

```typescript
.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
```

---

### 2.2 [P0] 窗口级沉浸式配置

**当前状态**: 未配置全屏布局，状态栏/导航栏为默认实色  
**目标效果**: 内容延伸至状态栏下方，状态栏透明

**改动位置**: `EntryAbility.ets` → `onWindowStageCreate`

```typescript
async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
  const mainWindow: window.Window = await windowStage.getMainWindow();

  try {
    await mainWindow.setWindowLayoutFullScreen(true);
    const sysBarProps: window.SystemBarProperties = {
      statusBarColor: '#00000000',
      statusBarContentColor: '#FF000000',
      navigationBarColor: '#00000000',
      navigationBarContentColor: '#FF000000',
    };
    await mainWindow.setWindowSystemBarProperties(sysBarProps);
  } catch (e) {
    Logger.w(TAG, `setWindowProperties failed: ${(e as Error).message}`);
  }

  windowStage.loadContent('pages/RootPage', ...);
}
```

**注意**: 启用全屏布局后，所有页面顶部需要用 `expandSafeArea` 或手动获取状态栏高度做避让。

---

### 2.3 [P0] 首页搜索框毛玻璃卡片

**当前状态**: `surfaceAlt` 实色圆角矩形  
**目标效果**: 磨砂质感搜索入口

**改动位置**: `HomeTab.ets` → `searchEntry()` Builder

```typescript
@Builder
private searchEntry() {
  Row({ space: 8 }) { ... }
    .backgroundColor(Color.Transparent)
    .backgroundBlurStyle(BlurStyle.Thin, {
      colorMode: ThemeColorMode.SYSTEM,
      adaptiveColor: AdaptiveColor.DEFAULT,
      scale: 0.9
    })
    .backgroundBrightness({ rate: 0.5, lightUpDegree: 0.4 })
    .borderRadius(AppRadius.pill)
    // 移除原有 .backgroundColor(AppColors.surface)
}
```

---

### 2.4 [P1] 书籍详情页顶部栏毛玻璃

**当前状态**: 无背景的 `Row` + padding  
**目标效果**: 滚动时顶栏浮起毛玻璃效果（类似原生"动态导航栏"）

**改动位置**: `BookDetailPage.ets` → `topBar()` Builder

**实现方案**: 使用 `Stack` 分层 — 顶栏固定在最上层，内容 `Scroll` 在下层。
当 `scrollOffset > 0` 时，顶栏加入毛玻璃：

```typescript
@Builder
private topBar() {
  Row({ space: 8 }) { ... }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 8 })
    .backgroundColor(Color.Transparent)
    .backgroundBlurStyle(
      this.scrollOffset > 10 ? BlurStyle.Regular : BlurStyle.NONE
    )
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
}
```

同理适用于:
- `SettingsPage.ets` → `topBar()`
- `SimilarBooksPage.ets` → `topBar()`
- `ErrorLogPage.ets` → `topBar()`
- `HistoryPage.ets` → 顶部 Row

---

### 2.5 [P1] 阅读器顶栏毛玻璃

**当前状态**: `brandPrimary` 实色顶栏  
**目标效果**: 半透明品牌色 + 模糊叠加

**改动位置**: `ReaderPage.ets` → `topBar()` Builder

```typescript
@Builder
private topBar() {
  Row({ space: 8 }) { ... }
    .backgroundColor('#CC0E7C7B')          // 品牌色 80% 不透明
    .backgroundBlurStyle(BlurStyle.Thin)    // 叠加模糊
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
}
```

---

### 2.6 [P1] 对话框 / 弹窗毛玻璃背景

**当前状态**: `surface` 实色卡片  
**目标效果**: 半透明磨砂弹窗

**适用组件**:
- `FilterDialog.ets`（搜索筛选弹窗）
- `DomainSelectorDialog.ets`（域名选择弹窗）

```typescript
// FilterDialog.build()
Column() { ... }
  .backgroundColor(Color.Transparent)
  .backgroundBlurStyle(BlurStyle.Thick, {
    colorMode: ThemeColorMode.SYSTEM,
    adaptiveColor: AdaptiveColor.DEFAULT,
  })
  .backgroundBrightness({ rate: 0.5, lightUpDegree: 0.5 })
  .borderRadius(AppRadius.lg)
```

---

### 2.7 [P1] 设置页圆角按钮毛玻璃

**当前状态**: `surfaceAlt` 实色圆形按钮  
**目标效果**: 按钮背景毛玻璃化

**适用组件**: 所有 `Button({ type: ButtonType.Circle })` 的返回、设置、刷新按钮

```typescript
Button({ type: ButtonType.Circle, stateEffect: true }) {
  Image($r('app.media.ic_back')).width(22).height(22);
}
  .width(40)
  .height(40)
  .backgroundColor(Color.Transparent)
  .backgroundBlurStyle(BlurStyle.Thin)
```

> 💡 此项涉及文件较多 (MainPage / HomeTab / FavoritesTab / BookDetailPage / SettingsPage / ReaderPage / SimilarBooksPage / ErrorLogPage / HistoryPage)，建议统一抽取为 `BlurCircleButton` 组件。

---

### 2.8 [P2] 下载管理页 Tab 切换器

**当前状态**: `DownloadsTab.ets` 内部 `Tabs` 使用默认样式  
**目标效果**: 悬浮式分段选择器

**方案**: 给内部 Tabs 添加毛玻璃效果，但优先级较低。

---

### 2.9 [P2] 书籍卡片悬浮阴影

**当前状态**: `surface` 实色 + `borderRadius`  
**目标效果**: 卡片微阴影 + 极轻模糊

> ⚠️ **性能警告**: 列表项上使用材质效果会严重影响滚动性能，
> 仅建议在首页横向推荐行 (固定数量较少) 中使用，**禁止在垂直长列表每个 Item 上使用**。

---

## 三、实施步骤（建议顺序）

| 步骤 | 内容 | 涉及文件 | 预估工量 |
|------|------|----------|----------|
| 1 | EntryAbility 窗口全屏 + 状态栏透明 | `EntryAbility.ets` | 小 |
| 2 | 底部 TabBar 毛玻璃 + barOverlap | `MainPage.ets` | 小 |
| 3 | 各 Tab 内容页 expandSafeArea 适配 | `HomeTab` / `SearchTab` / `FavoritesTab` / `DownloadsTab` | 中 |
| 4 | 首页搜索框毛玻璃 | `HomeTab.ets` | 小 |
| 5 | 详情页 / 设置页顶栏毛玻璃 | `BookDetailPage` / `SettingsPage` / `SimilarBooksPage` / `ErrorLogPage` / `HistoryPage` | 中 |
| 6 | 阅读器顶栏半透明品牌色 | `ReaderPage.ets` | 小 |
| 7 | 弹窗毛玻璃 | `FilterDialog` / `DomainSelectorDialog` | 小 |
| 8 | 圆形按钮统一毛玻璃 | 全局（建议抽组件） | 中 |

---

## 四、性能与兼容性注意事项

### 4.1 性能红线

- **禁止在 `ForEach` 列表 Item 上逐个添加 `backgroundBlurStyle`** → 滚动严重卡顿
- 材质效果依赖 GPU 实时模糊计算，仅用于**固定/少量/悬浮**的 UI 层
- 同一页面建议**不超过 3 个模糊层**

### 4.2 深色模式适配

- `BlurStyle` 系统会自动适配深色模式
- 搭配 `colorMode: ThemeColorMode.SYSTEM` 可跟随系统主题
- `adaptiveColor: AdaptiveColor.DEFAULT` 让模糊颜色自动匹配背景

### 4.3 版本降级策略

当前项目 `compatibleSdkVersion: 6.1.0(23)` 确保所有目标设备均支持，
**无需额外降级逻辑**。若未来降低最低兼容版本，需用 `canIUse` 检测：

```typescript
if (canIUse('SystemCapability.ArkUI.ArkUI.Full')) {
  // 使用 backgroundBlurStyle
} else {
  // 回退为实色背景
}
```

### 4.4 expandSafeArea 注意

启用 `setWindowLayoutFullScreen(true)` 后：
- 顶部内容会被状态栏遮挡 → 需 `expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])` 或手动 padding
- 底部列表被导航条遮挡 → 需 `expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])`
- 安全区设置需沿整个嵌套路径传递（Tabs → TabContent → 内容组件）

---

## 五、预期效果对比

| 区域 | 改前 | 改后 |
|------|------|------|
| 底部 TabBar | 实色白底，硬边界 | 毛玻璃悬浮，内容透出 |
| 状态栏 | 默认不透明 | 透明融入页面 |
| 首页搜索框 | `surface` 灰色实底 | 磨砂半透明卡片 |
| 详情页顶栏 | 无背景/实色 | 滚动触发毛玻璃 |
| 阅读器顶栏 | `brandPrimary` 实色 | 品牌色半透明 + 模糊 |
| 弹窗 | `surface` 实色卡片 | 磨砂质感弹窗 |
| 圆形按钮 | `surfaceAlt` 灰底 | 轻薄毛玻璃 |

---

## 六、参考资料

1. [悬浮页签开发指南（华为官方）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-tabs-bar-floating)
2. [沉浸光感开发指南（华为官方）](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ui-design-hds-component-material)
3. [HDS 深度实战：悬浮页签与沉浸光感 (API 23+)](https://harmonyosdev.csdn.net/69e6e5c054b52172bc6b2442.html)
4. [背景模糊效果的自定义 TabBar 实现案例](https://blog.csdn.net/m0_73088370/article/details/145159944)
5. [ArkTS 背景设置 API 文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-background)
