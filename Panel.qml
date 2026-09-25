import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.gustavonline.local-ai"
  ipcTarget: "io.github.gustavonline.local-ai"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string controlPath: decodeURIComponent(
    String(Qt.resolvedUrl("local-ai-control")).replace(/^file:\/\//, "")
  )
  readonly property string assistantControlPath: decodeURIComponent(
    String(Qt.resolvedUrl("local-ai-assistant")).replace(/^file:\/\//, "")
  )
  readonly property string configFile: String(
    settings && settings.localConfigFile ? settings.localConfigFile : "~/.config/omarchy/local-ai.toml"
  )
  readonly property int refreshInterval: Math.max(5, Number(
    settings && settings.refreshIntervalSec ? settings.refreshIntervalSec : 10
  )) * 1000
  readonly property string assistantConfigFile: configFile
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string defaultSuggestionPath: home + "/.local/state/omarchy/local-ai-assistant/suggestion.json"
  readonly property string suggestionPath: String(assistantStatus.suggestionFile || defaultSuggestionPath)
  readonly property string voxtypeStatePath: String(Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000")
    + "/voxtype/state"
  readonly property var hostWindow: button.QsWindow.window

  property var status: ({
    profile: "stopped", state: "inactive", label: "Stopped", detail: "Local runtime",
    model: "", variant: "", context: "", backend: "Local AI", endpoint: "",
    configFile: "", defaultProfile: "", profiles: []
  })
  property bool busy: false
  property string feedback: ""
  property bool feedbackIsError: false
  property string pendingAction: ""
  property string pendingProfile: ""
  property bool cursorActive: false
  property bool settingsPage: false
  property var assistantStatus: ({
    configured: false, configError: "", enabled: false, active: false, paused: false,
    state: "disabled", model: "auto", endpoint: "", lastError: "",
    suggestionFile: "", playbookFile: "", delegateAvailable: false,
    privacy: { windowTitle: true, screenshots: false, denyRules: 0 }
  })
  property var suggestion: ({})
  property bool assistantBusy: false
  property string assistantFeedback: ""
  property bool assistantFeedbackIsError: false
  property string assistantPendingAction: ""
  property bool suggestionHoldWanted: false
  property bool suggestionHoldApplied: false
  property bool suggestionWindowPrepared: false
  property bool suggestionHovered: false
  property bool suggestionFocused: false
  property double clockMs: Date.now()
  property string selectedModelChoice: ""
  property string selectedConfidence: "0.72"
  property string selectedPreferredHarness: ""
  property string summonPrompt: ""
  property bool selectedShareWindowTitle: true
  property var selectedBlockedApps: []
  property var assistantModelOptions: []
  property var assistantHarnessOptions: []
  property int learnedDismissalCount: 0
  property string voxtypeState: "idle"
  property var dictationWaveform: []
  property real dictationPeak: 0
  property int voiceAnimationTick: 0
  property bool suggestionPresented: false
  property string cornerToastTitle: ""
  property string cornerToastBody: ""
  property bool cornerToastIsError: false
  property bool cornerToastPresented: false
  readonly property var confidenceOptions: [
    { value: "0.82", label: "Quiet", description: "Slow cadence · only very clear suggestions" },
    { value: "0.72", label: "Balanced", description: "Recommended cadence and selectivity" },
    { value: "0.62", label: "Proactive", description: "Faster checks · more concrete useful nudges" }
  ]

  readonly property bool running: status.state === "active"
  readonly property bool failed: status.state === "failed"
  readonly property string stateLabel: busy ? "Switching…" : (running ? "Running" : (failed ? "Failed" : "Stopped"))
  readonly property bool assistantEnabled: assistantStatus.enabled === true
  readonly property bool assistantActive: assistantStatus.active === true
  readonly property bool assistantPaused: assistantStatus.paused === true
  readonly property bool assistantFailed: assistantStatus.state === "error"
    || String(assistantStatus.lastError || "") !== ""
  readonly property bool suggestionVisible: String((suggestion || {}).id || "") !== ""
    && ((suggestion || {}).held === true || Number((suggestion || {}).expiresAt || 0) * 1000 > clockMs)
  readonly property bool summonMode: String((suggestion || {}).mode || "") === "summon"
  readonly property bool voiceMode: String((suggestion || {}).mode || "") === "voice"
  readonly property bool directMode: String((suggestion || {}).mode || "") === "direct"
  readonly property bool suggestionInteracting: suggestionHovered || suggestionFocused
  readonly property bool summonAwaitingInput: summonMode && (suggestion || {}).awaitingInput === true
  readonly property bool dictationRecording: voxtypeState === "recording"
  readonly property bool dictationTranscribing: voxtypeState === "streaming"
    || voxtypeState === "transcribing"
  readonly property bool voiceThinking: voiceMode && assistantStatus.state === "thinking"
  readonly property color voiceActivityColor: dictationRecording ? accent
    : (voiceThinking ? Qt.lighter(accent, 1.28) : foreground)
  readonly property string assistantStateLabel: {
    if (assistantBusy) return "Updating…"
    if (!assistantStatus.configured) return "Setup needed"
    if (!assistantEnabled) return "Off"
    if (assistantPaused) return "Paused"
    if (assistantStatus.state === "thinking") return "Thinking…"
    if (assistantStatus.state === "suggesting") return "Suggestion ready"
    if (assistantFailed) return "Needs attention"
    if (assistantActive) return "Watching"
    return "Waiting"
  }

  function profileTitle(profile) {
    if (!profile) return ""
    return String(profile.label || profile.id || "")
  }

  function activeDetail() {
    var parts = []
    if (status.model) parts.push(String(status.model))
    if (status.variant) parts.push(String(status.variant))
    if (status.context) parts.push(String(status.context) + " context")
    return parts.length > 0 ? parts.join(" · ") : String(status.detail || "Local runtime")
  }

  function voiceBarHeight(index) {
    if (dictationRecording) {
      var samples = dictationWaveform || []
      var sampleIndex = Math.max(0, samples.length - 4 + index)
      var sample = sampleIndex < samples.length ? Number(samples[sampleIndex] || 0) : 0
      return Math.max(Style.space(3), Math.min(Style.space(12), Style.space(3) + sample * Style.space(15)))
    }
    var pulse = [4, 7, 11, 7]
    return Style.space(pulse[(voiceAnimationTick + index) % pulse.length])
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
    if (!assistantStatusProcess.running) assistantStatusProcess.running = true
  }

  function clearFeedback() {
    feedbackClearTimer.stop()
    feedback = ""
    feedbackIsError = false
  }

  function showTransientFeedback(message) {
    feedbackIsError = false
    feedback = message
    feedbackClearTimer.restart()
  }

  function showError(message) {
    feedbackClearTimer.stop()
    feedback = message
    feedbackIsError = true
  }

  function runAction(action, profileId) {
    if (actionProcess.running) return
    busy = true
    pendingAction = action
    pendingProfile = profileId || ""
    clearFeedback()
    actionProcess.command = [controlPath, "--config", configFile, action]
    if (profileId) actionProcess.command.push(profileId)
    actionProcess.running = true
  }

  function copyEndpoint() {
    if (!status.endpoint || copyProcess.running) return
    copyProcess.command = ["wl-copy", String(status.endpoint)]
    copyProcess.running = true
  }

  function openConfig() {
    if (openConfigProcess.running) return
    var path = String(status.configFile || configFile)
    if (path === "") return
    openConfigProcess.command = ["omarchy", "launch", "config", "editor", path]
    openConfigProcess.running = true
  }

  function clearAssistantFeedback() {
    assistantFeedbackTimer.stop()
    assistantFeedback = ""
    assistantFeedbackIsError = false
  }

  function showAssistantFeedback(message) {
    assistantFeedback = message
    assistantFeedbackIsError = false
    assistantFeedbackTimer.restart()
  }

  function showAssistantError(message) {
    assistantFeedback = message
    assistantFeedbackIsError = true
    assistantFeedbackTimer.stop()
  }

  function showCornerToast(title, body, isError) {
    cornerToastTimer.stop()
    cornerToastClearTimer.stop()
    cornerToastTitle = String(title || "Local AI")
    cornerToastBody = String(body || "")
    cornerToastIsError = isError === true
    cornerToastPresented = false
    Qt.callLater(function() { root.cornerToastPresented = true })
    cornerToastTimer.restart()
  }

  function hideCornerToast() {
    cornerToastTimer.stop()
    cornerToastPresented = false
    cornerToastClearTimer.restart()
  }

  function runAssistantAction(action, argument) {
    if (assistantActionProcess.running) return
    assistantBusy = true
    assistantPendingAction = action
    clearAssistantFeedback()
    assistantActionProcess.command = [assistantControlPath, "--config", assistantConfigFile, action]
    if (action === "configure") {
      assistantActionProcess.command.push(selectedModelChoice)
      assistantActionProcess.command.push(selectedConfidence)
      assistantActionProcess.command.push(selectedShareWindowTitle ? "true" : "false")
      assistantActionProcess.command.push(JSON.stringify(selectedBlockedApps))
      assistantActionProcess.command.push(selectedPreferredHarness)
    }
    if ((action === "delegate" || action === "ask") && argument) {
      assistantActionProcess.command.push(String(argument))
    }
    assistantActionProcess.running = true
  }

  function dismissSuggestion() {
    if (suggestionDismissProcess.running || String((suggestion || {}).id || "") === "") return
    suggestionDismissProcess.command = [
      assistantControlPath, "--config", assistantConfigFile, "dismiss"
    ]
    suggestionDismissProcess.running = true
  }

  function submitSummon() {
    var request = summonPrompt.trim()
    if (request === "" || assistantActionProcess.running) return
    runAssistantAction("ask", request)
  }

  function setSuggestionHeld(held) {
    if (String((suggestion || {}).id || "") === "") return
    suggestionHoldWanted = held
    if (!suggestionHoldProcess.running) flushSuggestionHold()
  }

  function flushSuggestionHold() {
    suggestionHoldProcess.requestedHeld = suggestionHoldWanted
    suggestionHoldProcess.command = [
      assistantControlPath,
      "--config",
      assistantConfigFile,
      suggestionHoldWanted ? "hold-suggestion" : "release-suggestion"
    ]
    suggestionHoldProcess.running = true
  }

  function refreshAssistantSetup() {
    if (!assistantSetupProcess.running) assistantSetupProcess.running = true
  }

  function applyAssistantSetup(value) {
    if (!value || typeof value !== "object") return
    var config = value.config || {}
    assistantModelOptions = Array.isArray(value.modelChoices) ? value.modelChoices : []
    assistantHarnessOptions = Array.isArray(value.harnessChoices) ? value.harnessChoices : []
    learnedDismissalCount = Number(value.dismissedSuggestionCount || 0)
    selectedModelChoice = String(config.modelChoice || "")
    selectedConfidence = Number(config.minimumConfidence || 0.72).toFixed(2)
    selectedPreferredHarness = String(config.preferredHarness || "")
    selectedShareWindowTitle = config.shareWindowTitle === undefined
      ? true : Boolean(config.shareWindowTitle)
    selectedBlockedApps = Array.isArray(config.blockedApps) ? config.blockedApps : []
  }

  function saveAssistantSetup() {
    if (selectedModelChoice === "") {
      showAssistantError("Choose a local assistant model")
      return
    }
    if (selectedPreferredHarness === "") {
      showAssistantError("Choose a preferred harness")
      return
    }
    runAssistantAction("configure")
  }

  function currentAssistantModelLabel() {
    var selected = assistantModelOptions.find(function(option) {
      return String(option.value || "") === selectedModelChoice
    })
    return selected ? String(selected.label || selected.model || "Local model")
      : String(assistantStatus.modelLabel || assistantStatus.model || "Local model")
  }

  function preferredHarnessLabel() {
    var preferred = String(assistantStatus.preferredHarness || selectedPreferredHarness || "")
    var options = Array.isArray(assistantStatus.harnessChoices) ? assistantStatus.harnessChoices : []
    var selected = options.find(function(option) { return String(option.value || "") === preferred })
    return selected ? String(selected.label || "") : String(assistantStatus.preferredHarnessLabel || "")
  }

  function continueButtonLabel() {
    var label = preferredHarnessLabel()
    return label === "" ? "Continue" : "Continue in " + label
  }

  function dismissButtonLabel() {
    if (suggestionHoldWanted || (suggestion || {}).held === true) return "Dismiss · paused"
    var remaining = Math.max(0, Math.ceil(
      (Number((suggestion || {}).expiresAt || 0) * 1000 - clockMs) / 1000
    ))
    return "Dismiss · " + remaining + "s"
  }

  function applyAssistantStatus(value) {
    if (!value || typeof value !== "object") return
    assistantStatus = value
    if (value.suggestion && value.suggestion.id) suggestion = value.suggestion
    suggestionFile.reload()
  }

  function applySuggestion(text) {
    try {
      var value = JSON.parse(String(text || "{}"))
      var previousId = String((suggestion || {}).id || "")
      suggestion = value && typeof value === "object" ? value : ({})
      if (String((suggestion || {}).id || "") !== previousId) summonPrompt = ""
    } catch (error) {
      suggestion = ({})
    }
  }

  function applyVoxtypeState(text) {
    var value = String(text || "idle").trim().toLowerCase()
    voxtypeState = value === "recording" || value === "streaming" || value === "transcribing"
      ? value : "idle"
    if (voxtypeState === "idle") {
      dictationWaveform = []
      dictationPeak = 0
    }
  }

  function applyAudioFrame(line) {
    try {
      var value = JSON.parse(String(line || ""))
      if (typeof value.peak !== "number") return
      dictationPeak = Math.max(0, Math.min(1, value.peak))
      var samples = dictationWaveform.slice()
      samples.push(dictationPeak)
      while (samples.length > 42) samples.shift()
      dictationWaveform = samples
    } catch (error) {
      // The bridge can emit connection messages as well as audio frames.
    }
  }

  function assistantSuccessMessage(action) {
    if (action === "enable") return "Assistant enabled"
    if (action === "disable") return "Assistant disabled"
    if (action === "pause") return "Assistant paused"
    if (action === "resume") return "Assistant resumed"
    if (action === "dismiss") return "Suggestion dismissed"
    if (action === "copy") return "Suggestion copied"
    if (action === "remember") return "Playbook rule saved"
    if (action === "delegate") return "Handoff ready · path copied"
    if (action === "ask") return "Local response ready"
    if (action === "clear-feedback") return "Learned dismissals reset"
    if (action === "open-memory") return "Learned memory opened"
    if (action === "test-suggestion") return "Test suggestion shown"
    if (action === "restart") return "Assistant restarted"
    if (action === "edit-settings") return "Assistant settings opened"
    if (action === "configure") return "Assistant settings saved"
    return "Assistant updated"
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    clearFeedback()
    clearAssistantFeedback()
    refresh()
    if (settingsPage) refreshAssistantSetup()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Component.onCompleted: {
    refresh()
    suggestionRuleProcess.running = true
  }

  onSuggestionVisibleChanged: if (suggestionVisible) suggestionPlacementTimer.restart()
  onSuggestionWindowPreparedChanged: if (suggestionWindowPrepared && suggestionVisible) {
    suggestionPlacementTimer.restart()
  }

  Timer {
    interval: root.refreshInterval
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    id: actionRefresh
    interval: 700
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: feedbackClearTimer
    interval: 3500
    repeat: false
    onTriggered: {
      root.feedback = ""
      root.feedbackIsError = false
    }
  }

  Timer {
    interval: 1000
    running: root.suggestionVisible
    repeat: true
    onTriggered: root.clockMs = Date.now()
  }

  Timer {
    interval: 110
    running: root.voiceMode
    repeat: true
    onTriggered: root.voiceAnimationTick = (root.voiceAnimationTick + 1) % 4
  }

  Timer {
    id: assistantFeedbackTimer
    interval: 3500
    repeat: false
    onTriggered: {
      root.assistantFeedback = ""
      root.assistantFeedbackIsError = false
    }
  }

  Timer {
    id: cornerToastTimer
    interval: 3600
    repeat: false
    onTriggered: root.hideCornerToast()
  }

  Timer {
    id: cornerToastClearTimer
    interval: 220
    repeat: false
    onTriggered: {
      root.cornerToastTitle = ""
      root.cornerToastBody = ""
      root.cornerToastIsError = false
    }
  }

  Timer {
    id: assistantActionRefresh
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: suggestionPlacementTimer
    interval: 60
    repeat: false
    onTriggered: if (!suggestionPlacementProcess.running) suggestionPlacementProcess.running = true
  }

  FileView {
    id: suggestionFile
    path: root.suggestionPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applySuggestion(text())
    onFileChanged: reload()
  }

  FileView {
    id: voxtypeStateFile
    path: root.voxtypeStatePath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyVoxtypeState(text())
    onFileChanged: reload()
  }

  Process {
    id: dictationAudioBridge
    command: ["voxtype-audio-bridge"]
    running: root.dictationRecording && root.voiceMode
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) { root.applyAudioFrame(data) }
    }
    onRunningChanged: if (!running) {
      root.dictationWaveform = []
      root.dictationPeak = 0
    }
  }

  Process {
    id: statusProcess
    running: false
    command: [root.controlPath, "--config", root.configFile, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(String(text || ""))
          if (parsed && typeof parsed === "object") root.status = parsed
        } catch (e) {
          root.showError("Could not read runtime status")
        }
      }
    }
    stderr: StdioCollector { id: statusError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var details = String(statusError.text || "Could not read runtime status").trim()
        root.showError(details.length > 180 ? details.slice(0, 177) + "…" : details)
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    stdout: StdioCollector { id: actionOutput; waitForEnd: true }
    stderr: StdioCollector { id: actionError; waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode === 0) {
        var successMessage = "Runtime updated"
        if (root.pendingAction === "start") {
          successMessage = root.pendingProfile !== "" ? root.pendingProfile + " started" : "Local AI started"
        } else if (root.pendingAction === "stop") successMessage = "Local AI stopped"
        else if (root.pendingAction === "restart") successMessage = "Local AI restarted"
        root.showTransientFeedback(successMessage)
      } else {
        var details = String(actionError.text || actionOutput.text || "Runtime action failed").trim()
        root.showError(details.length > 180 ? details.slice(0, 177) + "…" : details)
      }
      root.pendingAction = ""
      root.pendingProfile = ""
      actionRefresh.restart()
    }
  }

  Process {
    id: copyProcess
    running: false
    onExited: function(exitCode) {
      if (exitCode === 0) root.showTransientFeedback("Endpoint copied")
      else root.showError("Could not copy endpoint")
    }
  }

  Process {
    id: openConfigProcess
    running: false
    onExited: function(exitCode) { if (exitCode !== 0) root.showError("Could not open config") }
  }

  Process {
    id: assistantStatusProcess
    running: false
    command: [root.assistantControlPath, "--config", root.assistantConfigFile, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.applyAssistantStatus(JSON.parse(String(text || "{}")))
        } catch (error) {
          root.showAssistantError("Could not read assistant status")
        }
      }
    }
    stderr: StdioCollector { id: assistantStatusError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var detail = String(assistantStatusError.text || "Could not read assistant status").trim()
        root.showAssistantError(detail.length > 180 ? detail.slice(0, 177) + "…" : detail)
      }
    }
  }

  Process {
    id: assistantSetupProcess
    running: false
    command: [root.assistantControlPath, "--config", root.assistantConfigFile, "setup-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.applyAssistantSetup(JSON.parse(String(text || "{}")))
        } catch (error) {
          root.showAssistantError("Could not read assistant settings")
        }
      }
    }
    stderr: StdioCollector { id: assistantSetupError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var detail = String(assistantSetupError.text || "Could not read assistant settings").trim()
        root.showAssistantError(detail.length > 180 ? detail.slice(0, 177) + "…" : detail)
      }
    }
  }

  Process {
    id: assistantActionProcess
    running: false
    stdout: StdioCollector { id: assistantActionOutput; waitForEnd: true }
    stderr: StdioCollector { id: assistantActionError; waitForEnd: true }
    onExited: function(exitCode) {
      root.assistantBusy = false
      var completedAction = root.assistantPendingAction
      if (exitCode === 0) {
        root.showAssistantFeedback(root.assistantSuccessMessage(completedAction))
        if (completedAction === "delegate") {
          var harness = root.preferredHarnessLabel()
          root.showCornerToast(
            harness === "" ? "Handoff ready" : "Opened " + harness,
            "SESSION.md path copied to clipboard",
            false
          )
        } else if (completedAction === "copy") {
          root.showCornerToast("Response copied", "Ready to paste", false)
        }
      } else {
        var detail = String(assistantActionError.text || assistantActionOutput.text || "Assistant action failed").trim()
        root.showAssistantError(detail.length > 220 ? detail.slice(0, 217) + "…" : detail)
        if (completedAction === "delegate" || completedAction === "copy") {
          root.showCornerToast(
            completedAction === "delegate" ? "Handoff failed" : "Copy failed",
            detail.length > 140 ? detail.slice(0, 137) + "…" : detail,
            true
          )
        }
      }
      if (exitCode === 0 && (completedAction === "configure"
          || completedAction === "clear-feedback")) {
        if (completedAction === "configure") root.settingsPage = false
        root.refreshAssistantSetup()
      }
      root.assistantPendingAction = ""
      assistantActionRefresh.restart()
      suggestionFile.reload()
    }
  }

  Process {
    id: suggestionDismissProcess
    running: false
    stderr: StdioCollector { id: suggestionDismissError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var detail = String(suggestionDismissError.text || "Could not dismiss Local AI").trim()
        root.showAssistantError(detail.length > 180 ? detail.slice(0, 177) + "…" : detail)
      }
      suggestionFile.reload()
    }
  }

  Process {
    id: suggestionRuleProcess
    running: false
    command: [root.assistantControlPath, "--config", root.assistantConfigFile, "prepare-window"]
    onExited: function(exitCode) { root.suggestionWindowPrepared = exitCode === 0 }
  }

  Process {
    id: suggestionPlacementProcess
    running: false
    command: [root.assistantControlPath, "--config", root.assistantConfigFile, "place-window"]
  }

  Process {
    id: suggestionHoldProcess
    property bool requestedHeld: false
    running: false
    onExited: function(exitCode) {
      root.suggestionHoldApplied = requestedHeld
      if (root.suggestionHoldWanted !== root.suggestionHoldApplied) {
        Qt.callLater(function() { root.flushSuggestionHold() })
      }
      suggestionFile.reload()
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function start(profile: string): string { root.runAction("start", profile); return "ok" }
    function stop(): string { root.runAction("stop", ""); return "ok" }
    function restart(): string { root.runAction("restart", ""); return "ok" }
    function enableAssistant(): string { root.runAssistantAction("enable"); return "ok" }
    function disableAssistant(): string { root.runAssistantAction("disable"); return "ok" }
    function pauseAssistant(): string { root.runAssistantAction("pause"); return "ok" }
    function resumeAssistant(): string { root.runAssistantAction("resume"); return "ok" }
    function status(): string { return root.stateLabel }
  }

  Component {
    id: voiceIndicatorComponent

    Item {
      Row {
        width: implicitWidth
        height: Style.space(14)
        anchors.centerIn: parent
        spacing: Style.space(2)

        Repeater {
          model: 4

          Rectangle {
            required property int index
            width: Style.space(3)
            height: root.voiceBarHeight(index)
            y: (parent.height - height) / 2
            radius: width / 2
            color: root.voiceActivityColor
            opacity: root.dictationRecording ? 1 : (root.voiceThinking ? 0.92 : 0.72)

            Behavior on height {
              NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
            }

            Behavior on opacity {
              NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
            }
          }
        }
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.voiceMode ? "" : "󰍛"
    iconComponent: root.voiceMode ? voiceIndicatorComponent : null
    tooltipText: root.voiceMode
      ? (root.dictationRecording ? "Local AI · Listening — release SUPER+A to send"
        : (root.assistantStatus.state === "thinking" ? "Local AI · Thinking…" : "Local AI · Transcribing…"))
      : "Local AI · Runtime " + root.stateLabel + " · Assistant " + root.assistantStateLabel
    active: root.running || (root.assistantActive && !root.assistantPaused)
    useActiveColor: false

    Rectangle {
      visible: !root.voiceMode
        && (root.running || root.assistantEnabled || root.failed || root.assistantFailed)
      width: root.running ? Style.space(5) : Style.space(4)
      height: width
      radius: width / 2
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: Style.space(2)
      anchors.bottomMargin: Style.space(2)
      color: root.failed || root.assistantFailed ? Color.urgent
        : (root.assistantPaused && !root.running ? root.dim : root.accent)
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.runAction(root.running ? "stop" : "start", "")
      else if (buttonCode === Qt.MiddleButton) root.runAction("restart", "")
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(
      contentColumn.implicitHeight,
      root.settingsPage ? Style.space(640) : Style.space(680)
    )

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: modelDropdown.popupOpen || harnessDropdown.popupOpen
        || sensitivityDropdown.popupOpen || appPicker.popupOpen
      onActivateRequested: root.refresh()
      onCloseRequested: root.close()

      WheelHandler {
        target: null
        enabled: panelContent.contentHeight > panelContent.height
          && !modelDropdown.popupOpen && !harnessDropdown.popupOpen
          && !sensitivityDropdown.popupOpen && !appPicker.popupOpen
        onWheel: event => {
          var delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 2
          var maximum = Math.max(0, panelContent.contentHeight - panelContent.height)
          panelContent.contentY = Math.max(0, Math.min(maximum, panelContent.contentY - delta))
          event.accepted = true
        }
      }

      Flickable {
        id: panelContent
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        bottomMargin: Style.space(12)
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

        Column {
          id: contentColumn
          width: panelContent.width
          spacing: Style.space(12)

          Item {
            width: parent.width
            implicitHeight: Math.max(titleBlock.implicitHeight, settingsButton.implicitHeight)

            Column {
              id: titleBlock
              anchors.left: parent.left
              anchors.right: settingsButton.left
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.settingsPage ? "Assistant settings" : "Local AI"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: !root.settingsPage
                text: (root.assistantEnabled ? "Assistant on" : "Assistant off")
                  + " · " + (root.running ? "Runtime running" : "Runtime stopped")
                color: root.assistantEnabled ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            PanelActionButton {
              id: settingsButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.settingsPage ? "󰁍" : "󰒓"
              tooltipText: root.settingsPage ? "Back" : "Assistant settings"
              foreground: root.foreground
              hoverColor: root.accent
              fontFamily: root.fontFamily
              bordered: true
              focusable: true
              onClicked: {
                root.settingsPage = !root.settingsPage
                panelContent.contentY = 0
                root.clearAssistantFeedback()
                if (root.settingsPage) root.refreshAssistantSetup()
                else root.refresh()
              }
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          Column {
            visible: !root.settingsPage
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              width: parent.width
              text: "ALWAYS-ON ASSISTANT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Toggle {
              width: parent.width
              label: "Always-on Assistant"
              description: !root.assistantStatus.configured
                ? "Open settings to choose a small local model"
                : root.currentAssistantModelLabel() + " · " + root.assistantStateLabel
              checked: root.assistantEnabled
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              enabled: root.assistantStatus.configured && !root.assistantBusy
              onClicked: root.runAssistantAction(root.assistantEnabled ? "disable" : "enable")
            }

            Text {
              visible: root.assistantFeedback !== "" || root.assistantFailed
              width: parent.width
              text: root.assistantFeedback !== ""
                ? root.assistantFeedback
                : String(root.assistantStatus.lastError || "")
              color: root.assistantFeedbackIsError || root.assistantFailed ? root.urgent : root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            PanelSeparator { width: parent.width; foreground: root.foreground }

            PanelSectionHeader {
              width: parent.width
              text: "LOCAL MODEL RUNTIME"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: Math.max(runtimeName.implicitHeight, runtimeState.implicitHeight)

              Text {
                id: runtimeName
                anchors.left: parent.left
                anchors.right: runtimeState.left
                anchors.rightMargin: Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                text: String(root.status.label || root.status.model || "No model running")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                id: runtimeState
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.stateLabel
                color: root.failed ? root.urgent : (root.running ? root.accent : root.dim)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Text {
              width: parent.width
              text: root.activeDetail()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Grid {
              id: profileGrid
              width: parent.width
              columns: Math.max(1, Math.min(3, (root.status.profiles || []).length))
              spacing: Style.spacing.md
              readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

              Repeater {
                model: root.status.profiles || []

                Button {
                  required property var modelData
                  width: profileGrid.cellWidth
                  text: root.profileTitle(modelData)
                  selected: root.status.profile === modelData.id
                  enabled: !root.busy && modelData.ready === true
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: root.runAction("start", modelData.id)
                }
              }
            }

            Text {
              visible: (root.status.profiles || []).length === 0
              width: parent.width
              text: "No runtime profiles configured"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md
              readonly property real cellWidth: (width - spacing) / 2

              Button {
                width: parent.cellWidth
                text: root.running ? "Stop runtime" : "Start " + String(root.status.defaultProfile || "default")
                enabled: !root.busy && (root.running || root.status.defaultProfile !== "")
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.runAction(root.running ? "stop" : "start", "")
              }

              Button {
                width: parent.cellWidth
                text: "Restart"
                enabled: !root.busy && root.running
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.runAction("restart", "")
              }
            }

            Row {
              width: parent.width

              Button {
                width: parent.width
                text: "Copy endpoint"
                enabled: String(root.status.endpoint || "") !== ""
                bordered: false
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                verticalPadding: Style.spacing.controlPaddingY
                onClicked: root.copyEndpoint()
              }
            }

            Text {
              visible: root.feedback !== ""
              width: parent.width
              text: root.feedback
              color: root.feedbackIsError ? root.urgent : root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }

          Column {
            visible: root.settingsPage
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              width: parent.width
              text: "MODEL"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Dropdown {
              id: modelDropdown
              width: parent.width
              label: "Assistant model"
              value: root.selectedModelChoice
              options: root.assistantModelOptions
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(value) { root.selectedModelChoice = value }
            }

            Text {
              visible: root.assistantModelOptions.length === 0
              width: parent.width
              text: "No compatible local model endpoint is currently available."
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            PanelSectionHeader {
              width: parent.width
              text: "HANDOFF"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Dropdown {
              id: harnessDropdown
              width: parent.width
              label: "Preferred harness"
              value: root.selectedPreferredHarness
              options: root.assistantHarnessOptions
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(value) { root.selectedPreferredHarness = value }
            }

            PanelSectionHeader {
              width: parent.width
              text: "SUGGESTIONS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Dropdown {
              id: sensitivityDropdown
              width: parent.width
              label: "Frequency"
              value: root.selectedConfidence
              options: root.confidenceOptions
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(value) { root.selectedConfidence = value }
            }

            Toggle {
              width: parent.width
              label: "Use window titles"
              description: "Share the filtered active-window title with the local model"
              checked: root.selectedShareWindowTitle
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.selectedShareWindowTitle = !root.selectedShareWindowTitle
            }

            MultiSelect {
              id: appPicker
              width: parent.width
              label: "Blocked apps"
              values: root.selectedBlockedApps
              optionsCommand: [root.assistantControlPath, "--config", root.assistantConfigFile, "apps"]
              placeholderText: "Search installed apps…"
              noSelectionText: "No extra apps blocked"
              emptyText: "No installed apps found"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onChanged: function(values) { root.selectedBlockedApps = values }
            }

            Text {
              width: parent.width
              text: "Password managers and sensitive window-title patterns stay protected automatically."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "Filtered app metadata → quiet local decision → every action needs your click"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md
              readonly property real cellWidth: (width - spacing) / 2

              Button {
                width: parent.cellWidth
                text: "View memory"
                iconText: "󰈙"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(7)
                verticalPadding: Style.space(5)
                bordered: true
                enabled: !root.assistantBusy
                onClicked: root.runAssistantAction("open-memory")
              }

              Button {
                width: parent.cellWidth
                text: "Reset · " + root.learnedDismissalCount
                iconText: "󰑓"
                foreground: root.dim
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(7)
                verticalPadding: Style.space(5)
                bordered: true
                enabled: !root.assistantBusy && root.learnedDismissalCount > 0
                onClicked: root.runAssistantAction("clear-feedback")
              }
            }

            Button {
              width: parent.width
              text: root.assistantBusy && root.assistantPendingAction === "configure" ? "Saving…" : "Save"
              iconText: root.assistantBusy && root.assistantPendingAction === "configure" ? "󰦖" : "✓"
              iconSpinning: root.assistantBusy && root.assistantPendingAction === "configure"
              foreground: root.accent
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: true
              enabled: !root.assistantBusy && root.selectedModelChoice !== ""
                && root.selectedPreferredHarness !== ""
              onClicked: root.saveAssistantSetup()
            }

            Button {
              width: parent.width
              text: "Open full Local AI config"
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              bordered: false
              enabled: !root.assistantBusy
              onClicked: root.openConfig()
            }

            Text {
              visible: root.assistantFeedback !== ""
              width: parent.width
              text: root.assistantFeedback
              color: root.assistantFeedbackIsError ? root.urgent : root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }

            Item { width: 1; height: Style.space(8) }
          }
        }
      }
    }
  }

  PanelWindow {
    id: cornerFeedbackWindow
    screen: root.hostWindow ? root.hostWindow.screen : null
    visible: root.cornerToastTitle !== ""

    WlrLayershell.namespace: "local-ai-feedback"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    mask: Region { item: cornerToastCard }

    BorderSurface {
      id: cornerToastCard
      width: Style.space(286)
      height: cornerToastContent.implicitHeight + Style.space(20)
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: Style.gapsOut + Style.space(8)
        + (root.bar && root.bar.position === "right" && root.hostWindow ? root.hostWindow.width : 0)
      anchors.bottomMargin: Style.gapsOut + Style.space(8)
        + (root.bar && root.bar.position === "bottom" && root.hostWindow ? root.hostWindow.height : 0)
      color: Color.notifications.background
      borderSpec: Border.surfaceSpec(
        "notifications",
        "border",
        root.cornerToastIsError ? root.urgent : Color.notifications.border,
        Math.max(1, Style.space(2))
      )
      radius: Style.cornerRadius
      opacity: root.cornerToastPresented ? 1 : 0
      scale: root.cornerToastPresented ? 1 : 0.96

      transform: Translate {
        y: root.cornerToastPresented ? 0 : Style.space(10)
        Behavior on y {
          NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
        }
      }

      Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
      }

      Behavior on scale {
        NumberAnimation { duration: 190; easing.type: Easing.OutBack }
      }

      Row {
        id: cornerToastContent
        x: Style.space(10)
        y: Style.space(10)
        width: parent.width - Style.space(20)
        spacing: Style.space(9)

        Rectangle {
          width: Style.space(24)
          height: width
          radius: width / 2
          color: {
            var tint = root.cornerToastIsError ? root.urgent : root.accent
            return Qt.rgba(tint.r, tint.g, tint.b, 0.16)
          }

          Text {
            anchors.centerIn: parent
            text: root.cornerToastIsError ? "!" : "✓"
            color: root.cornerToastIsError ? root.urgent : root.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
        }

        Column {
          width: parent.width - Style.space(33)
          spacing: Style.space(2)

          Text {
            width: parent.width
            text: root.cornerToastTitle
            color: Color.notifications.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            visible: root.cornerToastBody !== ""
            width: parent.width
            text: root.cornerToastBody
            color: Qt.darker(Color.notifications.text, 1.28)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  FloatingWindow {
    id: suggestionWindow
    visible: root.suggestionVisible && root.suggestionWindowPrepared && !root.voiceMode
    screen: root.hostWindow ? root.hostWindow.screen : null
    title: "Local AI Suggestion"
    implicitWidth: Style.space(340)
    implicitHeight: Style.space(320)
    minimumSize: Qt.size(Style.space(340), Style.space(320))
    maximumSize: minimumSize
    color: "transparent"
    onClosed: root.dismissSuggestion()
    onVisibleChanged: {
      if (visible) {
        root.suggestionPresented = false
        Qt.callLater(function() { root.suggestionPresented = true })
      } else {
        root.suggestionPresented = false
        root.suggestionHovered = false
        root.suggestionFocused = false
        suggestionFlick.contentY = 0
      }
    }

    BorderSurface {
      id: suggestionCard
      anchors.fill: parent
      color: Color.notifications.background
      borderSpec: Border.surfaceSpec("notifications", "border", Color.notifications.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      clip: true
      opacity: root.suggestionPresented ? 1 : 0
      scale: root.suggestionPresented ? 1 : 0.975

      transform: Translate {
        y: root.suggestionPresented ? 0 : Style.space(8)
        Behavior on y {
          NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
      }

      Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
      }

      Behavior on scale {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
      }

      HoverHandler {
        id: suggestionHover
        onHoveredChanged: {
          root.suggestionHovered = hovered
          root.setSuggestionHeld(hovered || suggestionCard.Window.active)
        }
      }

      Window.onActiveChanged: {
        root.suggestionFocused = Window.active
        root.setSuggestionHeld(suggestionHover.hovered || Window.active)
        if (Window.active) {
          Qt.callLater(function() {
            if (root.summonAwaitingInput) summonField.forceActiveFocus()
            else suggestionFlick.forceActiveFocus()
          })
        }
      }

      Flickable {
        id: suggestionFlick
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: actionFooter.top
        anchors.bottomMargin: Style.space(6)
        contentWidth: width
        contentHeight: suggestionContent.implicitHeight + Style.space(24)
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        activeFocusOnTab: true
        Keys.onPressed: function(event) {
          var maximum = Math.max(0, contentHeight - height)
          if (event.key === Qt.Key_Escape) root.dismissSuggestion()
          else if (event.key === Qt.Key_Up) contentY = Math.max(0, contentY - Style.space(36))
          else if (event.key === Qt.Key_Down) contentY = Math.min(maximum, contentY + Style.space(36))
          else if (event.key === Qt.Key_PageUp) contentY = Math.max(0, contentY - height * 0.75)
          else if (event.key === Qt.Key_PageDown) contentY = Math.min(maximum, contentY + height * 0.75)
          else return
          event.accepted = true
        }
        ScrollBar.vertical: ScrollBar {
          policy: root.suggestionInteracting && suggestionFlick.contentHeight > suggestionFlick.height
            ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }

        Column {
          id: suggestionContent
          x: Style.space(12)
          y: Style.space(12)
          width: suggestionFlick.width - Style.space(24)
          spacing: Style.space(8)

          Text {
            width: parent.width
            text: String(root.suggestion.title || "Suggested next step")
            color: Color.notifications.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            text: "Context · " + String(root.suggestion.observation || "Active desktop context")
            color: Qt.darker(Color.notifications.text, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }

          Text {
            visible: String(root.suggestion.body || "") !== ""
            width: parent.width
            text: String(root.suggestion.body || "")
              + ((root.suggestion || {}).streaming === true ? "  ▌" : "")
            color: Qt.darker(Color.notifications.text, 1.15)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            maximumLineCount: root.suggestionInteracting ? 1000 : 9
            elide: root.suggestionInteracting ? Text.ElideNone : Text.ElideRight
          }

          Item {
            visible: String(root.suggestion.copyText || root.suggestion.body || "") !== ""
              && root.suggestionInteracting
            width: parent.width
            height: visible ? copySuggestionButton.implicitHeight : 0

            Button {
              id: copySuggestionButton
              anchors.right: parent.right
              iconText: "󰆏"
              tooltipText: "Copy response"
              foreground: Qt.darker(Color.notifications.text, 1.2)
              accent: root.accent
              fontFamily: root.fontFamily
              iconSize: Style.font.bodySmall
              horizontalPadding: Style.space(6)
              verticalPadding: Style.space(4)
              focusable: true
              onClicked: root.runAssistantAction("copy")
            }
          }

          TextField {
            id: summonField
            visible: root.summonAwaitingInput
            width: parent.width
            text: root.summonPrompt
            placeholderText: "What do you need?"
            foreground: Color.notifications.text
            accent: root.accent
            font.family: root.fontFamily
            maximumLength: 2000
            onTextChanged: root.summonPrompt = text
            Keys.onReturnPressed: root.submitSummon()
            Keys.onEscapePressed: root.dismissSuggestion()
          }

        }
      }

      Column {
        id: actionFooter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        anchors.bottomMargin: Style.space(12)
        height: implicitHeight

        Row {
          id: summonActions
          visible: root.summonAwaitingInput
          width: parent.width
          spacing: Style.space(8)
          readonly property real cellWidth: (width - spacing) / 2

          Button {
            width: parent.cellWidth
            text: root.dismissButtonLabel()
            bordered: true
            foreground: Color.notifications.text
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.dismissSuggestion()
          }

          Button {
            width: parent.cellWidth
            text: root.assistantBusy && root.assistantPendingAction === "ask" ? "Thinking…" : "Ask"
            bordered: true
            foreground: root.accent
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            enabled: root.summonPrompt.trim() !== "" && !root.assistantBusy
            onClicked: root.submitSummon()
          }
        }

        Row {
          id: resultActions
          visible: !root.summonAwaitingInput
          width: parent.width
          spacing: Style.space(8)
          readonly property bool continueAvailable: root.assistantStatus.delegateAvailable
            && String(root.suggestion.body || root.suggestion.delegatePrompt || "") !== ""
          readonly property real cellWidth: continueAvailable ? (width - spacing) / 2 : width

          Button {
            width: parent.cellWidth
            text: root.dismissButtonLabel()
            bordered: true
            foreground: Color.notifications.text
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.dismissSuggestion()
          }

          Button {
            width: resultActions.cellWidth
            visible: resultActions.continueAvailable
            text: root.assistantBusy && root.assistantPendingAction === "delegate"
              ? "Preparing handoff…" : root.continueButtonLabel()
            bordered: true
            foreground: root.accent
            accent: root.accent
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            enabled: !root.assistantBusy
            onClicked: root.runAssistantAction("delegate")
          }
        }
      }
    }
  }

}
