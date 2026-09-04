import QtQuick

Item {
  id: root
  property int iconSize: 16
  property color color: "#ffffff"
  implicitWidth: iconSize
  implicitHeight: iconSize

  Text {
    anchors.centerIn: parent
    text: "󰴈"
    color: root.color
    font.pixelSize: root.iconSize
  }
}
