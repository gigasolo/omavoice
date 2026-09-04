import QtQuick
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  Image {
    anchors.fill: parent
    source: Qt.resolvedUrl("omavoice.png")
    sourceSize.width: Math.round(root.iconSize * Screen.devicePixelRatio)
    sourceSize.height: Math.round(root.iconSize * Screen.devicePixelRatio)
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    asynchronous: true
  }
}
