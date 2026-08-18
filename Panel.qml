import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
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
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string controlPath: decodeURIComponent(
    String(Qt.resolvedUrl("local-ai-control")).replace(/^file:\/\//, "")
  )
  readonly property string configFile: String(
    settings && settings.localConfigFile ? settings.localConfigFile : "~/.config/omarchy/local-ai.toml"
  )
  readonly property int refreshInterval: Math.max(5, Number(
    settings && settings.refreshIntervalSec ? settings.refreshIntervalSec : 10
  )) * 1000

  property var status: ({
    profile: "stopped", state: "inactive", label: "Stopped", detail: "Local runtime",
    model: "", variant: "", context: "", backend: "Local AI", endpoint: "",
    configFile: "", defaultProfile: "", profiles: []
  })
  property bool busy: false
  property string feedback: ""
  property bool cursorActive: false

  readonly property bool running: status.state === "active"
  readonly property bool failed: status.state === "failed"
  readonly property string stateLabel: busy ? "Switching…" : (running ? "Running" : (failed ? "Failed" : "Stopped"))

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
  }

  function runAction(action, profileId) {
    if (actionProcess.running) return
    busy = true
    feedback = ""
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

  onOpenedChanged: if (opened) {
    cursorActive = false
    feedback = ""
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
          root.feedback = "Could not read runtime status"
        }
      }
    }
  }

  Process {
    id: actionProcess
    running: false
    onExited: function(exitCode) {
      root.busy = false
      root.feedback = exitCode === 0 ? "" : "Runtime action failed"
      actionRefresh.restart()
    }
  }

  Process {
    id: copyProcess
    running: false
    onExited: function(exitCode) { root.feedback = exitCode === 0 ? "Endpoint copied" : "Could not copy endpoint" }
  }

  Process {
    id: openConfigProcess
    running: false
    onExited: function(exitCode) { if (exitCode !== 0) root.feedback = "Could not open config" }
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
    function status(): string { return root.stateLabel }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: ""
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: "󰍛"
          color: root.foreground
          opacity: root.running ? 1.0 : 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }
        Rectangle {
          visible: root.running || root.failed
          width: Style.space(4)
          height: width
          radius: width / 2
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: Style.space(2)
          anchors.bottomMargin: Style.space(2)
          color: root.failed ? Color.urgent : root.accent
        }
      }
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
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onActivateRequested: root.refresh()
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.runAction("restart", "")
        if (t === "s" || t === "S") root.runAction(root.running ? "stop" : "start", "")
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
            text: "SHORTCUTS"
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
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
          }
        }
      }
    }
  }
}
