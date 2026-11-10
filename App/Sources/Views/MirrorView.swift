import SwiftUI

/// 폰 본체 화면 미러 창 — MacDroid 자체 창(외부 scrcpy 앱 창이 따로 뜨지 않는다).
/* 정책: 영상은 MirrorSession(DesktopStream mirror 모드)이 폰 본체 화면을 그대로 받아 FrameHub로 뿌리고,
   이 창은 그 전체 프레임을 비율 유지(aspectFit)로 보여 준다. 마우스·키보드 입력은 DesktopVideoView가
   절대좌표 터치·uhid 키보드로 전달한다(데스크톱 창과 같은 경로 — 한글 조합 포함). */
struct MirrorView: View {
    @Environment(AppState.self) private var appState
    let serial: String

    @State private var session: MirrorSession?

    private var device: Device? { appState.device(for: serial) }

    var body: some View {
        Group {
            if let session, session.videoSize.width > 0, session.stream != nil {
                DesktopVideo(session: session, windowID: 0,
                             crop: CGRect(origin: .zero, size: session.videoSize))
                    .aspectRatio(session.videoSize.width / session.videoSize.height, contentMode: .fit)
            } else if let session, let error = session.errorMessage {
                ContentUnavailableView {
                    Label("미러링 실패", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("다시 시도") {
                        session.stop()
                        self.session = nil
                        start()
                    }
                }
            } else {
                ProgressView("폰 화면 연결 중…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .navigationTitle("미러링 · \(device?.displayModel ?? serial)")
        .onAppear(perform: start)
        .onDisappear {
            session?.stop()
            session = nil
        }
    }

    private func start() {
        guard session == nil else { return }
        let new = MirrorSession(serial: serial, appState: appState)
        session = new
        new.start()
    }
}
