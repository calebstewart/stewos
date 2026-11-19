pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Networking

// Windows replacement for caelestia's services/Nmcli.qml.
//
// Upstream's file drives NetworkManager through the nmcli command. This one
// offers the members the rest of caelestia uses and takes its data from
// Quickshell.Networking, which on Windows reads the adapter list and the WLAN
// service.
//
// What works: adapter and connection status, the Wi-Fi networks in range with
// signal, security and frequency, IP details, switching the Wi-Fi radio,
// rescanning, connecting to a network Windows has a saved profile for, and
// disconnecting. What does not: connecting to a network for the first time,
// forgetting networks, hidden networks, autoconnect and changing IP settings.
// Those functions exist, do nothing, and report failure through their
// callback, so the interface stays usable.
//
// Saved networks are only those in range that Windows has a profile for;
// profiles for networks out of range are not listed.
//
// When upstream changes its file, check whether the rest of caelestia started
// using a member this one does not have.
Singleton {
    id: root

    // The Wi-Fi adapter, preferring one that is connected.
    readonly property var wifiDevice: {
        const devices = Networking.devices.values.filter(d => d.type === DeviceType.Wifi);
        return devices.find(d => d.connected) ?? devices[0] ?? null;
    }

    readonly property bool isConnected: Networking.devices.values.some(d => d.connected)
    readonly property bool connecting: pendingSsid !== "" || networks.some(n => n.connecting)

    // The attempt started by connectToNetwork() that has no outcome yet.
    property string pendingSsid: ""
    property var pendingCallback: null
    readonly property string activeInterface: Networking.devices.values.find(d => d.connected)?.name ?? ""
    readonly property string activeConnection: active?.ssid ?? activeEthernet?.connection ?? ""

    readonly property bool wifiEnabled: Networking.wifiEnabled
    property bool scanning: false

    property list<AccessPoint> networks: []
    readonly property AccessPoint active: networks.find(n => n.active) ?? null

    // Networks in range that Windows has a saved profile for.
    readonly property list<string> savedConnectionSsids: networks.filter(n => n.known).map(n => n.ssid)
    readonly property list<string> savedConnections: savedConnectionSsids
    readonly property var savedConnectionSecurity: {
        const map = {};
        for (const n of networks) {
            if (n.known)
                map[n.ssid] = n.keyManagement;
        }
        return map;
    }

    // Nothing can be connected to yet, so there is never a connection waiting for a password.
    readonly property var pendingConnection: null

    readonly property var wirelessDeviceDetails: detailsOf(wifiDevice)
    readonly property var ethernetDeviceDetails: detailsOf(activeEthernet?.modelData ?? ethernetDevices[0]?.modelData ?? null)
    readonly property string ethernetSpeed: activeEthernet?.speed ?? ""
    // Windows does not report data usage through the adapter list.
    readonly property string ethernetDataUsage: ""

    property list<EthernetDevice> ethernetDevices: []
    readonly property EthernetDevice activeEthernet: ethernetDevices.find(d => d.connected) ?? null
    readonly property bool hasAvailableEthernet: ethernetDevices.some(d => d.state !== "unavailable")

    readonly property alias connectionCheckTimer: connectionCheckTimer
    readonly property alias immediateCheckTimer: immediateCheckTimer

    signal connectionFailed(string ssid)

    function detailsOf(device: var): var {
        if (!device)
            return null;

        return {
            ipAddress: device.ipAddress,
            gateway: device.gateway,
            dns: device.dns,
            subnet: device.subnet,
            macAddress: device.address,
            speed: device.linkSpeed > 0 ? `${device.linkSpeed} Mb/s` : ""
        };
    }

    // The result handed to a callback by something that is not implemented.
    function unavailable(what: string): var {
        console.warn(`${what} is not available on Windows yet`);
        return {
            success: false,
            output: "",
            error: `${what} is not available on Windows yet`,
            exitCode: 1
        };
    }

    // The network an attempt is in progress for: one this file started, or
    // one Windows reports as associating.
    function connectingSsid(): string {
        return pendingSsid !== "" ? pendingSsid : (networks.find(n => n.connecting)?.ssid ?? "");
    }

    function findNetwork(ssid: string): var {
        return networks.find(n => n.ssid === ssid) ?? null;
    }

    function hasSavedProfile(ssid: string): bool {
        return savedConnectionSsids.includes(ssid);
    }

    function savedSecurityFor(ssid: string): string {
        return savedConnectionSecurity[ssid] ?? "";
    }

    // The label for a key management name as NetworkManager spells it.
    function securityLabel(keyMgmt: string): string {
        switch (keyMgmt) {
        case "wpa-psk":
            return "WPA/WPA2";
        case "sae":
            return "WPA3";
        case "wpa-eap":
            return "WPA Enterprise";
        case "wpa-eap-suite-b-192":
            return "WPA3 Enterprise";
        case "owe":
            return "OWE";
        case "none":
            return "WEP";
        case "":
            return "Open";
        default:
            return keyMgmt;
        }
    }

    function loadSavedConnections(callback: var): void {
        Networking.refresh();
        if (callback)
            callback(savedConnections);
    }

    function rescanWifi(): void {
        if (!wifiDevice)
            return;

        wifiDevice.scan();
        scanning = true;
        scanTimer.restart();
    }

    function enableWifi(enabled: bool, callback: var): void {
        Networking.wifiEnabled = enabled;
        if (callback)
            callback({
                success: true,
                output: "",
                error: "",
                exitCode: 0
            });
    }

    function toggleWifi(callback: var): void {
        enableWifi(!wifiEnabled, callback);
    }

    function getWifiStatus(callback: var): void {
        if (callback)
            callback(wifiEnabled);
    }

    function getNetworks(callback: var): void {
        Networking.refresh();
        if (callback)
            callback(networks);
    }

    function refreshStatus(callback: var): void {
        Networking.refresh();
        if (callback)
            callback({
                connected: isConnected,
                interface: activeInterface,
                connection: activeConnection
            });
    }

    function getEthernetInterfaces(callback: var): void {
        Networking.refresh();
        if (callback)
            callback(ethernetDevices.map(d => d.lastIpcObject));
    }

    function getEthernetDeviceDetails(interfaceName: string, callback: var): void {
        const device = ethernetDevices.find(d => d.iface === interfaceName)?.modelData ?? null;
        if (callback)
            callback(detailsOf(device));
    }

    function getWirelessDeviceDetails(interfaceName: string, callback: var): void {
        if (callback)
            callback(wirelessDeviceDetails);
    }

    function getEthernetSpeed(interfaceName: string): void {
    // ethernetSpeed is a binding, so there is nothing to fetch.
    }

    function getEthernetDataUsage(interfaceName: string, callback: var): void {
        if (callback)
            callback("");
    }

    // The configuration of the device carrying a connection, in the shape
    // upstream reads from NetworkManager. The method is always reported as
    // automatic, as how the address was assigned is not read.
    function getIpv4Config(connectionName: string, callback: var): void {
        const device = Networking.devices.values.find(d => d.name === connectionName) ?? (active?.ssid === connectionName ? wifiDevice : null) ?? Networking.devices.values.find(d => d.connected) ?? null;

        if (!callback)
            return;

        if (!device) {
            callback(null);
            return;
        }

        callback({
            method: "auto",
            address: device.ipAddress,
            gateway: device.gateway,
            dns: device.dns.join(", ")
        });
    }

    function setIpv4Config(connectionName: string, config: var, callback: var): void {
        const result = unavailable("Changing IP settings");
        if (callback)
            callback(result);
    }

    // Connects to a network Windows has a saved profile for. The password and
    // the access point address are not used: the profile holds the key, and
    // Windows picks the access point.
    function connectToNetwork(ssid: string, password: string, bssid: string, callback: var): void {
        const ap = findNetwork(ssid);

        if (ap?.active) {
            if (callback)
                callback({
                    success: true,
                    output: "",
                    error: "",
                    exitCode: 0
                });
            return;
        }

        if (!ap?.known) {
            const result = unavailable("Connecting to a network Windows has no saved profile for");
            connectionFailed(ssid);
            if (callback)
                callback(result);
            return;
        }

        // Only one attempt at a time. A newer one replaces an older one.
        if (pendingSsid !== "")
            connectionSettled(pendingSsid, false);

        pendingSsid = ssid;
        pendingCallback = callback ?? null;
        pendingTimer.restart();
        ap.modelData.connect();
    }

    // Called when an attempt started by connectToNetwork() has an outcome.
    function connectionSettled(ssid: string, succeeded: bool): void {
        if (ssid !== pendingSsid)
            return;

        const callback = pendingCallback;
        pendingSsid = "";
        pendingCallback = null;
        pendingTimer.stop();

        if (!succeeded)
            connectionFailed(ssid);

        if (callback)
            callback({
                success: succeeded,
                output: "",
                error: succeeded ? "" : "Connection failed",
                exitCode: succeeded ? 0 : 1
            });
    }

    function connectToNetworkWithPasswordCheck(ssid: string, isSecure: bool, callback: var, bssid: string): void {
        connectToNetwork(ssid, "", bssid, callback);
    }

    function addHiddenNetwork(ssid: string, password: string, security: string, hidden: bool, callback: var): void {
        const result = unavailable("Adding a hidden network");
        if (callback)
            callback(result);
    }

    function disconnectFromNetwork(): void {
        wifiDevice?.disconnect();
    }

    function forgetNetwork(ssid: string, callback: var): void {
        const result = unavailable("Forgetting a network");
        if (callback)
            callback(result);
    }

    function setAutoconnect(connectionName: string, enabled: bool, callback: var): void {
        const result = unavailable("Changing autoconnect");
        if (callback)
            callback(result);
    }

    function getAutoconnect(connectionName: string, callback: var): void {
        if (callback)
            callback(true);
    }

    function connectEthernet(connectionName: string, interfaceName: string, callback: var): void {
        const result = unavailable("Connecting an ethernet device");
        if (callback)
            callback(result);
    }

    function disconnectEthernet(connectionName: string, callback: var): void {
        const result = unavailable("Disconnecting an ethernet device");
        if (callback)
            callback(result);
    }

    function syncNetworks(): void {
        const list = [];
        for (let i = 0; i < accessPoints.count; i++) {
            const ap = accessPoints.objectAt(i);
            if (ap)
                list.push(ap);
        }
        networks = list;
    }

    function syncEthernet(): void {
        const list = [];
        for (let i = 0; i < wired.count; i++) {
            const device = wired.objectAt(i);
            if (device?.isWired)
                list.push(device);
        }
        ethernetDevices = list;
    }

    // One AccessPoint per network the backend reports. The backend keeps its
    // network objects across refreshes, so these are only created and
    // destroyed as networks come into and go out of range.
    Instantiator {
        id: accessPoints

        model: root.wifiDevice?.networks ?? null

        delegate: AccessPoint {}

        onObjectAdded: Qt.callLater(root.syncNetworks)
        onObjectRemoved: Qt.callLater(root.syncNetworks)
    }

    Instantiator {
        id: wired

        model: Networking.devices

        delegate: EthernetDevice {}

        onObjectAdded: Qt.callLater(root.syncEthernet)
        onObjectRemoved: Qt.callLater(root.syncEthernet)
    }

    Timer {
        id: scanTimer

        interval: 4000
        onTriggered: root.scanning = false
    }

    // An attempt with no outcome after this long is treated as failed.
    Timer {
        id: pendingTimer

        interval: 20000
        onTriggered: root.connectionSettled(root.pendingSsid, false)
    }

    // Upstream's timers for re-reading status after a change. The backend
    // follows changes by itself, so these only ask it to read again.
    Timer {
        id: connectionCheckTimer

        interval: 4000
        onTriggered: Networking.refresh()
    }

    Timer {
        id: immediateCheckTimer

        interval: 500
        onTriggered: Networking.refresh()
    }

    component AccessPoint: QtObject {
        // The backend's network object.
        required property var modelData

        readonly property string ssid: modelData.name
        readonly property string bssid: modelData.bssid
        readonly property int strength: Math.round(modelData.signalStrength * 100)
        readonly property int frequency: modelData.frequency
        readonly property bool active: modelData.connected
        // True while the adapter is associating with this network.
        readonly property bool connecting: modelData.stateChanging

        onActiveChanged: {
            if (active)
                root.connectionSettled(ssid, true);
        }

        readonly property Connections failureWatch: Connections {
            function onConnectionFailed(): void {
                root.connectionSettled(modelData.name, false);
            }

            target: modelData
        }

        // Empty for an open network, as nmcli reports it.
        readonly property string security: modelData.security === WifiSecurityType.Open ? "" : WifiSecurityType.toString(modelData.security)
        readonly property bool isSecure: security.length > 0
        readonly property bool known: modelData.known

        // The key management name NetworkManager would use for this network.
        readonly property string keyManagement: {
            switch (modelData.security) {
            case WifiSecurityType.Open:
                return "";
            case WifiSecurityType.Sae:
                return "sae";
            case WifiSecurityType.Owe:
                return "owe";
            case WifiSecurityType.Wpa3SuiteB192:
                return "wpa-eap-suite-b-192";
            case WifiSecurityType.Wpa2Eap:
            case WifiSecurityType.WpaEap:
                return "wpa-eap";
            case WifiSecurityType.StaticWep:
            case WifiSecurityType.DynamicWep:
                return "none";
            default:
                return "wpa-psk";
            }
        }

        readonly property var lastIpcObject: ({
                ssid: ssid,
                bssid: bssid,
                strength: strength,
                frequency: frequency,
                active: active,
                security: security
            })
    }

    component EthernetDevice: QtObject {
        // The backend's device object. Wi-Fi devices get one too and are left
        // out of ethernetDevices.
        required property var modelData

        readonly property bool isWired: modelData.type === DeviceType.Wired
        readonly property string iface: modelData.name
        readonly property string type: "ethernet"
        // nmcli calls a device with no cable plugged in "unavailable".
        readonly property string state: modelData.connected ? "connected" : "unavailable"
        readonly property string connection: modelData.connected ? modelData.name : ""
        readonly property bool connected: modelData.connected
        readonly property string ipAddress: modelData.ipAddress
        readonly property string gateway: modelData.gateway
        readonly property var dns: modelData.dns
        readonly property string subnet: modelData.subnet
        readonly property string macAddress: modelData.address
        readonly property string speed: modelData.linkSpeed > 0 ? `${modelData.linkSpeed} Mb/s` : ""

        readonly property var lastIpcObject: ({
                interface: iface,
                type: type,
                state: state,
                connection: connection,
                connected: connected,
                ipAddress: ipAddress,
                gateway: gateway,
                dns: dns,
                subnet: subnet,
                macAddress: macAddress,
                speed: speed
            })
    }
}
