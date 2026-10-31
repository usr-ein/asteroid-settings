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
import Connman 0.2

// How the watch reaches the internet: Wi-Fi, the phone's hotspot over
// classic Bluetooth, or nothing (see NetworkMode.qml); whether classic
// Bluetooth is on; and the state of each link (see PhoneLink.qml).
// The qsTr() strings are new in this fork and have no translations yet; the
// qsTrId() ones reuse the app's.
Item {
    id: page

    readonly property var manager: managerFactory.instance

    NetworkMode { id: networkMode }

    PhoneLink {
        id: phoneLink
        hotspotServicePath: networkMode.hotspot.path
    }

    NetworkManagerFactory { id: managerFactory }

    function modeIcon(mode, selected) {
        if (mode === "wifi")
            return selected && networkMode.wifi.connected ? "ios-wifi" : "ios-wifi-outline"
        if (mode === "hotspot")
            return selected && networkMode.hotspot.connected ? "ios-link" : "ios-link-outline"
        return "sonic/ios-globe-off"
    }

    function internetText() {
        var state = manager ? manager.state : ""
        if (state === "online")
            return qsTr("Online")
        if (state === "ready")
            return qsTr("Ready")
        if (state === "offline")
            return qsTr("Offline mode")
        return qsTr("None")
    }

    function addressesText() {
        var lines = []
        var services = [manager ? manager.connectedWifi : null,
                        networkMode.hotspotPresent ? networkMode.hotspot : null]
        for (var i = 0; i < services.length; i++) {
            var service = services[i]
            if (!service || !service.connected)
                continue
            if (service.ipv4 && service.ipv4.Address)
                lines.push(service.ipv4.Address)
            if (service.ipv6 && service.ipv6.Address)
                lines.push(service.ipv6.Address)
        }
        return lines.length > 0 ? lines.join("\n") : qsTr("None")
    }

    function wifiText() {
        if (!networkMode.wifi.powered)
            return qsTrId("id-off")
        var service = manager ? manager.connectedWifi : null
        if (service && service.connected)
            return qsTr("Connected to %1").arg(service.name)
        return qsTr("On, not connected")
    }

    function bluetoothText() {
        if (!phoneLink.adapterPowered)
            return qsTrId("id-off")
        return networkMode.classicBluetooth ? qsTr("On, LE and classic") : qsTr("On, LE only")
    }

    function phoneText() {
        if (phoneLink.path === "")
            return qsTr("Not paired")
        if (phoneLink.le)
            return qsTr("LE connected")
        if (phoneLink.connected)
            return phoneLink.leKnown ? qsTr("LE not connected, classic link up")
                                     : qsTr("Connected; LE unknown, ioslink isn't running")
        return qsTrId("id-disconnected")
    }

    function hotspotText() {
        if (!networkMode.classicBluetooth)
            return qsTr("Unavailable (classic Bluetooth off)")
        if (!networkMode.hotspotPresent)
            return qsTr("Unavailable")
        var hotspot = networkMode.hotspot
        switch (hotspot.state) {
        case "idle":
            return qsTrId("id-disconnected")
        case "association":
            return qsTr("Connecting")
        case "configuration":
            return qsTr("Getting an address")
        case "ready":
            return qsTrId("id-connected")
        case "online":
            return qsTr("Online")
        case "disconnect":
            return qsTr("Disconnecting")
        case "failure":
            return hotspot.error !== "" ? qsTr("Failed: %1").arg(hotspot.error) : qsTr("Failed")
        }
        return hotspot.state
    }

    component StatusRow: Column {
        property alias caption: captionLabel.text
        property alias value: valueLabel.text

        width: parent.width
        bottomPadding: Dims.l(3)

        Label {
            id: captionLabel
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            opacity: 0.6
            font.pixelSize: Dims.l(4.5)
        }
        Label {
            id: valueLabel
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.pixelSize: Dims.l(6)
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.topMargin: Dims.l(15)
        anchors.bottomMargin: Dims.l(15)
        contentHeight: contentColumn.implicitHeight
        flickableDirection: Flickable.VerticalFlick

        Column {
            id: contentColumn
            width: parent.width

            Item { width: parent.width; height: Dims.l(6) }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Dims.l(5)

                Repeater {
                    model: [
                        { mode: "wifi", label: qsTr("Wi-Fi"), tint: "#2196f3" },
                        { mode: "hotspot", label: qsTr("Hotspot"), tint: "#4caf50" },
                        { mode: "none", label: qsTr("Nothing"), tint: "#757575" }
                    ]

                    // Like the quick panel's toggles: the current mode is
                    // filled with its colour.
                    delegate: Item {
                        readonly property bool selected: networkMode.mode === modelData.mode
                        readonly property bool usable: modelData.mode !== "hotspot" || networkMode.hotspotAvailable

                        width: Dims.l(22)
                        height: circle.height + modeLabel.height + Dims.l(1)
                        opacity: usable ? 1 : 0.4

                        Rectangle {
                            id: circle
                            width: parent.width
                            height: width
                            radius: width / 2
                            color: selected ? modelData.tint : "#222222"
                            opacity: modeArea.pressed ? 0.6 : selected ? 0.75 : 0.2
                        }

                        Icon {
                            anchors.centerIn: circle
                            width: circle.width * 0.5
                            height: width
                            name: page.modeIcon(modelData.mode, selected)
                            opacity: selected ? 1 : 0.6
                        }

                        Label {
                            id: modeLabel
                            anchors.top: circle.bottom
                            anchors.topMargin: Dims.l(1)
                            anchors.horizontalCenter: circle.horizontalCenter
                            text: modelData.label
                            font.pixelSize: Dims.l(5)
                        }

                        MouseArea {
                            id: modeArea
                            anchors.fill: parent
                            enabled: usable
                            onClicked: networkMode.setMode(modelData.mode)
                        }
                    }
                }
            }

            Item { width: parent.width; height: Dims.l(4) }

            // ioslink's ClassicBluetooth: the hotspot and the phone's covers
            // need it; Bluetooth LE stays on either way.
            LabeledSwitch {
                id: classicSwitch
                width: parent.width
                height: Dims.h(25)
                text: qsTr("Classic Bluetooth")
                enabled: networkMode.classicSwitchable
                opacity: enabled ? 1.0 : 0.6
                checked: networkMode.classicBluetooth
                onCheckedChanged: {
                    if (checked !== networkMode.classicBluetooth)
                        networkMode.setClassicBluetooth(checked)
                }
                // A tap sets checked itself, which ends the binding above, so
                // follow changes made elsewhere by hand.
                Connections {
                    target: networkMode
                    function onClassicBluetoothChanged() {
                        classicSwitch.checked = networkMode.classicBluetooth
                    }
                }
            }

            Item { width: parent.width; height: Dims.l(4) }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Dims.w(70)

                StatusRow {
                    caption: qsTr("Internet")
                    value: page.internetText()
                }
                StatusRow {
                    caption: qsTr("IP address")
                    value: page.addressesText()
                }
                StatusRow {
                    caption: qsTr("Wi-Fi")
                    value: page.wifiText()
                }
                StatusRow {
                    caption: qsTrId("id-bluetooth-page")
                    value: page.bluetoothText()
                }
                StatusRow {
                    caption: qsTr("Phone")
                    value: page.phoneText()
                }
                StatusRow {
                    caption: qsTr("Hotspot")
                    value: page.hotspotText()
                }
            }

            Item { width: parent.width; height: Dims.l(10) }
        }
    }

    PageHeader {
        id: title
        text: qsTr("Internet")
    }
}
