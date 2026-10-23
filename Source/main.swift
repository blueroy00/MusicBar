import AppKit

struct Playback {
    var state = "stopped"
    var title = "暂无播放"
    var artist = "在 Apple Music 中选择音乐"
    var position: Double = 0
    var duration: Double = 0
    var running = false
    var hasTrack = false
    var playing: Bool { state == "playing" }
    var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
}

func timestamp(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let value = Int(min(seconds, 604800))
    return String(format: "%d:%02d", value / 60, value % 60)
}

final class MusicBridge {
    private let queue = DispatchQueue(label: "local.musicbar.applescript")
    private var pending = 0
    private let readScript = """
    if application id "com.apple.Music" is not running then return {"closed", "", "", 0, 0}
    tell application id "com.apple.Music"
        with timeout of 3 seconds
            set playbackState to player state as text
            try
                set currentSong to current track
                return {playbackState, name of currentSong, artist of currentSong, player position, duration of currentSong}
            on error messageText number errorNumber
                if errorNumber is -1728 or errorNumber is -1719 then return {playbackState, "", "", 0, 0}
                error messageText number errorNumber
            end try
        end timeout
    end tell
    """

    func run(command: String? = nil, completion: @escaping (Playback?, String?) -> Void) {
        guard command != nil || pending == 0 else { return }
        pending += 1
        queue.async {
            var result: Playback?
            var failure: String?
            autoreleasepool {
                if let command {
                    var error: NSDictionary?
                    let source = """
                    if application id "com.apple.Music" is running then
                        tell application id "com.apple.Music"
                            with timeout of 3 seconds
                                \(command)
                            end timeout
                        end tell
                    end if
                    """
                    NSAppleScript(source: source)?.executeAndReturnError(&error)
                    if let error { failure = Self.errorMessage(error) }
                }
                if failure == nil {
                    var error: NSDictionary?
                    if let value = NSAppleScript(source: self.readScript)?.executeAndReturnError(&error), error == nil,
                       value.numberOfItems == 5 {
                        var playback = Playback()
                        playback.state = value.atIndex(1)?.stringValue ?? "stopped"
                        playback.running = playback.state != "closed"
                        let title = value.atIndex(2)?.stringValue ?? ""
                        playback.hasTrack = !title.isEmpty
                        if playback.hasTrack {
                            playback.title = title
                            playback.artist = value.atIndex(3)?.stringValue ?? ""
                        } else if !playback.running {
                            playback.title = "Apple Music 未打开"
                        }
                        playback.position = value.atIndex(4)?.doubleValue ?? 0
                        playback.duration = value.atIndex(5)?.doubleValue ?? 0
                        result = playback
                    } else {
                        failure = error.map(Self.errorMessage) ?? "无法读取音乐信息"
                    }
                }
            }
            let playback = result
            let message = failure
            DispatchQueue.main.async {
                self.pending -= 1
                completion(playback, message)
            }
        }
    }

    private static func errorMessage(_ error: NSDictionary) -> String {
        if (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 {
            return "请在系统设置 → 隐私与安全性 → 自动化中，允许 MusicBar 控制音乐。授权后点击重试。"
        }
        return error[NSAppleScript.errorMessage] as? String ?? "暂时无法连接 Apple Music"
    }
}

final class PlayerView: NSViewController {
    let song = NSTextField(labelWithString: "正在连接 Apple Music…")
    let artist = NSTextField(labelWithString: "")
    let progress = NSProgressIndicator()
    let elapsed = NSTextField(labelWithString: "0:00")
    let duration = NSTextField(labelWithString: "0:00")
    let errorLabel = NSTextField(wrappingLabelWithString: "")
    let retry = NSButton()
    let previous = NSButton()
    let toggle = NSButton()
    let next = NSButton()
    var onCommand: ((String) -> Void)?
    var onOpen: (() -> Void)?
    var onRetry: (() -> Void)?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 176))
        let heading = NSTextField(labelWithString: "APPLE MUSIC")
        heading.font = .systemFont(ofSize: 10, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        song.font = .systemFont(ofSize: 17, weight: .bold)
        song.lineBreakMode = .byTruncatingTail
        artist.font = .systemFont(ofSize: 12)
        artist.textColor = .secondaryLabelColor
        artist.lineBreakMode = .byTruncatingTail
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.style = .bar
        for label in [elapsed, duration] {
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
        }
        let times = NSStackView(views: [elapsed, NSView(), duration])
        times.orientation = .horizontal
        configure(previous, symbol: "backward.end.fill", label: "上一首", action: #selector(previousTrack))
        configure(toggle, symbol: "play.fill", label: "播放", action: #selector(playPause))
        configure(next, symbol: "forward.end.fill", label: "下一首", action: #selector(nextTrack))
        toggle.contentTintColor = .systemPink
        let controls = NSStackView(views: [previous, toggle, next])
        controls.orientation = .horizontal
        controls.spacing = 4
        controls.alignment = .centerY
        controls.widthAnchor.constraint(equalToConstant: 92).isActive = true
        song.setContentHuggingPriority(.defaultLow, for: .horizontal)
        song.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let titleRow = NSStackView(views: [song, controls])
        titleRow.orientation = .horizontal
        titleRow.distribution = .fill
        titleRow.alignment = .centerY
        titleRow.spacing = 8
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .secondaryLabelColor
        let open = NSButton(title: "打开音乐", target: self, action: #selector(openMusic))
        retry.title = "重试"
        retry.target = self
        retry.action = #selector(retryRead)
        let quit = NSButton(title: "退出控件", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        for button in [open, retry, quit] {
            button.bezelStyle = .inline
            button.font = .systemFont(ofSize: 11)
        }
        let footer = NSStackView(views: [open, retry, NSView(), quit])
        footer.orientation = .horizontal
        let stack = NSStackView(views: [heading, titleRow, artist, progress, times, errorLabel, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -14)
        ])
        for item in [titleRow, artist, progress, times, errorLabel, footer] {
            item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func configure(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(.init(pointSize: 17, weight: .medium))
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    func update(_ playback: Playback, error: String?) {
        _ = view
        song.stringValue = playback.title
        song.toolTip = playback.title
        artist.stringValue = playback.artist
        progress.doubleValue = playback.progress
        elapsed.stringValue = timestamp(playback.position)
        duration.stringValue = timestamp(playback.duration)
        errorLabel.stringValue = error ?? ""
        errorLabel.isHidden = error == nil
        retry.isHidden = error == nil
        let label = playback.playing ? "暂停" : "播放"
        toggle.image = NSImage(systemSymbolName: playback.playing ? "pause.fill" : "play.fill", accessibilityDescription: label)?.withSymbolConfiguration(.init(pointSize: 17, weight: .medium))
        toggle.toolTip = label
        toggle.setAccessibilityLabel(label)
        toggle.isEnabled = playback.running && error == nil
        previous.isEnabled = playback.hasTrack && error == nil
        next.isEnabled = playback.hasTrack && error == nil
    }

    @objc private func previousTrack() { onCommand?("previous track") }
    @objc private func playPause() { onCommand?("playpause") }
    @objc private func nextTrack() { onCommand?("next track") }
    @objc private func openMusic() { onOpen?() }
    @objc private func retryRead() { onRetry?() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let player = PlayerView()
    private let bridge = MusicBridge()
    private var playback = Playback()
    private var timer: Timer?
    private var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(showPlayer)
        item.button?.imagePosition = .imageLeading
        item.button?.font = .systemFont(ofSize: 12, weight: .medium)
        popover.behavior = .transient
        popover.contentViewController = player
        popover.contentSize = NSSize(width: 300, height: 176)
        player.onCommand = { [weak self] in self?.refresh(command: $0) }
        player.onRetry = { [weak self] in self?.refresh() }
        player.onOpen = {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Music.app"), configuration: .init())
        }
        render()
        refresh()
        // shortcut: poll every 2 seconds; use notifications if sub-second updates become necessary.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard self?.lastError == nil else { return }
            self?.refresh()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if !self.popover.isShown { self.showPlayer() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { showPlayer() }
        return true
    }

    private func refresh(command: String? = nil) {
        bridge.run(command: command) { [weak self] result, error in
            guard let self else { return }
            if let result { self.playback = result }
            self.lastError = error
            self.render()
        }
    }

    private func render() {
        let symbol = lastError != nil ? "exclamationmark.circle" : playback.playing ? "waveform" : "music.note"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "音乐控件")
        image?.isTemplate = true
        item.button?.image = image
        let name = playback.hasTrack ? playback.title : "音乐"
        item.button?.title = " " + String(name.prefix(18)) + (name.count > 18 ? "…" : "")
        item.button?.toolTip = lastError ?? "\(playback.title) — \(playback.artist)"
        player.update(playback, error: lastError)
        popover.contentSize = NSSize(width: 300, height: lastError == nil ? 176 : 236)
    }

    @objc private func showPlayer() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

if CommandLine.arguments.contains("--self-test") {
    assert(timestamp(0) == "0:00")
    assert(timestamp(-1) == "0:00")
    assert(timestamp(.nan) == "0:00")
    assert(timestamp(185.7) == "3:05")
    assert(Playback(position: 200, duration: 100).progress == 1)
    assert(Playback(position: -10, duration: 100).progress == 0)
    assert(Playback(position: 10, duration: 0).progress == 0)
    assert(Playback(state: "playing").playing)
    print("MusicBar: 8 self-checks passed")
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
