**MacDroid — a native DeX for macOS.** Mirror your Android phone, or use it as a desktop on your Mac: Android apps open as windows inside MacDroid's own desktop (dock, status bar, desktop icons, folders, window snapping). English / 한국어.

### Download
- `MacDroid-<version>-macos-arm64.zip` — the app (Apple Silicon, macOS 14+). adb and scrcpy are bundled; nothing else to install.
- `macdroid-cli-<version>-macos-arm64.zip` — optional CLI for agents and scripts (uses the tools bundled in `/Applications/MacDroid.app`).

### First launch
MacDroid is notarized by Apple, so it opens with a normal double-click:
1. Unzip and move **MacDroid.app** to **Applications**
2. Allow **Local Network** access when asked (needed for Wi-Fi devices)

On the phone: Developer options → **USB debugging** (and **Wireless debugging** for Wi-Fi). See the [README](https://github.com/wjchoi87/MacDroid#readme) for details.

---

**처음 실행:** Apple 공증이 완료되어 일반 앱처럼 더블클릭으로 바로 실행할 수 있습니다. 압축을 풀어 **응용 프로그램** 폴더로 옮기고, 와이파이 기기를 쓰려면 **로컬 네트워크** 접근을 허용해 주세요. 자세한 내용은 [한국어 README](https://github.com/wjchoi87/MacDroid/blob/main/README.ko.md)를 참고하세요.
