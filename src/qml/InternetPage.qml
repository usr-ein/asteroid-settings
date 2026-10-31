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
import Nemo.DBus 2.0
import Connman 0.2

// How the watch reaches the internet: Wi-Fi, the phone's hotspot over
// Bluetooth, or nothing (see NetworkMode.qml), and the state of each link.
// The qsTr() strings are new in this fork and have no translations yet; the
// qsTrId() ones reuse the app's.
Item {
    id: page

    readonly property var manager: managerFactory.instance
    readonly property string adapterPath: "/org/bluez/hci0"
    // The phone in BlueZ: the device behind connman's hotspot service, or
    // else the first paired phone.
    property string phonePath: ""
    // BlueZ adds org.bluez.Battery1 to a device once its LE link is up and its
    // GATT battery service is read, and removes it when the LE link drops,
    // whatever the classic link does. Device1.Connected can't tell: it stays
    // true while either link is up.
    property bool phoneLe: false
    readonly property bool phoneConnected: phonePath !== "" && phoneDevice.connected

    NetworkMode { id: networkMode }

    NetworkManagerFactory { id: managerFactory }

    DBusInterface {
        id: adapter
        bus: DBus.SystemBus
        service: "org.bluez"
        path: page.adapterPath
        iface: "org.bluez.Adapter1"
        propertiesEnabled: true
        property bool powered: false
    }

    DBusInterface {
        id: phoneDevice
        bus: DBus.SystemBus
        service: "org.bluez"
        path: page.phonePath
        iface: "org.bluez.Device1"
        propertiesEnabled: true
        property bool connected: false
    }

    DBusInterface {
        id: bluez
        bus: DBus.SystemBus
        service: "org.bluez"
        path: "/"
        iface: "org.freedesktop.DBus.ObjectManager"
        signalsEnabled: true

        // GATT objects come and go with the LE link; only devices matter here.
        function interfacesAdded(path, interfaces) { page.objectsChanged(path) }
        function interfacesRemoved(path, interfaces) { page.objectsChanged(path) }
    }

    function objectsChanged(path) {
        if (/^\/org\/bluez\/hci\d+\/dev_[0-9A-F_]+$/.test(path))
            findPhone()
    }

    // connman names a Bluetooth service bluetooth_<adapter>_<device>, with
    // both addresses in hex.
    function hotspotAddress() {
        var m = /bluetooth_[0-9A-Fa-f]{12}_([0-9A-Fa-f]{12})$/.exec(networkMode.hotspot.path)
        return m ? m[1].toUpperCase() : ""
    }

    function findPhone() {
        bluez.typedCall("GetManagedObjects", [], function (objects) {
            var wanted = hotspotAddress()
            var byAddress = ""
            var firstPhone = ""
            for (var path in objects) {
                var device = objects[path]["org.bluez.Device1"]
                if (!device || !device.Paired || path.indexOf(adapterPath + "/") !== 0)
                    continue
                if (wanted !== "" && String(device.Address).replace(/:/g, "") === wanted)
                    byAddress = path
                if (firstPhone === "" && device.Icon === "phone")
                    firstPhone = path
            }
            var found = byAddress !== "" ? byAddress : firstPhone
            phonePath = found
            phoneLe = found !== "" && objects[found]["org.bluez.Battery1"] !== undefined
        }, function (error, message) {
            console.warn("InternetPage: BlueZ GetManagedObjects failed: " + message)
        })
    }

    Connections {
        target: networkMode.hotspot
        function onPathChanged() { page.findPhone() }
    }

    Component.onCompleted: findPhone()

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
                        networkMode.hotspotAvailable ? networkMode.hotspot : null]
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

    function phoneText() {
        if (phonePath === "")
            return qsTr("Not paired")
        if (phoneLe)
            return qsTr("LE connected")
        if (phoneConnected)
            return qsTr("LE not connected, classic link up")
        return qsTrId("id-disconnected")
    }

    function hotspotText() {
        if (!networkMode.hotspotAvailable)
            return qsTr("Not available")
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

            Item { width: parent.width; height: Dims.l(6) }

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
                    value: adapter.powered ? qsTr("On") : qsTrId("id-off")
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
