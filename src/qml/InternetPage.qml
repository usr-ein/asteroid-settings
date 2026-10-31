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

// How the watch reaches the internet: over Wi-Fi only. The watch talks to the
// phone over Bluetooth LE alone (ADR 0001 in sonic-screwdriver), so there is
// no hotspot. The page switches Wi-Fi on and off, and shows the internet
// state, the address and the phone's LE link.
// The qsTr() strings are new in this fork and have no translations yet; the
// qsTrId() ones reuse the app's.
Item {
    id: page

    readonly property var manager: managerFactory.instance
    // The phone's device object in BlueZ, or "" when no phone is paired.
    property string phonePath: ""
    // ioslink decides whether the phone's LE link is up: from Battery1 when
    // BlueZ has it, otherwise with a GATT read every 30 s. Without ioslink,
    // BlueZ's Device1.Connected stands in. The watch is LE-only, so any link
    // to the phone is the LE one.
    readonly property bool phoneLe: ioslinkPhone.status === DBusInterface.Available ?
                                        ioslinkPhone.connected :
                                        phonePath !== "" && phoneDevice.connected

    NetworkManagerFactory { id: managerFactory }

    NetworkTechnology {
        id: wifi
        path: "/net/connman/technology/wifi"
    }

    DBusInterface {
        id: ioslinkPhone
        bus: DBus.SessionBus
        service: "org.sonicscrewdriver.ioslink"
        path: "/org/sonicscrewdriver/ioslink"
        iface: "org.sonicscrewdriver.ioslink.Phone"
        watchServiceStatus: true
        propertiesEnabled: true
        property bool connected: false
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

    // Devices come and go as they are paired or removed; GATT objects, which
    // come and go with the LE link, don't matter here.
    DBusInterface {
        id: bluez
        bus: DBus.SystemBus
        service: "org.bluez"
        path: "/"
        iface: "org.freedesktop.DBus.ObjectManager"
        signalsEnabled: true

        function interfacesAdded(objectPath, interfaces) { changed(objectPath) }
        function interfacesRemoved(objectPath, interfaces) { changed(objectPath) }
        function changed(objectPath) {
            if (/^\/org\/bluez\/hci\d+\/dev_[0-9A-F_]+$/.test(objectPath))
                page.findPhone()
        }
    }

    // The phone is the first paired device whose icon is "phone".
    function findPhone() {
        bluez.typedCall("GetManagedObjects", [], function (objects) {
            var found = ""
            for (var objectPath in objects) {
                var properties = objects[objectPath]["org.bluez.Device1"]
                if (properties && properties.Paired && properties.Icon === "phone") {
                    found = objectPath
                    break
                }
            }
            page.phonePath = found
        }, function (error, message) {
            console.warn("InternetPage: BlueZ GetManagedObjects failed: " + message)
        })
    }

    Component.onCompleted: findPhone()

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
        var service = manager ? manager.connectedWifi : null
        if (service && service.connected) {
            if (service.ipv4 && service.ipv4.Address)
                lines.push(service.ipv4.Address)
            if (service.ipv6 && service.ipv6.Address)
                lines.push(service.ipv6.Address)
        }
        return lines.length > 0 ? lines.join("\n") : qsTr("None")
    }

    function wifiText() {
        if (!wifi.powered)
            return qsTrId("id-off")
        var service = manager ? manager.connectedWifi : null
        if (service && service.connected)
            return qsTr("Connected to %1").arg(service.name)
        return qsTr("On, not connected")
    }

    function phoneText() {
        if (phoneLe)
            return qsTr("LE connected")
        if (phonePath === "")
            return qsTr("Not paired")
        return qsTr("LE not connected")
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

            LabeledSwitch {
                id: wifiSwitch
                width: parent.width
                height: Dims.h(25)
                text: qsTr("Wi-Fi")
                checked: wifi.powered
                onCheckedChanged: {
                    if (checked !== wifi.powered)
                        wifi.powered = checked
                }
                // A tap sets checked itself, which ends the binding above, so
                // follow changes made elsewhere, such as the quick panel, by hand.
                Connections {
                    target: wifi
                    function onPoweredChanged() {
                        wifiSwitch.checked = wifi.powered
                    }
                }
            }

            Item { width: parent.width; height: Dims.l(4) }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Dims.w(70)

                StatusRow {
                    caption: qsTr("Wi-Fi network")
                    value: page.wifiText()
                }
                StatusRow {
                    caption: qsTr("IP address")
                    value: page.addressesText()
                }
                StatusRow {
                    caption: qsTr("Internet")
                    value: page.internetText()
                }
                StatusRow {
                    caption: qsTr("iPhone")
                    value: page.phoneText()
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
