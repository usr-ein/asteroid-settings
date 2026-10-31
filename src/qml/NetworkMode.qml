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
import Nemo.DBus 2.0

// The watch's network mode: how it reaches the internet. Each mode is a state
// of connman, so it survives a reboot:
// - "wifi": Wi-Fi is powered. The hotspot doesn't auto-connect and is
//   disconnected.
// - "hotspot": Wi-Fi is off. The hotspot auto-connects and is connected.
// - "none": Wi-Fi is off. The hotspot doesn't auto-connect and is
//   disconnected.
// The hotspot is the phone's Personal Hotspot over classic Bluetooth (PAN):
// connman's service of type "bluetooth". There is no automatic fallback, so
// losing Wi-Fi never brings up the hotspot.
//
// Classic Bluetooth is ioslink's ClassicBluetooth setting. Bluetooth LE, which
// carries notifications and music control, always stays on. With classic off,
// the watch doesn't use classic Bluetooth at all, so there is no hotspot:
// switching classic off in hotspot mode leaves no internet.
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
    // Whether connman has the phone's Bluetooth service. It hasn't when the
    // phone isn't paired over classic Bluetooth, or Bluetooth is off.
    readonly property bool hotspotPresent: hotspotService.path !== "" && hotspotService.valid
    // Whether the hotspot can be used: it is present and classic Bluetooth is on.
    readonly property bool hotspotAvailable: hotspotPresent && classicBluetooth

    // Classic Bluetooth on or off. Until ioslink answers, or without ioslink,
    // this reads on, ioslink's own default.
    readonly property bool classicBluetooth: ioslinkSettings.classicBluetooth
    // Whether ioslink runs, so that classic Bluetooth can be switched.
    readonly property bool classicSwitchable: ioslinkSettings.status === DBusInterface.Available

    // The mode after this one in the cycle Wi-Fi, hotspot, none. The hotspot is
    // skipped when it can't be used.
    function nextMode() {
        if (mode === "wifi")
            return hotspotAvailable ? "hotspot" : "none"
        if (mode === "hotspot")
            return "none"
        return "wifi"
    }

    // Puts connman in the given mode. Every setting is written, so this also
    // repairs a mixed state. Returns false if the mode is "hotspot" and the
    // hotspot can't be used.
    function setMode(newMode) {
        if (newMode !== "wifi" && newMode !== "hotspot" && newMode !== "none")
            return false
        if (newMode === "hotspot" && !hotspotAvailable)
            return false

        // Wi-Fi is switched on first and off last, so that mode never reads
        // "none" in between.
        if (newMode === "wifi" && !wifiTechnology.powered)
            wifiTechnology.powered = true

        if (newMode === "hotspot") {
            if (!hotspotService.autoConnect)
                hotspotService.autoConnect = true
            if (!hotspotService.connected && !hotspotService.connecting)
                hotspotService.requestConnect()
        } else {
            stopHotspot()
        }

        if (newMode !== "wifi" && wifiTechnology.powered)
            wifiTechnology.powered = false
        return true
    }

    // Switches classic Bluetooth on or off through ioslink. Before switching it
    // off, the hotspot stops, so that hotspot mode ends as "none".
    function setClassicBluetooth(on) {
        if (!on)
            stopHotspot()
        ioslinkSettings.setProperty("ClassicBluetooth", on)
    }

    // The hotspot stops auto-connecting and disconnects. This applies even
    // while it can't be used, so that connman doesn't connect it on its own
    // once classic Bluetooth is back.
    function stopHotspot() {
        if (!hotspotPresent)
            return
        if (hotspotService.autoConnect)
            hotspotService.autoConnect = false
        if (hotspotService.state !== "idle")
            hotspotService.requestDisconnect()
    }

    // The first Bluetooth service in connman's order. With one phone paired
    // over classic Bluetooth, that is its hotspot.
    function findHotspot() {
        var manager = managerFactory.instance
        var services = manager && manager.available ? manager.servicesList("bluetooth") : []
        hotspotService.path = services.length > 0 ? services[0] : ""
    }

    // Classic Bluetooth can also be switched off elsewhere, for example by the
    // other user interface. The hotspot then stops here too.
    readonly property bool hotspotWithoutClassic: !classicBluetooth && hotspotPresent &&
                                                  (hotspotService.autoConnect || hotspotService.connected ||
                                                   hotspotService.connecting)
    onHotspotWithoutClassicChanged: if (hotspotWithoutClassic) stopHotspot()

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

    // ioslink's settings, on the session bus.
    DBusInterface {
        id: ioslinkSettings
        bus: DBus.SessionBus
        service: "org.sonicscrewdriver.ioslink"
        path: "/org/sonicscrewdriver/ioslink"
        iface: "org.sonicscrewdriver.ioslink.Settings"
        watchServiceStatus: true
        propertiesEnabled: true
        property bool classicBluetooth: true
    }

    Component.onCompleted: findHotspot()
}
