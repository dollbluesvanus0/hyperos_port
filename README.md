<div align="center">

# HyperOS 移植项目

简体中文&nbsp;&nbsp;|&nbsp;&nbsp;[English](/README_en-US.md) 

</div>

## 简介
- HyperOS 一键自动移植打包
- 支持A-only和AB机型

## 测试机型及版本
- 测试机型小米10/Pro/Ultra, 小米10S HyperOS最新版
- 测试版本 小米12、小米13/Pro/Ultra、小米14/Pro HyperOS1.0 正式版和开发版 官方OTA包 & xiaomi.eu官改包
- 测试版本 小米平板5 Pro 12.4（DAGU）


## 正常工作
- 人脸
- 挖孔
- 指纹
- 相机
- NFC
- 自动亮度
- 通话息屏
- 应用双开
- 护眼模式
- 带壳截屏


## BUG

- 等你发现

## 说明
- 以上CN ROM均基于小米正式版官方HyperOS(A13)底包
- 欧版基于最新xiaomi.eu官方的最新HyperOS底包

## 平板系统
移植平板HyperOS到手机，需要从其他正常手机HyperOS机型复制下面的软件
Contacts MIUIAod MiuiHome MIUISecurityCenter  Mms  MIUIContentExtension  MIUIPackageInstaller


## 如何使用
- 在WSL、ubuntu、deepin等Linux下
```shell
    sudo apt update
    sudo apt upgrade
    sudo apt install git -y
    # 克隆项目
    git clone https://github.com/toraidl/hyperos_port.git
    cd hyperos_port
    # 安装依赖
    sudo ./setup.sh
    # 开始移植
    sudo ./port.sh <底包路径> <移植包路径>
```
- 在macOS下
```shell
    # 安装brew
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # 克隆项目
    git clone https://github.com/toraidl/hyperos_port.git
    cd hyperos_port
    # 安装依赖
    sudo ./setup.sh
    # 开始移植
    sudo ./port.sh <底包路径> <移植包路径>
```
- 在Termux上(未测试)
```shell
    pkg update
    pkg upgrade
    pkg install git tsu -y
    # 克隆项目
    git clone https://github.com/toraidl/hyperos_port.git
    cd hyperos_port/
    # 安装依赖
    ./setup.sh
    # 进入root模式
    tsu
    ./port.sh <底包路径> <移植包路径>
```
- 上述代码中，底包路径和移植包路径可以替换为链接

## GitHub Actions

Every build downloads [MiuiCamera 6.0.001240.1](https://drive.google.com/file/d/1a_I20XHYjxNOn5mudIoenHCRaqGPAb93/view?usp=drive_link) before extracting firmware. The URL is configurable as `miuicamera_url` in `bin/port_config`. Invalid APKs and download errors stop the build. After device overlays, the downloaded APK replaces the old camera in `product/priv-app/MiuiCamera`, with stale copies and `oat` removed. Its native libraries remain inside the original APK; the required `TURN_SCREEN_ON` permission is granted in `product/etc/permissions/privapp-permissions-miuicamera.xml`.

Open [Actions → Build HyperOS port](https://github.com/dollbluesvanus0/hyperos_port/actions/workflows/build-port.yml), select **Run workflow**, choose branch **test**, and start the build.

**Pixeldrain upload is enabled by default.** First create a key on [Pixeldrain's API keys page](https://pixeldrain.com/user/api_keys) and add it under **Settings → Secrets and variables → Actions → New repository secret**, named **`PIXELDRAIN_API_KEY`**. The workflow checks authentication before downloading firmware. To build using GitHub artifacts alone, uncheck **Upload to Pixeldrain**.

The stock and donor URLs are already filled in:

- Stock: **Venus / Mi 11**, HyperOS **OS2.0.3.0.UKBMIXM**, Android 14.
- Donor: **Diting / Redmi K50 Ultra**, HyperOS **OS2.0.211.0.VLFCNXM**, Android 15.

Both inputs require an official HTTPS OTA ZIP containing `payload.bin`. Keep **Repack as EXT4** enabled for the default build; disabling it preserves the stock filesystem. `aosp` produces the OTA/recovery ZIP, while `super` produces the existing super-image flash package.

The workflow installs dependencies on Ubuntu 24.04, frees unused runner SDKs, and requires at least 40 GiB of free space before downloading. It deletes its own downloaded archives after extraction and redundant extracted trees before packaging. Builds have a six-hour timeout.

When the run succeeds, download **hyperos-port-<run ID>** from **Artifacts**; it contains the ROM ZIP and `SHA256SUMS`. **build-log-<run ID>** contains the download/build log, including failed builds that reached the build step. Artifacts are retained for **7 days**. A successful ZIP build still needs boot/functionality testing on the target device.

After building, the workflow uploads the ROM ZIP through [Pixeldrain's PUT API](https://pixeldrain.com/api) and verifies the returned size and SHA256 against the local file. The download link appears in the run summary and `pixeldrain-links.txt` inside the log artifact. If uploading fails, the GitHub ROM artifact remains available. Pixeldrain's file-size and storage limits depend on your account plan.

## 感谢
> 本项目使用了以下开源项目的部分或全部内容，感谢这些项目的开发者（排名顺序不分先后）。

- [「BypassSignCheck」by Weverses](https://github.com/Weverses/BypassSignCheck)
- [「contextpatch」 by ColdWindScholar](https://github.com/ColdWindScholar/TIK)
- [「fspatch」by affggh](https://github.com/affggh/fspatch)
- [「gettype」by affggh](https://github.com/affggh/gettype)
- [「lpunpack」by unix3dgforce](https://github.com/unix3dgforce/lpunpack)
- [「miui_port」by ljc-fight](https://github.com/ljc-fight/miui_port)
- etc
