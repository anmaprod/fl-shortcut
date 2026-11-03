// « Quitter et rouvrir » : la copie relancée attend l'ancienne au lieu de partir, et l'app reprend là où on en était.
import XCTest
@testable import FLShortcut

final class AppResumeTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "FLShortcutTests-\(UUID())")!
    }

    func testOnlyARecentStateWithSomethingOpenIsResumed() {
        let now = Date()
        var state = ResumeState()
        state.editor = true
        state.page = "macros"
        state.savedAt = now.addingTimeInterval(-30)
        XCTAssertEqual(ResumeState.pending(state, now: now), state, "relancée 30 s après : reprise")
        state.savedAt = now.addingTimeInterval(-(ResumeState.maxAge + 1))
        XCTAssertNil(ResumeState.pending(state, now: now), "relancée bien plus tard (Mac redémarré) : rien ne s'ouvre")
        state.savedAt = now.addingTimeInterval(60)
        XCTAssertNil(ResumeState.pending(state, now: now), "date dans le futur (horloge changée) : ignorée")
        XCTAssertNil(ResumeState.pending(ResumeState(savedAt: now), now: now), "seule l'icône : rien à rouvrir")
        XCTAssertNil(ResumeState.pending(nil, now: now))
    }

    func testEveryPageComesBack() {
        let pages: [SidebarItem] = FLSection.allCases.map(SidebarItem.section) + [.custom, .macros, .community, .help, .account]
        for page in pages {
            XCTAssertEqual(SidebarItem(resumeKey: page.resumeKey), page, page.resumeKey)
        }
        XCTAssertNil(SidebarItem(resumeKey: "section:inconnue"))
        XCTAssertNil(SidebarItem(resumeKey: ""))
    }

    func testStateIsSavedAtQuitThenReadOnceAtLaunch() {
        let defaults = makeDefaults()
        let resume = AppResume()
        let quitAt = Date()
        resume.saveOnQuit(defaults, permissions: true, organizer: true, now: quitAt)
        let loaded = resume.load(defaults, now: quitAt.addingTimeInterval(3))
        XCTAssertEqual(loaded?.permissions, true)
        XCTAssertEqual(loaded?.organizer, true)
        XCTAssertEqual(loaded?.editor, false, "fenêtre principale fermée : elle reste fermée")
        XCTAssertNil(defaults.data(forKey: AppResume.key), "effacé dès la lecture : repris une seule fois")
        XCTAssertNil(resume.load(defaults, now: quitAt.addingTimeInterval(4)))
    }

    func testNothingOpenLeavesNothingBehind() {
        let defaults = makeDefaults()
        defaults.set(Data([1, 2, 3]), forKey: AppResume.key)
        AppResume().saveOnQuit(defaults, permissions: false, organizer: false)
        XCTAssertNil(defaults.data(forKey: AppResume.key))
    }

    func testWelcomeStepIsTakenOnce() {
        let defaults = makeDefaults()
        let resume = AppResume()
        resume.onboardingStage = "guide"
        resume.guidePage = 3
        resume.saveOnQuit(defaults, permissions: false, organizer: false)
        resume.load(defaults)
        XCTAssertEqual(resume.takeOnboarding()?.stage, "guide")
        XCTAssertNil(resume.takeOnboarding(), "l'accueil ne revient pas deux fois au même écran")
        XCTAssertNil(resume.takeEditor())
    }

    /// La copie relancée attend que l'ancienne soit partie ; une copie qui reste ouverte n'est pas attendue au-delà.
    func testRelaunchedCopyWaitsForTheOldOneToLeave() throws {
        let done = Process()
        done.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try done.run()
        done.waitUntilExit()
        XCTAssertTrue(SingleInstance.waitForExit(done.processIdentifier, timeout: 1), "partie : la relance continue")
        let start = Date()
        XCTAssertFalse(SingleInstance.waitForExit(getpid(), timeout: 0.3), "toujours là : pas de deuxième copie")
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        // Une copie qui se ferme est attendue plus longtemps (la note peut n'arriver qu'après le début de l'attente).
        var asked = 0
        let longer = Date()
        XCTAssertFalse(SingleInstance.waitForExit(getpid(), timeout: 0.3, longer: {
            asked += 1
            return asked > 1
        }, longTimeout: 0.6))
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(longer), 0.5, "attendue jusqu'au bout")
    }

    /// La note « je me ferme » d'une copie : lue par la copie relancée.
    func testQuittingNoteIsReadByTheRelaunchedCopy() {
        let saved = try? Data(contentsOf: SingleInstance.quittingFile)
        defer {
            if let saved { try? saved.write(to: SingleInstance.quittingFile) } else {
                try? FileManager.default.removeItem(at: SingleInstance.quittingFile)
            }
        }
        try? FileManager.default.removeItem(at: SingleInstance.quittingFile)
        let other: pid_t = 999_999
        XCTAssertFalse(SingleInstance.isQuitting(other))
        try? Data("\(other)".utf8).write(to: SingleInstance.quittingFile)
        XCTAssertTrue(SingleInstance.isQuitting(other))
        XCTAssertFalse(SingleInstance.isQuitting(other - 1))
    }

    /// « Quitter et rouvrir » vient de Réglages Système, ou de sa page « Confidentialité et sécurité » (une extension
    /// à part, parfois sans nom d'app : retour du propriétaire, l'app ne revenait pas) : l'app se relance elle-même ;
    /// quittée par l'utilisateur, la fin de session ou une autre app : non.
    func testOnlySystemSettingsAsksForARelaunch() {
        typealias Sender = SingleInstance.QuitSender
        XCTAssertTrue(SingleInstance.isSettings("com.apple.systempreferences"))
        XCTAssertTrue(SingleInstance.isSettings("com.apple.Settings"))
        XCTAssertTrue(SingleInstance.isSettings("com.apple.settings.PrivacySecurity.extension"))
        XCTAssertFalse(SingleInstance.isSettings(nil))
        XCTAssertTrue(SingleInstance.relaunches(Sender(bundle: "com.apple.systempreferences")))
        XCTAssertTrue(SingleInstance.relaunches(Sender(bundle: nil,
            path: "/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/MacOS/SecurityPrivacyExtension")))
        XCTAssertTrue(SingleInstance.relaunches(Sender(bundle: nil, path: "/System/Library/PrivateFrameworks/TCC.framework/Support/tccd")))
        XCTAssertTrue(SingleInstance.relaunches(Sender(bundle: nil, path: nil)), "envoyeur déjà parti")
        XCTAssertFalse(SingleInstance.relaunches(nil), "⌘Q : pas de relance")
        XCTAssertFalse(SingleInstance.relaunches(Sender(bundle: "com.apple.loginwindow",
            path: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow", sessionEnd: true)),
                       "fin de session : pas de relance")
        XCTAssertFalse(SingleInstance.relaunches(Sender(bundle: "com.apple.dock",
            path: "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock")), "quittée depuis le Dock")
        XCTAssertFalse(SingleInstance.relaunches(Sender(bundle: "com.apple.ActivityMonitor",
            path: "/System/Applications/Utilities/Activity Monitor.app/Contents/MacOS/Activity Monitor")))
        XCTAssertFalse(SingleInstance.relaunches(Sender(bundle: "com.raycast.macos",
            path: "/Applications/Raycast.app/Contents/MacOS/Raycast")), "une autre app : pas de relance")
        XCTAssertEqual(Sender(bundle: nil, path: "/System/Library/x/tccd").label, "tccd")
        XCTAssertNil(SingleInstance.quitSender(), "aucun événement « quit » en cours")
        XCTAssertNotNil(SingleInstance.processPath(getpid()))
    }

    /// 01/11 : relancée en pleine autorisation, l'app note laquelle et l'attend (cachée) ; un état noté par une version
    /// d'avant (sans « asking ») se lit toujours.
    func testPermissionBeingAskedIsKeptForTheRelaunchedCopy() throws {
        let defaults = makeDefaults()
        let resume = AppResume()
        resume.onboardingStage = "keyboard"
        resume.saveOnQuit(defaults, permissions: false, organizer: false, asking: "clavier")
        XCTAssertEqual(resume.load(defaults)?.asking, "clavier")
        let old = #"{"onboarding":"keyboard","guidePage":0,"permissions":false,"editor":false,"macroIsNew":false,"#
            + #""organizer":false,"savedAt":0}"#
        let decoded = try JSONDecoder().decode(ResumeState.self, from: Data(old.utf8))
        XCTAssertNil(decoded.asking)
        XCTAssertEqual(decoded.onboarding, "keyboard")
    }

    /// Retour du 01/11 au soir (« n'attend toujours pas ») : l'autorisation en cours est notée dès la demande, pas
    /// seulement en quittant (macOS peut fermer l'app de force) ; lue une fois au lancement, moins de 3 minutes après.
    func testPermissionBeingAskedIsNotedAsSoonAsAsked() {
        let defaults = makeDefaults()
        let resume = AppResume()
        let now = Date()
        resume.noteAsking("son", defaults, now: now)
        XCTAssertEqual(resume.takeAsking(defaults, now: now.addingTimeInterval(20)), "son")
        XCTAssertNil(resume.takeAsking(defaults, now: now.addingTimeInterval(21)), "lue une seule fois")
        resume.noteAsking("son", defaults, now: now)
        XCTAssertNil(resume.takeAsking(defaults, now: now.addingTimeInterval(181)), "trop vieille : plus d'attente")
        resume.noteAsking("clavier", defaults, now: now)
        resume.noteAsking(nil, defaults)
        XCTAssertNil(resume.takeAsking(defaults, now: now), "donnée ou abandonnée : effacée")
        defaults.set(["key": "autre chose", "at": now.timeIntervalSince1970], forKey: AppResume.askingKey)
        XCTAssertNil(resume.takeAsking(defaults, now: now), "seulement « clavier » ou « son »")
    }

    /// Retour du 02/11 (« Son de FL reste À autoriser quand j'appuie sur Autoriser ») : la réponse de TCC lue telle
    /// quelle (0 oui, 1 non, le reste : pas demandé) ; « Autorisé » aussi après « Autoriser » choisi à la question, ou
    /// avec la case « écran et audio du système » ; un refus noté par TCC reste un refus sans cette case.
    func testSoundAllowedEvenWhenTCCSaysNothing() {
        XCTAssertEqual(AudioCapturePermission.from(0), .granted)
        XCTAssertEqual(AudioCapturePermission.from(1), .denied)
        XCTAssertEqual(AudioCapturePermission.from(2), .unknown)
        XCTAssertEqual(AudioCapturePermission.from(nil), .unknown)
        // 03/11 : le son de FL, c'est « Enregistrement de l'écran et audio du système » (liste du haut).
        XCTAssertEqual(AudioCapturePermission.screenStatus(preflight: true, raw: nil), .granted)
        XCTAssertEqual(AudioCapturePermission.screenStatus(preflight: false, raw: 0), .granted, "TCC lu en direct")
        XCTAssertEqual(AudioCapturePermission.screenStatus(preflight: false, raw: 1), .denied)
        XCTAssertEqual(AudioCapturePermission.screenStatus(preflight: false, raw: 2), .unknown)
        XCTAssertEqual(AudioCapturePermission.screenStatus(preflight: false, raw: nil), .unknown)
    }

    func testWelcomeWaitsUntilThePermissionIsGiven() {
        XCTAssertTrue(PermissionRelaunchWait.missing("clavier", keyboardOK: false, audioOK: true))
        XCTAssertFalse(PermissionRelaunchWait.missing("clavier", keyboardOK: true, audioOK: false))
        XCTAssertTrue(PermissionRelaunchWait.missing("son", keyboardOK: true, audioOK: false))
        XCTAssertFalse(PermissionRelaunchWait.missing("autre", keyboardOK: false, audioOK: false))
        XCTAssertFalse(PermissionRelaunchWait.ends(missing: true, settingsGoneFor: nil, elapsed: 30),
                       "Réglages encore ouverts, pas encore autorisé : l'accueil attend")
        XCTAssertTrue(PermissionRelaunchWait.ends(missing: false, settingsGoneFor: nil, elapsed: 1), "autorisé : il revient")
        XCTAssertFalse(PermissionRelaunchWait.ends(missing: true, settingsGoneFor: 1, elapsed: 5))
        XCTAssertTrue(PermissionRelaunchWait.ends(missing: true, settingsGoneFor: 2, elapsed: 5), "Réglages fermés")
        XCTAssertTrue(PermissionRelaunchWait.ends(missing: true, settingsGoneFor: nil, elapsed: 180), "3 minutes au plus")
    }
}
