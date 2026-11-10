import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "aldo.display-mode"
  ipcTarget: "aldo.display-mode"

  readonly property string script: String(Qt.resolvedUrl("display-mode")).replace(/^file:\/\//, "")
  readonly property string duplicateStrategy: setting("duplicate", "common") === "external" ? "external" : "common"

  readonly property string glyphLaptop: String.fromCodePoint(0xF0322)
  readonly property string glyphMonitor: String.fromCodePoint(0xF0379)
  readonly property string glyphMonitors: String.fromCodePoint(0xF037A)

  readonly property var modes: [
    { id: "internal", glyphs: [glyphLaptop] },
    { id: "duplicate", glyphs: [glyphMonitors] },
    { id: "extend", glyphs: [glyphLaptop, glyphMonitor] },
    { id: "external", glyphs: [glyphMonitor] }
  ]

  property string currentMode: "internal"
  property bool hasInternal: true
  property bool hasExternal: false
  property int cursor: 0

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function modeIndex(id) {
    for (var i = 0; i < modes.length; i++) if (modes[i].id === id) return i
    return 0
  }

  function available(id) {
    if (id === "internal") return hasInternal
    return hasInternal && hasExternal
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function updateStatus(raw) {
    try {
      var value = JSON.parse(String(raw || ""))
      if (!value || typeof value !== "object") return
      if (modeIndex(String(value.mode)) >= 0) currentMode = modes[modeIndex(String(value.mode))].id
      hasInternal = value.hasInternal === true
      hasExternal = value.hasExternal === true
    } catch (e) {
    }
  }

  function moveCursor(delta) {
    cursor = Math.max(0, Math.min(modes.length - 1, cursor + delta))
  }

  function applyMode(index) {
    if (index < 0 || index >= modes.length) return
    var id = modes[index].id
    if (!available(id)) return
    cursor = index
    close()
    Quickshell.execDetached([script, "set", id, duplicateStrategy])
    settle.restart()
  }

  onOpenedChanged: {
    if (opened) {
      cursor = modeIndex(currentMode)
      refresh()
    }
  }

  Component.onCompleted: refresh()

  Connections {
    target: Quickshell
    function onScreensChanged() { settle.restart() }
  }

  Timer {
    id: settle
    interval: 1200
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: [root.script, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.updateStatus(text)
        if (root.opened && !panelCursorMoved.moved) root.cursor = root.modeIndex(root.currentMode)
      }
    }
  }

  QtObject {
    id: panelCursorMoved
    property bool moved: false
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.currentMode === "internal" ? root.glyphLaptop
      : root.currentMode === "external" ? root.glyphMonitor
      : root.glyphMonitors
    tooltipText: strings.t("tooltip") + " · " + strings.t("mode." + root.currentMode)
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    onOpenChanged: panelCursorMoved.moved = false

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: cards.implicitHeight

      onMoveRequested: function(dx, dy) {
        panelCursorMoved.moved = true
        root.moveCursor(dx !== 0 ? dx : dy)
      }
      onActivateRequested: root.applyMode(root.cursor)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text, modifiers) {
        var n = parseInt(text, 10)
        if (n >= 1 && n <= root.modes.length) root.applyMode(n - 1)
      }

      Row {
        id: cards
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(8)

        readonly property real cellWidth: (width - spacing * (root.modes.length - 1)) / root.modes.length

        Repeater {
          model: root.modes

          Rectangle {
            id: card
            required property var modelData
            required property int index

            readonly property bool usable: root.available(modelData.id)
            readonly property bool current: root.currentMode === modelData.id
            readonly property bool hot: usable && root.cursor === index
            readonly property color foreground: root.bar ? root.bar.foreground : Commons.Color.foreground

            width: cards.cellWidth
            implicitHeight: body.implicitHeight + Style.space(18) * 2
            radius: Style.cornerRadius
            opacity: usable ? 1 : 0.35

            color: area.pressed && usable ? Style.pressedFillFor(foreground, Commons.Color.accent)
              : hot ? Style.hoverFillFor(foreground, Commons.Color.accent)
              : current ? Style.selectedFillFor(foreground, Commons.Color.accent)
              : Style.normalFillFor(foreground, Commons.Color.accent)
            border.width: hot ? Math.max(1, Style.hoverBorderWidth) : (current ? Math.max(1, Style.normalBorderWidth) : Style.normalBorderWidth)
            border.color: hot ? Style.selectedBorderFor(foreground, Commons.Color.accent)
              : current ? Style.selectedBorderFor(Commons.Color.accent, Commons.Color.accent)
              : Style.normalBorderFor(foreground, Commons.Color.accent)

            scale: area.pressed && usable ? 0.97 : 1
            Behavior on color { ColorAnimation { duration: Style.duration(120) } }
            Behavior on scale {
              NumberAnimation {
                duration: Style.duration(160)
                easing.type: Easing.Bezier
                easing.bezierCurve: Style.easeOut
              }
            }

            Column {
              id: body
              anchors.centerIn: parent
              width: parent.width - Style.space(8) * 2
              spacing: Style.space(10)

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(4)

                Repeater {
                  model: card.modelData.glyphs
                  Text {
                    required property string modelData
                    textFormat: Text.PlainText
                    text: modelData
                    color: card.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.displayLarge
                  }
                }
              }

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: strings.t("mode." + card.modelData.id)
                color: card.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: card.current
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                height: Math.ceil(labelMetrics.height * 2) + Style.space(2)

                FontMetrics {
                  id: labelMetrics
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            MouseArea {
              id: area
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: card.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
              onEntered: if (card.usable) { panelCursorMoved.moved = true; root.cursor = card.index }
              onClicked: root.applyMode(card.index)
            }
          }
        }
      }
    }
  }
}
