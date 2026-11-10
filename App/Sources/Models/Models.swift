import Foundation

// MARK: - Device

struct Device: Identifiable, Equatable, Sendable, Hashable {
    let serial: String
    var state: DeviceState

    // 상세(비동기 채움)
    var model: String?
    var brand: String?
    var manufacturer: String?
    var androidVersion: String?
    var sdkInt: Int?
    var batteryLevel: Int?
    var isCharging: Bool?
    var screenSize: String?
    /// 기기 고유 시리얼(ro.serialno) — 같은 폰이 여러 전송(USB·Tailscale·LAN)으로 붙었는지 판별용.
    var serialNo: String?

    var id: String { serial }

    /* 변경 전: ':'가 없으면 USB로 봤다 → adb가 mDNS로 자동 연결한 무선 기기
       ("adb-<serial>-<id>._adb-tls-connect._tcp")가 USB로 표시되고 '무선으로 전환'이 떴다.
       변경 후: mDNS 서비스 이름(._tcp)도 무선으로 분류한다. */
    var isUSB: Bool { !serial.contains(":") && !serial.hasSuffix("._tcp") }
    var displayModel: String { model ?? serial }

    /// ip:port 시리얼의 IP 부분(그 외 nil).
    var wirelessIP: String? {
        guard serial.contains(":") else { return nil }
        return serial.split(separator: ":").first.map(String.init)
    }

    /// CGNAT 대역(100.64/10 — Tailscale 등 VPN)으로 연결된 무선 기기인지.
    /// 자동발견(mDNS)이 안 되는 환경 안내에 사용(실측: VPN 연결은 mDNS 멀티캐스트가 못 넘어옴).
    var isVPNConnected: Bool {
        guard !isUSB else { return false }
        let octets = serial.split(separator: ":").first?
            .split(separator: ".").compactMap { Int($0) } ?? []
        guard octets.count == 4 else { return false }
        return octets[0] == 100 && (64...127).contains(octets[1])
    }

    var stateBadge: String {
        switch state {
        case .online: return isUSB ? "USB" : "Wi-Fi"
        case .offline: return String(localized: "오프라인")
        case .unauthorized: return String(localized: "승인 필요")
        case .unknown: return String(localized: "인식 안 됨")
        }
    }
}

enum DeviceState: String, Equatable, Sendable {
    case online = "device"
    case offline = "offline"
    case unauthorized = "unauthorized"
    case unknown

    init(rawState: String) {
        switch rawState.trimmingCharacters(in: .whitespaces) {
        case "device": self = .online
        case "offline": self = .offline
        case "unauthorized": self = .unauthorized
        default: self = .unknown
        }
    }
}

// MARK: - Android App

struct AndroidApp: Identifiable, Hashable, Sendable {
    let package: String
    let apkPath: String?

    var label: String?
    var iconURL: URL?
    /// 런처 액티비티(앱 인덱서가 알려 줌) — 있으면 am start로 바로 연다.
    var activity: String?

    var id: String { package }

    /// aapt2 라벨이 없을 때 쓸 폴백: 마지막 세그먼트를 사람 이름처럼.
    var fallbackLabel: String {
        let last = package.split(separator: ".").last.map(String.init) ?? package
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    var displayLabel: String { label ?? fallbackLabel }

    /// 모노그램 타일 배경색 결정(패키지 해시 기반 고정 팔레트).
    var monogramColorIndex: Int {
        abs(package.hashValue) % 8
    }
}

// MARK: - 연결했던 기기 저장

/// 한번 연결된 기기의 스냅샷 — 사이드바 '최근 기기' 목록과 원클릭 재연결에 쓴다.
/* 변경 전 정책: 무선 재접속용 ip:port 목록(wirelessHostsKey)만 저장했다 — 포트가 바뀌어
   refused가 오면 삭제됐고, 기기 이름·USB 이력은 남지 않아 "한번 연결했던 폰"이 UI에 없었다.
   변경 후 정책: 기기 단위(ro.serialno 기준)로 모델명·마지막 무선 주소·마지막 연결 시각을 저장한다.
   변경 이유: 재스캔/재입력 없이 최근 기기를 한 번에 다시 연결하기 위함.
   영향 범위: 기기가 online으로 확인될 때마다 갱신, 사이드바 최근 기기 섹션. */
struct SavedDevice: Codable, Identifiable, Equatable, Sendable {
    /// 기기 고유 id — ro.serialno(전송 무관) 우선, 못 얻으면 마지막 adb serial.
    let id: String
    var model: String?
    var brand: String?
    var androidVersion: String?
    /// 마지막 무선 연결 주소(ip:port) — 원클릭 재연결 대상. USB/mDNS 전송이면 nil.
    var lastHost: String?
    /// 마지막으로 본 adb serial(USB 시리얼 또는 ip:port) — 현재 연결 여부 판별용.
    var lastSerial: String
    var wasWireless: Bool
    var lastConnectedAt: Date

    var displayModel: String { model ?? lastSerial }

    /// 행 부제목 — 마지막 주소(무선) 또는 USB 안내.
    var subtitle: String {
        if let lastHost { return lastHost }
        return String(localized: "USB · 케이블을 연결하면 자동 인식")
    }
}

/// 연결했던 기기 저장소(UserDefaults Codable 배열) — 저장·병합·삭제만 담당.
enum SavedDeviceStore {
    private static let key = "MacDroid.savedDevices"
    /// 최근 기기 상한 — 무선 자동 재접속 목록(wirelessHostsKey)의 8개와 같은 취지.
    private static let limit = 10

    static func load() -> [SavedDevice] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedDevice].self, from: data) else { return [] }
        return decoded.sorted { $0.lastConnectedAt > $1.lastConnectedAt }
    }

    private static func save(_ devices: [SavedDevice]) {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// 기기 스냅샷을 저장 목록에 반영(같은 기기 병합, 최근순, 상한 초과분 삭제).
    /// id뿐 아니라 lastSerial(ip:port)이 같은 옛 기록도 함께 흡수한다 — 상세(serialNo) 채워지기 전에
    /// ip:port를 id로 먼저 저장한 중복 기록을 막기 위함.
    @discardableResult
    static func upsert(device: Device) -> [SavedDevice] {
        guard device.state == .online else { return load() }
        let entry = SavedDevice(
            id: device.serialNo ?? device.serial,
            model: device.model,
            brand: device.brand,
            androidVersion: device.androidVersion,
            // 무선 중에서도 ip:port 전송만 재연결 주소로 쓴다(mDNS 이름 전송은 adb connect 대상이 아니다)
            lastHost: device.wirelessIP != nil ? device.serial : nil,
            lastSerial: device.serial,
            wasWireless: !device.isUSB,
            lastConnectedAt: Date()
        )
        var devices = load()
        // 이미 저장된 모델명/마지막 주소는 새 스냅샷이 비었을 때 유지(부분 실패 허용 정책)
        var merged = entry
        if let previous = devices.first(where: { $0.id == entry.id || $0.lastSerial == entry.lastSerial }) {
            merged.model = merged.model ?? previous.model
            merged.brand = merged.brand ?? previous.brand
            merged.androidVersion = merged.androidVersion ?? previous.androidVersion
            if entry.lastHost == nil { merged.lastHost = previous.lastHost }
        }
        devices.removeAll { $0.id == entry.id || $0.lastSerial == entry.lastSerial }
        devices.insert(merged, at: 0)
        if devices.count > limit { devices = Array(devices.prefix(limit)) }
        save(devices)
        return devices
    }

    static func remove(id: String) -> [SavedDevice] {
        var devices = load()
        devices.removeAll { $0.id == id }
        save(devices)
        return devices
    }
}

// MARK: - mDNS 발견 서비스

struct MdnsService: Identifiable, Equatable, Sendable {
    let name: String
    let address: String  // ip:port
    /// 페어링 대기 서비스(_adb-tls-pairing) — 이름(표시 문구)이 언어에 따라 바뀌므로 판별은 이 값으로.
    var isPairing = false
    var id: String { name + address }
}

// MARK: - 미러링 설정

/// 화면 품질 프리셋. 사용자가 개별 값을 건드리면 custom으로 전환.
enum QualityPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case balanced = "balanced"      // 균형(기본)
    case crisp = "crisp"            // 선명
    case lightweight = "lightweight" // 가볍게(무선/저사양)

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return String(localized: "균형")
        case .crisp: return String(localized: "선명")
        case .lightweight: return String(localized: "가볍게")
        }
    }

    var subtitle: String {
        switch self {
        case .balanced: return String(localized: "H.264 · 20 Mbps · 최대 1920px")
        case .crisp: return String(localized: "H.265 · 30 Mbps · 최대 2560px")
        case .lightweight: return String(localized: "H.264 · 4 Mbps · 최대 1280px · 60fps 제한")
        }
    }

    var values: MirrorSettings.Video {
        switch self {
        /* 비트레이트 정책: 움직임에서 블록/끊김(버벅임으로 느껴짐)이 나지 않는 수준으로.
           가상 디스플레이는 기기가 60Hz로 상한(One UI 실측 — new-display fps 파라미터 무시)이고
           캡처 프레임은 이미 무제한(maxFPS 0)이므로, 매끄러움을 좌우하는 건 비트레이트다. */
        case .balanced: return .init(codec: "h264", bitRateMbps: 20, maxSize: 1920, maxFPS: 0)
        case .crisp: return .init(codec: "h265", bitRateMbps: 30, maxSize: 2560, maxFPS: 0)
        case .lightweight: return .init(codec: "h264", bitRateMbps: 4, maxSize: 1280, maxFPS: 60)
        }
    }
}

struct MirrorSettings: Codable, Equatable, Sendable {
    struct Video: Codable, Equatable, Sendable {
        var codec: String        // h264 | h265 | av1
        var bitRateMbps: Int
        var maxSize: Int         // 0 = 제한 없음
        var maxFPS: Int          // 0 = 제한 없음
    }

    struct VirtualDisplay: Codable, Equatable, Sendable {
        var width: Int
        var height: Int
        var density: Int
    }

    var preset: QualityPreset
    var video: Video
    var audioEnabled: Bool = true
    var stayAwake: Bool = true
    var turnScreenOff: Bool = false
    var showTouches: Bool = false
    var advancedInput: Bool = true    // uhid 키보드/마우스(호버·물리키보드 경험)
    var virtualDisplay: VirtualDisplay = .init(width: 1920, height: 1080, density: 240)

    var isCustomVideo: Bool {
        video != preset.values
    }

    static let `default` = MirrorSettings(
        preset: .balanced,
        video: QualityPreset.balanced.values
    )

    // MARK: 저장

    private static let storageKey = "MacDroid.mirrorSettings"

    static func load() -> MirrorSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(MirrorSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
