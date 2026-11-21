# Theseus Keyboard 0.1.0-test4 — RootHide arm64e host repair

全新项目。只取 Theseus 原版 iOS27 TabBar 中央玻璃配置与材质曲线，挂载在系统键盘背景实例；不取 Tab、选中镜片、图标、文字或交互，不改按键和输入逻辑。

上游：valzevul/Theseus commit `71ca1c127a4e7fe3387361f160c4890dbd427f66`（Apache-2.0，见 vendor/Theseus/LICENSE 与 NOTICE）。作者署名 Ning&Vadim Drobinin。

## 明确的实验边界

- test4 把可见 Theseus 层直接插入包含 `UIKBBackdropView` 的键盘宿主 `contentView` 最底层，按键前景保留；不再依赖固定 InputUI 进程名，并增加真实宿主识别、身份诊断和迟加载重试。
- App 窗口采样路径保留为辅助实验，但不再作为键盘宿主的可见玻璃层；原版 shader/material 仍保留。
- iOS17 键盘独立进程；本地 backdrop 是否能通过 `layer.render` 取得有效背景仍需真机确认，失败时保留系统背景。
- 本包为用户明确要求的真机测试，构建成功不等于玻璃外观验证通过。
- 保留原生 backdrop，不做 PNG/截图伪造，不悄悄替换为别的材质。当前组合不保证等价原版一次处理。
- 本版不启用常驻逐帧刷新；先测试背景挂载和实际外观。后方 App 连续动画不保证同步。
- 不更换按键，不新增设置页面或图标，不修改通知/桌面，不注入 backboardd。

## 测试

仅 `iphoneos-arm64e` / RootHide。没有自动 respring/重启/注销脚本。安装后需要目标键盘宿主进程重新加载插件；如未生效，由用户自行决定手动重启桌面或重开相关 App。本助手不会自动操作。

1. 在普通文本框打开系统键盘，检查下方背景是否出现 Theseus 材质；检查是否只剩平色。
2. 检查中英文切换、候选展开、横竖屏、深浅外观，重点确认按键可正常输入。
3. 若无变化、平色、闪退或发热，卸载此测试包并提供截图/崩溃报告；不宣称这些范围已经验证。

## 构建

GitHub Actions 仅 workflow_dispatch，macos-latest；`python3 tools/build.py` 编译真 arm64e Swift/ObjC 动态库与 Metal library、adhoc 签名、创建完整目录的 deb 并复核。无自动 push 构建和失败重试。
