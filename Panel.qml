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
  readonly property string copilotControlPath: decodeURIComponent(
    String(Qt.resolvedUrl("local-ai-copilot")).replace(/^file:\/\//, "")
  )
  readonly property string configFile: String(
    settings && settings.localConfigFile ? settings.localConfigFile : "~/.config/omarchy/local-ai.toml"
  )
  readonly property int refreshInterval: Math.max(5, Number(
    settings && settings.refreshIntervalSec ? settings.refreshIntervalSec : 10
  )) * 1000
  readonly property string copilotConfigFile: String(
    settings && settings.copilotConfigFile
      ? settings.copilotConfigFile
      : "~/.config/omarchy/local-ai-copilot.toml"
  )
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string defaultSuggestionPath: home + "/.local/state/omarchy/local-ai-copilot/suggestion.json"
  readonly property string suggestionPath: String(copilotStatus.suggestionFile || defaultSuggestionPath)
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
  property var copilotStatus: ({
    configured: false, configError: "", enabled: false, active: false, paused: false,
    state: "disabled", model: "auto", endpoint: "", lastError: "",
    suggestionFile: "", playbookFile: "", delegateAvailable: false,
    privacy: { windowTitle: true, screenshots: false, denyRules: 0 }
  })
  property var suggestion: ({})
  property bool copilotBusy: false
  property string copilotFeedback: ""
  property bool copilotFeedbackIsError: false
  property string copilotPendingAction: ""
  property double clockMs: Date.now()

  readonly property bool running: status.state === "active"
  readonly property bool failed: status.state === "failed"
  readonly property string stateLabel: busy ? "Switching…" : (running ? "Running" : (failed ? "Failed" : "Stopped"))
  readonly property bool copilotEnabled: copilotStatus.enabled === true
  readonly property bool copilotActive: copilotStatus.active === true
  readonly property bool copilotPaused: copilotStatus.paused === true
  readonly property bool copilotFailed: copilotStatus.state === "error"
    || String(copilotStatus.lastError || "") !== ""
  readonly property bool suggestionVisible: String((suggestion || {}).id || "") !== ""
    && Number((suggestion || {}).expiresAt || 0) * 1000 > clockMs
  readonly property string copilotStateLabel: {
    if (copilotBusy) return "Updating…"
    if (!copilotStatus.configured) return "Setup needed"
    if (!copilotEnabled) return "Off"
    if (copilotPaused) return "Paused"
    if (copilotStatus.state === "thinking") return "Thinking…"
    if (copilotStatus.state === "suggesting") return "Suggestion ready"
    if (copilotFailed) return "Needs attention"
    if (copilotActive) return "Watching"
    return "Waiting"
  }

  function profileTitle(profile) {
    if (!profile) return ""
    return String(profile.label || profile.id || "")
  }

  function activeDetail() {
    var parts = []
    if (status.label && status.label !== status.model) parts.push(String(status.label))
    if (status.variant) parts.push(String(status.variant))
    if (status.context) parts.push(String(status.context) + " context")
    return parts.length > 0 ? parts.join(" · ") : String(status.detail || "Local runtime")
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
    if (!copilotStatusProcess.running) copilotStatusProcess.running = true
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

  function clearCopilotFeedback() {
    copilotFeedbackTimer.stop()
    copilotFeedback = ""
    copilotFeedbackIsError = false
  }

  function showCopilotFeedback(message) {
    copilotFeedback = message
    copilotFeedbackIsError = false
    copilotFeedbackTimer.restart()
  }

  function showCopilotError(message) {
    copilotFeedback = message
    copilotFeedbackIsError = true
    copilotFeedbackTimer.stop()
  }

  function runCopilotAction(action) {
    if (copilotActionProcess.running) return
    copilotBusy = true
    copilotPendingAction = action
    clearCopilotFeedback()
    copilotActionProcess.command = [copilotControlPath, "--config", copilotConfigFile, action]
    copilotActionProcess.running = true
  }

  function applyCopilotStatus(value) {
    if (!value || typeof value !== "object") return
    copilotStatus = value
    if (value.suggestion && value.suggestion.id) suggestion = value.suggestion
    suggestionFile.reload()
  }

  function applySuggestion(text) {
    try {
      var value = JSON.parse(String(text || "{}"))
      suggestion = value && typeof value === "object" ? value : ({})
    } catch (error) {
      suggestion = ({})
    }
  }

  function copilotSuccessMessage(action) {
    if (action === "enable") return "Copilot enabled"
    if (action === "disable") return "Copilot disabled"
    if (action === "pause") return "Copilot paused"
    if (action === "resume") return "Copilot resumed"
    if (action === "dismiss") return "Suggestion dismissed"
    if (action === "copy") return "Suggestion copied"
    if (action === "remember") return "Playbook rule saved"
    if (action === "delegate") return "Task opened in the heavy harness"
    if (action === "test-suggestion") return "Test suggestion shown"
    if (action === "restart") return "Copilot restarted"
    if (action === "edit-settings") return "Copilot settings opened"
    return "Copilot updated"
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    clearFeedback()
    clearCopilotFeedback()
    refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Component.onCompleted: refresh()

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
    id: copilotFeedbackTimer
    interval: 3500
    repeat: false
    onTriggered: {
      root.copilotFeedback = ""
      root.copilotFeedbackIsError = false
    }
  }

  Timer {
    id: copilotActionRefresh
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  FileView {
    id: suggestionFile
    path: root.suggestionPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applySuggestion(text())
    onFileChanged: reload()
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
    id: copilotStatusProcess
    running: false
    command: [root.copilotControlPath, "--config", root.copilotConfigFile, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.applyCopilotStatus(JSON.parse(String(text || "{}")))
        } catch (error) {
          root.showCopilotError("Could not read Copilot status")
        }
      }
    }
    stderr: StdioCollector { id: copilotStatusError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var detail = String(copilotStatusError.text || "Could not read Copilot status").trim()
        root.showCopilotError(detail.length > 180 ? detail.slice(0, 177) + "…" : detail)
      }
    }
  }

  Process {
    id: copilotActionProcess
    running: false
    stdout: StdioCollector { id: copilotActionOutput; waitForEnd: true }
    stderr: StdioCollector { id: copilotActionError; waitForEnd: true }
    onExited: function(exitCode) {
      root.copilotBusy = false
      if (exitCode === 0) root.showCopilotFeedback(root.copilotSuccessMessage(root.copilotPendingAction))
      else {
        var detail = String(copilotActionError.text || copilotActionOutput.text || "Copilot action failed").trim()
        root.showCopilotError(detail.length > 220 ? detail.slice(0, 217) + "…" : detail)
      }
      root.copilotPendingAction = ""
      copilotActionRefresh.restart()
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
    function enableCopilot(): string { root.runCopilotAction("enable"); return "ok" }
    function disableCopilot(): string { root.runCopilotAction("disable"); return "ok" }
    function pauseCopilot(): string { root.runCopilotAction("pause"); return "ok" }
    function resumeCopilot(): string { root.runCopilotAction("resume"); return "ok" }
    function status(): string { return root.stateLabel }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰍛"
    tooltipText: "Local AI · Runtime " + root.stateLabel + " · Copilot " + root.copilotStateLabel
    active: root.running || (root.copilotActive && !root.copilotPaused)
    useActiveColor: false

    Rectangle {
      visible: root.running || root.copilotEnabled || root.failed || root.copilotFailed
      width: root.running ? Style.space(5) : Style.space(4)
      height: width
      radius: width / 2
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: Style.space(2)
      anchors.bottomMargin: Style.space(2)
      color: root.failed || root.copilotFailed ? Color.urgent
        : (root.copilotPaused && !root.running ? root.dim : root.accent)
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
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.refresh()
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.runAction("restart", "")
        if (t === "s" || t === "S") root.runAction(root.running ? "stop" : "start", "")
        if (t === "c" || t === "C") root.runCopilotAction(root.copilotEnabled ? "disable" : "enable")
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Local AI"
            meta: String(root.status.backend || "LOCAL RUNTIME").toUpperCase()
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: "󰍛"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(activeName.implicitHeight, activeState.implicitHeight)

            Text {
              id: activeName
              anchors.left: parent.left
              anchors.right: activeState.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              text: String(root.status.model || root.status.label || "Stopped")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              id: activeState
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.stateLabel
              color: root.failed ? Color.urgent : (root.running ? root.foreground : root.dim)
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

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            width: parent.width
            text: "RUNTIME PROFILES"
            foreground: root.foreground
            fontFamily: root.fontFamily
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

          Text {
            visible: (root.status.profiles || []).length > 0
            width: parent.width
            text: (root.status.profiles || []).length + " profiles · "
              + (root.status.profiles || []).filter(function(profile) { return profile.ready === true }).length
              + " ready"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }

          Row {
            width: parent.width
            spacing: Style.spacing.md
            readonly property real cellWidth: (width - spacing) / 2

            Button {
              width: parent.cellWidth
              text: root.running ? "Stop" : "Start " + String(root.status.defaultProfile || "default")
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

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            width: parent.width
            text: "ALWAYS-ON COPILOT"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(copilotName.implicitHeight, copilotState.implicitHeight)

            Text {
              id: copilotName
              anchors.left: parent.left
              anchors.right: copilotState.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              text: root.copilotActive ? "Proactive local observer" : "Optional proactive suggestions"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              id: copilotState
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.copilotStateLabel
              color: root.copilotFailed ? root.urgent
                : (root.copilotActive && !root.copilotPaused ? root.foreground : root.dim)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            width: parent.width
            text: !root.copilotStatus.configured
              ? String(root.copilotStatus.configError || "Create the machine-local Copilot settings")
              : String(root.copilotStatus.model || "auto") + " · "
                + String(root.copilotStatus.endpoint || "local endpoint")
            color: root.copilotFailed ? root.urgent : root.dim
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
              text: root.copilotEnabled ? "Turn Copilot off" : "Turn Copilot on"
              enabled: !root.copilotBusy && root.copilotStatus.configured
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.runCopilotAction(root.copilotEnabled ? "disable" : "enable")
            }

            Button {
              width: parent.cellWidth
              text: root.copilotPaused ? "Resume" : "Pause"
              enabled: !root.copilotBusy && root.copilotEnabled
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.runCopilotAction(root.copilotPaused ? "resume" : "pause")
            }
          }

          Grid {
            width: parent.width
            columns: 2
            spacing: Style.spacing.md
            readonly property real cellWidth: (width - spacing) / 2

            Button {
              width: parent.cellWidth
              text: root.copilotStatus.configured ? "Copilot settings" : "Set up Copilot"
              enabled: !root.copilotBusy
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.runCopilotAction("edit-settings")
            }

            Button {
              width: parent.cellWidth
              text: "Edit playbook"
              enabled: !root.copilotBusy && root.copilotStatus.configured
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.runCopilotAction("open-playbook")
            }

            Button {
              width: parent.cellWidth
              text: "Test suggestion"
              enabled: !root.copilotBusy
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.runCopilotAction("test-suggestion")
            }

            Button {
              width: parent.cellWidth
              text: "Restart Copilot"
              enabled: !root.copilotBusy && root.copilotEnabled
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.runCopilotAction("restart")
            }
          }

          Text {
            width: parent.width
            text: "Window metadata only · no screenshots · no autonomous tools · isolated Pi session"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: root.copilotFeedback !== ""
              ? root.copilotFeedback
              : String(root.copilotStatus.lastError || "")
            visible: text !== ""
            color: root.copilotFeedbackIsError || root.copilotFailed ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            width: parent.width
            text: "RUNTIME SHORTCUTS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            width: parent.width
            spacing: Style.spacing.md
            readonly property real cellWidth: (width - spacing) / 2

            Button {
              width: parent.cellWidth
              text: "Copy URL"
              enabled: String(root.status.endpoint || "") !== ""
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.copyEndpoint()
            }

            Button {
              width: parent.cellWidth
              text: "Edit profiles"
              enabled: String(root.status.configFile || root.configFile) !== ""
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              verticalPadding: Style.spacing.controlPaddingY
              onClicked: root.openConfig()
            }
          }

          Text {
            width: parent.width
            text: root.feedback !== "" ? root.feedback : String(root.status.endpoint || "")
            color: root.feedbackIsError ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
          }
        }
      }
    }
  }

  PanelWindow {
    id: suggestionWindow
    visible: root.suggestionVisible
    screen: root.hostWindow ? root.hostWindow.screen : null
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "local-ai-copilot-suggestion"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    mask: Region { item: suggestionCard }

    BorderSurface {
      id: suggestionCard
      width: Math.min(Style.space(410), suggestionWindow.width - Style.gapsOut * 2)
      implicitHeight: suggestionContent.implicitHeight + borderTop + borderBottom + Style.space(24)
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: Style.gapsOut + (root.bar && root.bar.position === "right" ? root.bar.barSize : 0)
      anchors.bottomMargin: Style.gapsOut + (root.bar && root.bar.position === "bottom" ? root.bar.barSize : 0)
      color: Color.notifications.background
      borderSpec: Border.surfaceSpec("notifications", "border", Color.notifications.border, Math.max(1, Style.space(2)))
      radius: Style.cornerRadius
      clip: true

      Column {
        id: suggestionContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Style.space(12)
        spacing: Style.space(8)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "󰚩"
            color: Color.notifications.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.icon
          }

          Text {
            width: parent.width - Style.space(34)
            text: String(root.suggestion.title || "Local AI Copilot")
            color: Color.notifications.text
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }
        }

        Text {
          width: parent.width
          text: String(root.suggestion.body || "")
          color: Qt.darker(Color.notifications.text, 1.15)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          maximumLineCount: 4
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          text: String((root.suggestion.context || {}).appId || "Desktop")
            + " · " + Math.round(Number(root.suggestion.confidence || 0) * 100) + "%"
          color: Qt.darker(Color.notifications.text, 1.45)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Grid {
          width: parent.width
          columns: 2
          spacing: Style.space(8)
          readonly property real cellWidth: (width - spacing) / 2

          Button {
            width: parent.cellWidth
            text: "Dismiss"
            bordered: true
            foreground: Color.notifications.text
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.runCopilotAction("dismiss")
          }

          Button {
            width: parent.cellWidth
            text: "Copy draft"
            bordered: true
            foreground: Color.notifications.text
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.runCopilotAction("copy")
          }

          Button {
            width: parent.cellWidth
            text: "Remember"
            bordered: true
            foreground: Color.notifications.text
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.runCopilotAction("remember")
          }

          Button {
            width: parent.cellWidth
            visible: root.copilotStatus.delegateAvailable && String(root.suggestion.delegatePrompt || "") !== ""
            text: "Delegate…"
            bordered: true
            foreground: Color.notifications.text
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            verticalPadding: Style.spacing.controlPaddingY
            onClicked: root.runCopilotAction("delegate")
          }
        }
      }
    }
  }
}
