import QtQuick
import Quickshell.Io

Item {
  id: root

  property var shell: null

  readonly property string script: String(Qt.resolvedUrl("display-mode")).replace(/^file:\/\//, "")

  Process {
    id: watcher
    command: [root.script, "watch"]
    running: true
    onExited: restart.start()
  }

  Timer {
    id: restart
    interval: 3000
    onTriggered: watcher.running = true
  }
}
