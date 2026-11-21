# Theseus Keyboard — 全新项目

用户最新要求：使用 https://github.com/valzevul/Theseus/blob/master/assets/tabBar.gif 的玻璃底面，覆盖到系统键盘背景上；不取 Tab 按钮、文字、图标、选中滑块或拖动交互。

- 从零新建，不恢复或复用已删除的 KeyboardGlass 项目代码或素材。
- 上游原版：valzevul/Theseus，commit `71ca1c127a4e7fe3387361f160c4890dbd427f66`，Apache-2.0；保留 LICENSE / NOTICE。
- 本次玻璃来源为 `TheseusTabBar.backgroundGlassView`，不是选中滑块材质，不预先假设 `.clear` preset。
- 只加背景玻璃层，不改键帽、文字、候选点击、输入行为；按键必须在玻璃前面。
- 原版底面配置：blur 18，edgeWidth 0，interiorSharpness light 0.48 / dark 0.42，interiorAverage 80，dispersion 0，neutralBodyScale 1，outerGlow 0，edgeFeather 1/3，原版 chrome 曲线。
- 玻璃按键盘背景的实际 bounds / clipping 适配，不把底栏的高度或巨大胶囊形状强套给整个键盘。
- 使用原版 Swift / Metal 引擎，不用 GIF 截图、固定 PNG 或自绘相似图冒充。
- 保留系统背景作为采样底层及失败回退。只允许采样背景，不采样按键，也不能采样自身。
- 不承诺跨进程 UIKit layer capture 能取得其他 App 的真实合成画面。
- 本次用户明确授权「构建，我来测试」「只要64e」「用小号」：使用 Ning9527Repo 新建独立仓库，源码同步 main 核实后，仅触发一次 64e / RootHide 实验构建。未授权安装、注入、注销或上源。

状态：test1/test2 已完成构建并经用户真机确认无效；test2 日志确认 App-owned overlay 错在远程键盘合成层后面。test3 已将可见玻璃改为 InputUI 内 `UIKBBackdropView.contentView` 的 index 0，完成 ObjC 严格语法、状态边界和 Hook 幂等测试；本轮用户已授权构建，尚未构建或真机验证。

采样边界：本地 keyboard backdrop 的 `layer.render(in:)` 仍不保证取得 iOS17 原生 blur 的真实合成像素；失败时不清空原生背景。保留 App 端采样作为辅助，不再把 App-owned UIWindow 当作 InputUI 可见层。不用 PNG、自绘或材质近似冒充原版 Theseus。
