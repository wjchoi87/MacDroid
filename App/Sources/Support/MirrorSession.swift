import Foundation
import SwiftUI

/// 폰 본체 화면 미러 세션 — 외부 scrcpy 앱 창 대신 MacDroid 자체 창에서 그린다(대장님 요청).
/* 정책: 스트림·입력은 데스크톱과 같은 DesktopStream(scrcpy-server 직접 연결)을 재사용하되,
   new_display 없이 폰 본체 화면(디스플레이 0)을 영상으로 받는다(mirror=true).
   마우스는 절대좌표 터치 주입(커서 로컬 렌더링 — 버벅임 없음), 키보드는 uhid(한글 조합을 폰 IME가 직접).
   세션 동안 절전 방지(stay_on)는 데스크톱 세션과 같은 방식으로 걸고 종료 시 복구한다. */

/// CVPixelBuffer를 비동기 경계 넘겨 주는 상자(Sendable 아님을 숨긴다 — 데스크톱 세션과 같은 기법).
final class MirrorPixelBox: @unchecked Sendable {
    let buffer: CVPixelBuffer
    init(_ buffer: CVPixelBuffer) { self.buffer = buffer }
}

@MainActor
@Observable
final class MirrorSession: VideoFeedSession {

    let serial: String
    let frames = FrameHub()
    private(set) var stream: DesktopStream?
    private(set) var videoSize: CGSize = .zero
    private(set) var errorMessage: String?

    private weak var appState: AppState?
    private var stayOnSaved: Int?

    var input: DesktopStream? { stream }

    init(serial: String, appState: AppState?) {
        self.serial = serial
        self.appState = appState
    }

    func start() {
        guard stream == nil else { return }
        let video = appState?.settings.video
        let stream = DesktopStream(config: .init(
            serial: serial, width: 0, height: 0, density: 0,
            bitRateMbps: max(video?.bitRateMbps ?? 8, 8),
            maxFPS: video?.maxFPS ?? 0,
            screenOff: false,
            mirror: true
        ))
        let hub = frames
        stream.onFrame = { buffer in
            let box = MirrorPixelBox(buffer)   // CVPixelBuffer는 Sendable이 아니라 박스로 감싼다(데스크톱 세션 방식)
            DispatchQueue.main.async { MainActor.assumeIsolated { hub.publish(box.buffer) } }
        }
        stream.onVideoSize = { [weak self] size in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.videoSize = size } }
        }
        stream.onEnd = { [weak self] message in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finish(message) } }
        }
        stream.start()
        self.stream = stream
        // 세션 동안 폰이 잠들지 않게(이전값 기억 — 종료 시 복구)
        Task { if let previous = await ADB.enableStayAwake(serial: serial) { stayOnSaved = previous } }
    }

    private func finish(_ message: String?) {
        stream = nil
        if let message { errorMessage = message }
    }

    func stop() {
        stream?.stop()
        stream = nil
        if let previous = stayOnSaved {
            stayOnSaved = nil
            Task { await ADB.restoreStayAwake(serial: serial, previous: previous) }
        }
    }

    // MARK: VideoFeedSession(DesktopVideoView 입력 지원)

    func nudgeAwake() {}
    func markKeyboardUsed() {}
    func raiseLocally(_ id: Int) {}

    /// Esc = 안드로이드 뒤로가기(데스크톱 세션과 동일).
    func back() {
        stream?.pressKey(4)  // KEYCODE_BACK
    }

    func back(windowID: Int) { back() }
}
