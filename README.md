# mac-tools

个人 macOS 实用工具集。第一个成员：

## 性能监控悬浮工具（PerfBar）

macOS 桌面横向性能悬浮条，实时显示 CPU、内存、磁盘活动和网络上下行吞吐量。

![PerfBar 悬浮条](docs/screenshot.png)

### 功能

- CPU 总使用率
- 物理内存使用率（含已用 / 总量）
- 磁盘实时读 / 写速度
- 物理网卡实时下载、上传吞吐量
- CPU、内存、磁盘和网络的最近 60 秒真实趋势曲线
- macOS 风格深色毛玻璃面板
- 横向悬浮长条，始终置顶，支持跨多个桌面空间和全屏应用之上显示
- 拖动移动，自动记忆位置，下次启动回到原处
- 单击悬浮条展开 / 收起详情面板（内存用量、读写速率、活动网卡列表）
- 菜单栏托盘：显示 / 隐藏悬浮条、鼠标穿透开关、退出
- 本地运行，不采集、不上传任何数据

### 系统要求

- macOS 13.0 及以上
- Xcode 15+ 或 Command Line Tools（仅构建时需要）

### 构建与运行

```bash
git clone https://github.com/kahing7/mac-tools.git
cd mac-tools
./build.sh
open PerfBar.app
```

构建产物为 `PerfBar.app`（无 Dock 图标，常驻菜单栏）。建议在「系统设置 → 通用 → 登录项」中添加自启动。

### 项目结构

- `Sources/Metrics.swift`：CPU、内存、磁盘和网络采集逻辑
- `Sources/Sparkline.swift`：迷你趋势曲线控件
- `Sources/BarPanel.swift`：悬浮面板、毛玻璃主视图、详情展开与位置记忆
- `Sources/AppDelegate.swift`：应用入口与托盘菜单
- `Sources/main.swift`：程序启动
- `build.sh`：一键构建脚本（编译 + 打包 .app + ad-hoc 签名）

### 数据来源

- CPU：mach `host_processor_info`
- 内存：mach `host_statistics64`
- 磁盘：IOKit `IOBlockStorageDriver` 注册表统计
- 网络：`getifaddrs` 接口字节计数

默认排除回环（lo）、VPN（utun）、AWDL、桥接等虚拟接口，避免重复计算。

### 已知限制 / Roadmap

- [ ] 磁盘活动时间与队列长度
- [ ] CPU 每核心使用率展开视图
- [ ] 悬浮条尺寸缩放与记忆
- [ ] 趋势曲线悬停查看历史数值

### 许可证

[MIT](LICENSE)
