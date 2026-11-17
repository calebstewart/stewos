pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Win32
import Caelestia.Config
import qs.components.misc
import qs.services

// Windows replacement for caelestia's services/Brightness.qml.
//
// Upstream's file drives ddcutil, brightnessctl and asdbctl. This one offers
// the same members to the rest of caelestia and gets brightness from Windows:
//
// - An external monitor is controlled over DDC/CI through Quickshell.Win32's
//   MonitorBrightness.
// - A monitor that does not answer DDC/CI is assumed to be a laptop's built in
//   panel, which Windows exposes through WMI. That is reached by running
//   PowerShell, as it is rarely needed and slow either way.
// - A monitor that answers neither keeps a brightness of 0 and ignores changes.
//
// The functions, shortcuts and IPC handler below getMonitor() are upstream's,
// unchanged. Only the Monitor component and the device detection differ. When
// upstream changes its file, check whether the rest of caelestia started using
// a member this one does not have.
Singleton {
    id: root

    readonly property list<Monitor> monitors: variants.instances

    function getMonitorForScreen(screen: ShellScreen): var {
        return monitors.find(m => m.modelData === screen);
    }

    function getMonitor(query: string): var {
        if (query === "active") {
            return monitors.find(m => Hypr.monitorFor(m.modelData)?.focused);
        }

        if (query.startsWith("model:")) {
            const model = query.slice(6);
            return monitors.find(m => m.modelData.model === model);
        }

        if (query.startsWith("serial:")) {
            const serial = query.slice(7);
            return monitors.find(m => m.modelData.serialNumber === serial);
        }

        if (query.startsWith("id:")) {
            const id = parseInt(query.slice(3), 10);
            return monitors.find(m => Hypr.monitorFor(m.modelData)?.id === id);
        }

        return monitors.find(m => m.modelData.name === query);
    }

    function increaseBrightness(): void {
        const monitor = getMonitor("active");
        if (monitor)
            monitor.setBrightness(monitor.brightness + GlobalConfig.services.brightnessIncrement);
    }

    function decreaseBrightness(): void {
        const monitor = getMonitor("active");
        if (monitor)
            monitor.setBrightness(monitor.brightness - GlobalConfig.services.brightnessIncrement);
    }

    Variants {
        id: variants

        model: Quickshell.screens // Don't respect excluded screens cause ipc

        Monitor {}
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "brightnessUp"
        description: "Increase brightness"
        onPressed: root.increaseBrightness()
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "brightnessDown"
        description: "Decrease brightness"
        onPressed: root.decreaseBrightness()
    }

    IpcHandler {
        function get(): real {
            return getFor("active");
        }

        // Allows searching by active/model/serial/id/name
        function getFor(query: string): real {
            return root.getMonitor(query)?.brightness ?? -1;
        }

        function set(value: string): string {
            return setFor("active", value);
        }

        // Handles brightness value like brightnessctl: 0.1, +0.1, 0.1-, 10%, +10%, 10%-
        function setFor(query: string, value: string): string {
            const monitor = root.getMonitor(query);
            if (!monitor)
                return "Invalid monitor: " + query;

            let targetBrightness;
            if (value.endsWith("%-")) {
                const percent = parseFloat(value.slice(0, -2));
                targetBrightness = monitor.brightness - (percent / 100);
            } else if (value.startsWith("+") && value.endsWith("%")) {
                const percent = parseFloat(value.slice(1, -1));
                targetBrightness = monitor.brightness + (percent / 100);
            } else if (value.endsWith("%")) {
                const percent = parseFloat(value.slice(0, -1));
                targetBrightness = percent / 100;
            } else if (value.startsWith("+")) {
                const increment = parseFloat(value.slice(1));
                targetBrightness = monitor.brightness + increment;
            } else if (value.endsWith("-")) {
                const decrement = parseFloat(value.slice(0, -1));
                targetBrightness = monitor.brightness - decrement;
            } else if (value.includes("%") || value.includes("-") || value.includes("+")) {
                return `Invalid brightness format: ${value}\nExpected: 0.1, +0.1, 0.1-, 10%, +10%, 10%-`;
            } else {
                targetBrightness = parseFloat(value);
            }

            if (isNaN(targetBrightness))
                return `Failed to parse value: ${value}\nExpected: 0.1, +0.1, 0.1-, 10%, +10%, 10%-`;

            monitor.setBrightness(targetBrightness);

            return `Set monitor ${monitor.modelData.name} brightness to ${+monitor.brightness.toFixed(2)}`;
        }

        target: "brightness"
    }

    component Monitor: QtObject {
        id: monitor

        required property ShellScreen modelData

        // Upstream's names for how a monitor is reached. Kept so anything
        // reading them still finds them.
        readonly property bool isDdc: ddc.available
        readonly property bool isAppleDisplay: false
        readonly property string busNum: ""

        // True if this monitor is the built in panel and answers through WMI.
        property bool isPanel: false
        // True if brightness can be read and changed at all.
        readonly property bool controllable: isDdc || isPanel

        property real brightness: 0

        readonly property MonitorBrightness ddc: MonitorBrightness {
            screen: monitor.modelData

            onBrightnessChanged: {
                if (available)
                    monitor.brightness = brightness;
            }

            // Only a monitor without DDC/CI is tried as the built in panel.
            onReadyChanged: {
                if (available)
                    monitor.brightness = brightness;
                else
                    monitor.panelRead.running = true;
            }
        }

        readonly property Process panelRead: Process {
            command: ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", "(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue | Select-Object -First 1).CurrentBrightness"]
            stdout: StdioCollector {
                onStreamFinished: {
                    const value = parseInt(text.trim());
                    if (isNaN(value))
                        return;

                    monitor.isPanel = true;
                    monitor.brightness = value / 100;
                }
            }
        }

        readonly property Process panelWrite: Process {
            // Started again for the latest value if one was asked for meanwhile.
            onRunningChanged: {
                if (!running && !isNaN(monitor.queuedPanelBrightness)) {
                    const value = monitor.queuedPanelBrightness;
                    monitor.queuedPanelBrightness = NaN;
                    monitor.writePanel(value);
                }
            }
        }

        property real queuedPanelBrightness: NaN

        function writePanel(percent: int): void {
            if (panelWrite.running) {
                queuedPanelBrightness = percent;
                return;
            }

            panelWrite.exec(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", `Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods | Select-Object -First 1 | Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]1; Brightness = [byte]${percent} } | Out-Null`]);
        }

        function setBrightness(value: real): void {
            if (!controllable)
                return;

            value = Math.max(0, Math.min(1, value));
            const rounded = Math.round(value * 100);
            if (Math.round(brightness * 100) === rounded)
                return;

            brightness = value;

            if (isDdc)
                ddc.brightness = value;
            else
                writePanel(rounded);
        }
    }
}
