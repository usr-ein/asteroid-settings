/*
 * Copyright (C) 2026 Samuel Prevost <usr_ein@pm.me>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.9
import org.asteroid.controls 1.0
import org.asteroid.settings 1.0
import Nemo.DBus 2.0

// The TicWatch Pro 3 Ultra's second screen: the monochrome layer that shows
// the time while the main display is off, lit from behind. By day a tilt
// lights it for a few seconds; at night it stays on at the night brightness,
// and a tilt turns it up to the tilt brightness. The sonic-fstn service on the
// watch does the work (sonic-screwdriver, docs/prd/secondary_display.md);
// this page only reads and sets its four values over the system bus.
// The qsTr() strings are new in this fork and have no translations yet.
Item {
    id: page

    // Mobvoi's 18 presets, as RGB332 bytes, in their picker's order.
    readonly property var presets: [255, 251, 31, 83, 59, 151, 147, 26, 30,
                                    159, 155, 224, 254, 250, 248, 244, 242, 175]

    property int colour: 255
    property int nightLevel: 8
    property int tiltLevel: 60
    property bool nightMode: true
    property bool loaded: false
    property string status: ""
    readonly property bool online: fstn.status === DBusInterface.Available

    TiltToWake { id: tiltToWake }

    DBusInterface {
        id: fstn
        bus: DBus.SystemBus
        service: "org.sonicscrewdriver.Fstn"
        path: "/org/sonicscrewdriver/Fstn"
        iface: "org.sonicscrewdriver.Fstn"
        watchServiceStatus: true
        onStatusChanged: if (status === DBusInterface.Available) page.load()
    }

    // RGB332 to the swatch's tint, as Mobvoi's picker draws it.
    function tint(c) {
        if (c === 255)
            return "#ffffff"
        var r = (c >> 5) & 7, g = (c >> 2) & 7, b = c & 3
        return Qt.rgba(r * 34 / 255, g * 34 / 255, b * 68 / 255, 1)
    }

    Component.onCompleted: if (page.online) page.load()

    function load() {
        fstn.typedCall("Get", [], function (c, night, tilt, mode) {
            page.colour = c
            page.nightLevel = night
            page.tiltLevel = tilt
            page.nightMode = mode
            page.loaded = true
        }, function (error, message) {
            console.warn("SecondScreenPage: Get failed: " + message)
        })
        fstn.typedCall("Status", [], function (s) { page.status = s })
    }

    // The selectors change step by step while dragged: send once they rest.
    Timer {
        id: saveTimer
        interval: 300
        onTriggered: fstn.typedCall("Set", [
            { "type": "y", "value": page.colour },
            { "type": "y", "value": page.nightLevel },
            { "type": "y", "value": page.tiltLevel },
            { "type": "b", "value": page.nightMode }
        ], function () {
            fstn.typedCall("Status", [], function (s) { page.status = s })
        }, function (error, message) {
            console.warn("SecondScreenPage: Set failed: " + message)
        })
    }

    function save() {
        if (page.loaded)
            saveTimer.restart()
    }

    property string rowHeight: Dims.h(25)

    Flickable {
        anchors.fill: parent
        anchors.topMargin: Dims.l(15)
        anchors.bottomMargin: Dims.l(15)
        contentHeight: contentColumn.implicitHeight

        Column {
            id: contentColumn
            width: parent.width

            Label {
                width: parent.width
                visible: !page.online
                text: qsTr("The second screen's service isn't running.")
                font.pixelSize: Dims.l(6)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Label {
                width: parent.width
                height: Dims.l(10)
                visible: page.online && page.status !== ""
                text: page.status
                font.pixelSize: Dims.l(5)
                opacity: 0.7
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
            }

            // A tilt either wakes the main display or lights this screen: with
            // tilt-to-wake on, the watch's sensor hub leaves tilts alone.
            Label {
                width: parent.width
                visible: tiltToWake.enabled
                text: qsTr("Tilt-to-wake is on, so a tilt wakes the main display instead of lighting this screen.")
                font.pixelSize: Dims.l(5)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            LabeledActionButton {
                width: parent.width
                height: rowHeight
                visible: tiltToWake.enabled
                text: qsTr("Turn tilt-to-wake off")
                icon: "ios-checkmark-circle-outline"
                onClicked: function() { tiltToWake.enabled = false }
            }

            Label {
                width: parent.width
                height: Dims.l(12)
                text: qsTr("Colour")
                font.pixelSize: Dims.l(6)
                verticalAlignment: Text.AlignBottom
                horizontalAlignment: Text.AlignHCenter
            }

            Grid {
                id: swatches
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 6
                spacing: Dims.l(2)
                opacity: page.online ? 1.0 : 0.4
                Repeater {
                    model: page.presets
                    Rectangle {
                        width: Dims.l(10)
                        height: width
                        radius: width / 2
                        color: page.tint(modelData)
                        border.width: modelData === page.colour ? Dims.l(1.2) : 0
                        border.color: "#ffffff"
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Dims.l(1)
                            enabled: page.online
                            onClicked: {
                                page.colour = modelData
                                page.save()
                            }
                        }
                    }
                }
            }

            Item { width: parent.width; height: Dims.l(4) }

            Label {
                width: parent.width
                height: Dims.l(12)
                text: qsTr("Night brightness")
                font.pixelSize: Dims.l(6)
                verticalAlignment: Text.AlignBottom
                horizontalAlignment: Text.AlignHCenter
            }

            IntSelector {
                width: parent.width
                height: rowHeight
                min: 2
                max: 60
                stepSize: 2
                unitMarker: ""
                enabled: page.online
                value: page.nightLevel
                onValueChanged: if (value !== page.nightLevel) { page.nightLevel = value; page.save() }
            }

            Label {
                width: parent.width
                height: Dims.l(12)
                text: qsTr("Tilt brightness")
                font.pixelSize: Dims.l(6)
                verticalAlignment: Text.AlignBottom
                horizontalAlignment: Text.AlignHCenter
            }

            IntSelector {
                width: parent.width
                height: rowHeight
                min: 20
                max: 150
                stepSize: 10
                unitMarker: ""
                enabled: page.online
                value: page.tiltLevel
                onValueChanged: if (value !== page.tiltLevel) { page.tiltLevel = value; page.save() }
            }

            RowSeparator {}

            LabeledSwitch {
                width: parent.width
                height: rowHeight
                text: qsTr("Lit at night")
                enabled: page.online
                checked: page.nightMode
                onCheckedChanged: if (checked !== page.nightMode) { page.nightMode = checked; page.save() }
            }

            Label {
                width: parent.width
                text: qsTr("From sunset to sunrise. The second screen shows while Always on Display is off.")
                font.pixelSize: Dims.l(5)
                opacity: 0.7
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Item { width: parent.width; height: Dims.l(10) }
        }
    }

    PageHeader {
        id: title
        text: qsTr("Second screen")
    }
}
