import Foundation

/// Staat van het app-slot (SPEC §10) voor de root-view en het
/// instellingenscherm. Vergrendelt bij een koude start en na terugkeer uit de
/// achtergrond (na de ingestelde grace period) als het slot aan staat.
@Observable
public final class AppLockViewModel {

    public private(set) var isLocked: Bool
    public private(set) var isAuthenticating = false
    public var isEnabled: Bool
    public var gracePeriod: TimeInterval
    public var errorMessage: String?

    private let service: AppLockService
    private var backgroundedAt: Date?

    public init(service: AppLockService = AppLockService()) {
        self.service = service
        self.isEnabled = service.isEnabled
        self.gracePeriod = service.gracePeriod
        self.isLocked = AppLockService.shouldLock(isEnabled: service.isEnabled, backgroundedAt: nil, now: Date(), gracePeriod: 0)
    }

    public var methodName: String { service.methodName() }
    public var canAuthenticate: Bool { service.canAuthenticate() }

    // MARK: - Levenscyclus

    public func didEnterBackground(now: Date = Date()) {
        backgroundedAt = now
    }

    /// Bij terugkeer uit de achtergrond: vergrendelen als dat nodig is en meteen
    /// om ontgrendeling vragen. Een wissel via `.inactive` (bijv. de Face
    /// ID-prompt zelf of het control center) telt niet, zodat annuleren niet
    /// in een lus steeds opnieuw om Face ID vraagt.
    @MainActor
    public func didBecomeActive(now: Date = Date()) async {
        guard let backgroundedAt else { return }
        self.backgroundedAt = nil
        guard AppLockService.shouldLock(isEnabled: isEnabled, backgroundedAt: backgroundedAt, now: now, gracePeriod: gracePeriod) else { return }
        isLocked = true
        await unlock()
    }

    @MainActor
    public func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        let success = await service.authenticate()
        isAuthenticating = false
        if success {
            isLocked = false
            errorMessage = nil
        } else {
            errorMessage = "Ontgrendelen mislukt. Probeer het opnieuw."
        }
    }

    // MARK: - Instellingen

    /// Zet het slot aan (pas na een geslaagde authenticatie, zodat je jezelf
    /// niet buitensluit) of uit.
    @MainActor
    public func setEnabled(_ enabled: Bool) async {
        if enabled {
            guard service.canAuthenticate() else {
                errorMessage = "Stel eerst Face ID, Touch ID of een toegangscode in op je toestel."
                isEnabled = false
                return
            }
            guard await service.authenticate(reason: "Bevestig om het app-slot aan te zetten") else {
                isEnabled = false
                return
            }
        }
        errorMessage = nil
        isEnabled = enabled
        service.isEnabled = enabled
    }

    public func setGracePeriod(_ value: TimeInterval) {
        gracePeriod = value
        service.gracePeriod = value
    }
}
