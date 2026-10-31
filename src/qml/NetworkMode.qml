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
import Connman 0.2

// The watch's network mode: how it reaches the internet. Each mode is a state
// of connman, so it survives a reboot:
// - "wifi": Wi-Fi is powered. The hotspot doesn't auto-connect and is
//   disconnected.
// - "hotspot": Wi-Fi is off. The hotspot auto-connects and is connected.
// - "none": Wi-Fi is off. The hotspot doesn't auto-connect and is
//   disconnected.
// The hotspot is the phone's Personal Hotspot over Bluetooth (PAN): connman's
// service of type "bluetooth". There is no automatic fallback, so losing Wi-Fi
// never brings up the hotspot.
//
// The launcher's quick panel and the Settings app share this file. Keep the
// copies in usr-ein/asteroid-launcher (src/qml/quickpanel/NetworkMode.qml)
// and usr-ein/asteroid-settings (src/qml/NetworkMode.qml) identical below the
// licence header.
Item {
    id: networkMode

    visible: false

    // "wifi", "hotspot" or "none", read back from connman.
    readonly property string mode: wifiTechnology.powered ? "wifi" :
                                   hotspotAvailable && hotspotService.autoConnect ? "hotspot" : "none"
    property alias wifi: wifiTechnology
    property alias hotspot: hotspotService
    // False when connman has no Bluetooth service: the phone isn't paired over
    // classic Bluetooth, or Bluetooth is off.
    readonly property bool hotspotAvailable: hotspotService.path !== "" && hotspotService.valid

    // The mode after this one in the cycle Wi-Fi, hotspot, none. The hotspot is
    // skipped when there is none.
    function nextMode() {
        if (mode === "wifi")
            return hotspotAvailable ? "hotspot" : "none"
        if (mode === "hotspot")
            return "none"
        return "wifi"
    }

    // Puts connman in the given mode. Every setting is written, so this also
    // repairs a mixed state. Returns false if the mode is "hotspot" and there
    // is no hotspot.
    function setMode(newMode) {
        if (newMode !== "wifi" && newMode !== "hotspot" && newMode !== "none")
            return false
        if (newMode === "hotspot" && !hotspotAvailable)
            return false

        // Wi-Fi is switched on first and off last, so that mode never reads
        // "none" in between.
        if (newMode === "wifi" && !wifiTechnology.powered)
            wifiTechnology.powered = true

        if (hotspotAvailable) {
            var useHotspot = newMode === "hotspot"
            if (hotspotService.autoConnect !== useHotspot)
                hotspotService.autoConnect = useHotspot
            if (useHotspot) {
                if (!hotspotService.connected && !hotspotService.connecting)
                    hotspotService.requestConnect()
            } else if (hotspotService.state !== "idle") {
                hotspotService.requestDisconnect()
            }
        }

        if (newMode !== "wifi" && wifiTechnology.powered)
            wifiTechnology.powered = false
        return true
    }

    // The first Bluetooth service in connman's order. With one phone paired
    // over classic Bluetooth, that is its hotspot.
    function findHotspot() {
        var manager = managerFactory.instance
        var services = manager && manager.available ? manager.servicesList("bluetooth") : []
        hotspotService.path = services.length > 0 ? services[0] : ""
    }

    NetworkTechnology {
        id: wifiTechnology
        path: "/net/connman/technology/wifi"
    }

    NetworkService { id: hotspotService }

    NetworkManagerFactory { id: managerFactory }

    Connections {
        target: managerFactory.instance
        function onServicesChanged() { networkMode.findHotspot() }
        function onAvailabilityChanged() { networkMode.findHotspot() }
    }

    Component.onCompleted: findHotspot()
}
