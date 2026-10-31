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
import Nemo.DBus 2.0

// The phone's Bluetooth links, from BlueZ on the system bus.
// - The phone is the device behind connman's hotspot service, whose name is
//   bluetooth_<adapter>_<device>; without that service, the first paired
//   device whose icon is "phone".
// - le: whether the phone's LE link is up, as far as BlueZ shows it.
//   Device1.Connected can't tell, as it stays true while either the LE or
//   the classic link is up. Two signs count:
//   - org.bluez.Battery1 on the device. BlueZ adds it once the LE link is up
//     and battery notifications are on, and removes it when the LE link
//     drops. With some pairings the notifications can't be enabled, and then
//     it never appears.
//   - ServicesResolved while connected. BlueZ clears it when either link
//     drops, and sets it again once services resolve. So it misses an LE link
//     that outlived a classic one, and can read true after a classic-only
//     reconnect.
// - connected: whether any link to the phone is up.
//
// The launcher's quick panel and the Settings app share this file. Keep the
// copies in usr-ein/asteroid-launcher (src/qml/quickpanel/PhoneLink.qml)
// and usr-ein/asteroid-settings (src/qml/PhoneLink.qml) identical below the
// licence header.
Item {
    id: phoneLink

    visible: false

    // connman's hotspot service, to find the phone by its address.
    property string hotspotServicePath: ""
    readonly property string adapterPath: "/org/bluez/hci0"
    // The phone's device object, or "" when no phone is paired.
    property string path: ""
    property bool battery: false
    readonly property bool connected: path !== "" && device.connected
    readonly property bool le: battery || (connected && device.servicesResolved)
    readonly property bool adapterPowered: adapter.powered

    function refresh() {
        var m = /bluetooth_[0-9A-Fa-f]{12}_([0-9A-Fa-f]{12})$/.exec(hotspotServicePath)
        var wanted = m ? m[1].toUpperCase() : ""
        bluez.typedCall("GetManagedObjects", [], function (objects) {
            var byAddress = ""
            var firstPhone = ""
            for (var objectPath in objects) {
                var properties = objects[objectPath]["org.bluez.Device1"]
                if (!properties || !properties.Paired || objectPath.indexOf(adapterPath + "/") !== 0)
                    continue
                if (wanted !== "" && String(properties.Address).replace(/:/g, "") === wanted)
                    byAddress = objectPath
                if (firstPhone === "" && properties.Icon === "phone")
                    firstPhone = objectPath
            }
            var found = byAddress !== "" ? byAddress : firstPhone
            phoneLink.path = found
            phoneLink.battery = found !== "" && objects[found]["org.bluez.Battery1"] !== undefined
        }, function (error, message) {
            console.warn("PhoneLink: BlueZ GetManagedObjects failed: " + message)
        })
    }

    onHotspotServicePathChanged: refresh()
    Component.onCompleted: refresh()

    DBusInterface {
        id: adapter
        bus: DBus.SystemBus
        service: "org.bluez"
        path: phoneLink.adapterPath
        iface: "org.bluez.Adapter1"
        propertiesEnabled: true
        property bool powered: false
    }

    DBusInterface {
        id: device
        bus: DBus.SystemBus
        service: "org.bluez"
        path: phoneLink.path
        iface: "org.bluez.Device1"
        propertiesEnabled: true
        property bool connected: false
        property bool servicesResolved: false
    }

    DBusInterface {
        id: bluez
        bus: DBus.SystemBus
        service: "org.bluez"
        path: "/"
        iface: "org.freedesktop.DBus.ObjectManager"
        signalsEnabled: true

        // GATT objects come and go with the LE link; only the devices matter.
        function interfacesAdded(objectPath, interfaces) { changed(objectPath) }
        function interfacesRemoved(objectPath, interfaces) { changed(objectPath) }
        function changed(objectPath) {
            if (/^\/org\/bluez\/hci\d+\/dev_[0-9A-F_]+$/.test(objectPath))
                phoneLink.refresh()
        }
    }
}
