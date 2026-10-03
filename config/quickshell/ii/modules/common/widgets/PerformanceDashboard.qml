import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    required property bool active
    property var snapshot: ({})
    property string errorText: ""
    property var cpuHistory: []
    property var memoryHistory: []
    property var gpuHistory: []
    property var networkHistory: []

    readonly property var system: snapshot.system ?? ({})
    readonly property var cpu: snapshot.cpu ?? ({})
    readonly property var memory: snapshot.memory ?? ({})
    readonly property var battery: snapshot.battery ?? ({})
    readonly property var network: snapshot.network ?? ({})
    readonly property var graphics: snapshot.graphics ?? ({})
    readonly property var nvidia: graphics.nvidia ?? ({})
    readonly property var integratedGpu: graphics.integrated ?? ({})
    readonly property var asus: snapshot.asus ?? ({})
    readonly property var disk: snapshot.disk ?? ({})

    implicitWidth: 1740
    implicitHeight: 820

    function formatBytes(value, decimals = 1) {
        const bytes = Number(value ?? 0);
        if (bytes <= 0) return "0 B";
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        const unit = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
        return `${(bytes / Math.pow(1024, unit)).toFixed(unit === 0 ? 0 : decimals)} ${units[unit]}`;
    }

    function percent(part, total) {
        return Number(total) > 0 ? Math.max(0, Math.min(100, Number(part) * 100 / Number(total))) : 0;
    }

    function uptimeText(seconds) {
        const value = Number(seconds ?? 0);
        const days = Math.floor(value / 86400);
        const hours = Math.floor((value % 86400) / 3600);
        const minutes = Math.floor((value % 3600) / 60);
        return `${days > 0 ? `${days}d ` : ""}${hours}h ${minutes}m`;
    }

    function pushHistory(history, value) {
        const next = history.slice(-39);
        next.push(Number(value ?? 0));
        return next;
    }

    function refresh() {
        if (!root.active || snapshotProcess.running) return;
        snapshotProcess.running = true;
    }

    onActiveChanged: if (active) refresh()

    Timer {
        interval: 4000
        running: root.active
        repeat: true
        onTriggered: root.refresh()
    }

    Process {
        id: snapshotProcess
        command: ["python3", Quickshell.shellPath("scripts/system/performance_snapshot.py")]
        stdout: StdioCollector {
            id: outputCollector
            onStreamFinished: {
                try {
                    const next = JSON.parse(outputCollector.text);
                    root.snapshot = next;
                    root.cpuHistory = root.pushHistory(root.cpuHistory, next.cpu?.usage ?? 0);
                    root.memoryHistory = root.pushHistory(root.memoryHistory, root.percent(next.memory?.used, next.memory?.total));
                    root.gpuHistory = root.pushHistory(root.gpuHistory, next.graphics?.nvidia?.available
                        ? next.graphics.nvidia.usage : next.graphics?.integrated?.usage ?? 0);
                    root.networkHistory = root.pushHistory(root.networkHistory,
                        (Number(next.network?.downBps ?? 0) + Number(next.network?.upBps ?? 0)) / 1048576);
                    root.errorText = "";
                } catch (error) {
                    root.errorText = Translation.tr("Could not parse system metrics");
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.errorText = text.trim()
        }
    }

    component Sparkline: Canvas {
        id: sparkline
        required property var values
        property color lineColor: Appearance.colors.colPrimary
        implicitHeight: 34
        implicitWidth: 180
        onValuesChanged: requestPaint()
        onLineColorChanged: requestPaint()
        onPaint: {
            const context = getContext("2d");
            context.reset();
            if (!values || values.length < 2) return;
            const maximum = Math.max(1, ...values);
            context.strokeStyle = lineColor;
            context.lineWidth = 2;
            context.beginPath();
            for (let i = 0; i < values.length; i++) {
                const x = i * width / Math.max(1, values.length - 1);
                const y = height - 3 - (Number(values[i]) / maximum) * (height - 6);
                if (i === 0) context.moveTo(x, y);
                else context.lineTo(x, y);
            }
            context.stroke();
        }
    }

    component UsageBar: ColumnLayout {
        id: usageBar
        required property string label
        required property real value
        property string detail: `${Math.round(value)}%`
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: usageBar.label
                color: Appearance.colors.colOnLayer1
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            StyledText {
                text: usageBar.detail
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 7
            radius: height / 2
            color: Appearance.colors.colLayer3
            Rectangle {
                width: parent.width * Math.max(0, Math.min(100, usageBar.value)) / 100
                height: parent.height
                radius: parent.radius
                color: usageBar.value >= 90 ? Appearance.colors.colError : Appearance.colors.colPrimary
                Behavior on width { NumberAnimation { duration: 250 } }
            }
        }
    }

    component MetricRow: RowLayout {
        id: metricRow
        required property string label
        required property string value
        property string icon: ""
        spacing: 7
        MaterialSymbol {
            visible: metricRow.icon.length > 0
            text: metricRow.icon
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            text: metricRow.label
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
        StyledText {
            text: metricRow.value || "—"
            color: Appearance.colors.colOnLayer1
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Medium
        }
    }

    component Panel: Rectangle {
        id: panel
        required property string title
        required property string icon
        default property alias content: panelBody.data
        Layout.fillWidth: true
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        implicitHeight: panelColumn.implicitHeight + 24

        ColumnLayout {
            id: panelColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                MaterialSymbol {
                    text: panel.icon
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: panel.title
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                }
            }
            ColumnLayout {
                id: panelBody
                Layout.fillWidth: true
                spacing: 7
            }
        }
    }

    component SummaryCard: Rectangle {
        id: card
        required property string title
        required property string value
        required property string icon
        property string detail: ""
        property var history: []
        property real progress: 0
        Layout.fillWidth: true
        implicitHeight: 112
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10
            ColumnLayout {
                Layout.fillWidth: true
                MaterialSymbol { text: card.icon; color: Appearance.colors.colPrimary; iconSize: 23 }
                StyledText { text: card.title; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smaller }
                StyledText { text: card.value; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.large; font.weight: Font.DemiBold }
                StyledText { text: card.detail; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.smallest; elide: Text.ElideRight; Layout.fillWidth: true }
            }
            Sparkline {
                Layout.preferredWidth: 85
                Layout.alignment: Qt.AlignBottom
                values: card.history
            }
        }
    }

    ScrollView {
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        ColumnLayout {
            width: root.width - 20
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    Layout.fillWidth: true
                    text: `${root.system.os ?? "System"}  •  ${root.system.hostname ?? ""}  •  ${root.uptimeText(root.system.uptimeSeconds)}`
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                MaterialSymbol {
                    text: snapshotProcess.running ? "progress_activity" : "refresh"
                    iconSize: Appearance.font.pixelSize.large
                    color: root.errorText ? Appearance.colors.colError : Appearance.colors.colPrimary
                    RotationAnimation on rotation {
                        running: snapshotProcess.running
                        from: 0; to: 360; duration: 900; loops: Animation.Infinite
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                SummaryCard {
                    title: "CPU"; icon: "memory"; value: `${Math.round(root.cpu.usage ?? 0)}%`
                    detail: `${root.cpu.frequencyMHz ?? 0} MHz  •  load ${(root.cpu.load ?? [0])[0]}`
                    history: root.cpuHistory; progress: root.cpu.usage ?? 0
                }
                SummaryCard {
                    title: "Memory"; icon: "memory_alt"; value: root.formatBytes(root.memory.used)
                    detail: `${Math.round(root.percent(root.memory.used, root.memory.total))}% of ${root.formatBytes(root.memory.total)}`
                    history: root.memoryHistory; progress: root.percent(root.memory.used, root.memory.total)
                }
                SummaryCard {
                    title: "Battery"; icon: root.battery.status === "Charging" ? "battery_charging_full" : "battery_full"
                    value: root.battery.available ? `${Math.round(root.battery.percent ?? 0)}%` : "Unavailable"
                    detail: `${root.battery.status ?? ""}  •  health ${root.battery.health ?? 0}%`
                    history: []; progress: root.battery.percent ?? 0
                }
                SummaryCard {
                    title: "Graphics"; icon: "developer_board"
                    value: root.nvidia.available ? `${Math.round(root.nvidia.usage ?? 0)}% NVIDIA` : `${Math.round(root.integratedGpu.usage ?? 0)}% AMD`
                    detail: `${root.graphics.mode ?? ""}  •  dGPU ${root.graphics.powerStatus ?? "unknown"}`
                    history: root.gpuHistory; progress: (root.nvidia.available ? root.nvidia.usage : root.integratedGpu.usage) ?? 0
                }
                SummaryCard {
                    title: "Network"; icon: "wifi"; value: root.network.ssid ?? "Disconnected"
                    detail: `↓ ${root.formatBytes(root.network.downBps)}/s  ↑ ${root.formatBytes(root.network.upBps)}/s`
                    history: root.networkHistory; progress: root.network.signal ?? 0
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 3
                columnSpacing: 10
                rowSpacing: 10

                Panel {
                    title: "Processor"; icon: "memory"
                    StyledText { Layout.fillWidth: true; text: root.cpu.model ?? "—"; wrapMode: Text.Wrap; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.smaller }
                    UsageBar { Layout.fillWidth: true; label: "Total usage"; value: root.cpu.usage ?? 0 }
                    MetricRow { Layout.fillWidth: true; label: "Cores / threads"; value: `${root.cpu.physicalCores ?? 0} / ${root.cpu.cores ?? 0}` }
                    MetricRow { Layout.fillWidth: true; label: "Clock"; value: `${root.cpu.frequencyMHz ?? 0} / ${root.cpu.maxFrequencyMHz ?? 0} MHz` }
                    MetricRow { Layout.fillWidth: true; label: "Load 1 / 5 / 15m"; value: (root.cpu.load ?? []).join("  ·  ") }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 4
                        Repeater {
                            model: root.cpu.perCore ?? []
                            delegate: Rectangle {
                                required property int index
                                required property var modelData
                                width: 49; height: 24; radius: 5
                                color: Appearance.colors.colLayer2
                                StyledText { anchors.centerIn: parent; text: `${index}: ${Math.round(modelData)}%`; font.pixelSize: Appearance.font.pixelSize.smallest; color: Appearance.colors.colSubtext }
                            }
                        }
                    }
                }

                Panel {
                    title: "Memory & storage"; icon: "storage"
                    UsageBar { Layout.fillWidth: true; label: "RAM"; value: root.percent(root.memory.used, root.memory.total); detail: `${root.formatBytes(root.memory.used)} / ${root.formatBytes(root.memory.total)}` }
                    UsageBar { Layout.fillWidth: true; label: "Swap"; value: root.percent(root.memory.swapUsed, root.memory.swapTotal); detail: `${root.formatBytes(root.memory.swapUsed)} / ${root.formatBytes(root.memory.swapTotal)}` }
                    UsageBar { Layout.fillWidth: true; label: "Root filesystem"; value: root.percent(root.disk.used, root.disk.total); detail: `${root.formatBytes(root.disk.used)} / ${root.formatBytes(root.disk.total)}` }
                    MetricRow { Layout.fillWidth: true; label: "Root device"; value: root.disk.source ?? "—" }
                    MetricRow { Layout.fillWidth: true; label: "Disk read"; value: `${root.formatBytes(root.disk.readBps)}/s` }
                    MetricRow { Layout.fillWidth: true; label: "Disk write"; value: `${root.formatBytes(root.disk.writeBps)}/s` }
                }

                Panel {
                    title: "Power & ASUS"; icon: "battery_android_full"
                    UsageBar { Layout.fillWidth: true; label: "Battery"; value: root.battery.percent ?? 0; detail: `${Math.round(root.battery.percent ?? 0)}%` }
                    MetricRow { Layout.fillWidth: true; label: "Status"; value: root.battery.status ?? "—" }
                    MetricRow { Layout.fillWidth: true; label: "Health"; value: `${root.battery.health ?? 0}%  (${root.battery.fullWh ?? 0}/${root.battery.designWh ?? 0} Wh)` }
                    MetricRow { Layout.fillWidth: true; label: "Power / voltage"; value: `${root.battery.powerW ?? 0} W  ·  ${root.battery.voltageV ?? 0} V` }
                    MetricRow { Layout.fillWidth: true; label: "Charge limit"; value: `${root.battery.limit ?? 0}%` }
                    MetricRow { Layout.fillWidth: true; label: "ASUS profile"; value: String(root.asus.profile ?? "—").split("\n")[0] }
                }

                Panel {
                    title: "Graphics"; icon: "developer_board"
                    MetricRow { Layout.fillWidth: true; label: "supergfxctl mode"; value: root.graphics.mode ?? "—" }
                    MetricRow { Layout.fillWidth: true; label: "dGPU power state"; value: root.graphics.powerStatus ?? "—" }
                    StyledText { Layout.fillWidth: true; text: root.nvidia.available ? root.nvidia.name : "NVIDIA GPU suspended / unavailable"; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.smaller }
                    UsageBar { Layout.fillWidth: true; label: "NVIDIA utilization"; value: root.nvidia.usage ?? 0; visible: root.nvidia.available ?? false }
                    MetricRow { Layout.fillWidth: true; label: "NVIDIA VRAM"; value: root.nvidia.available ? `${root.nvidia.memoryUsedMiB}/${root.nvidia.memoryTotalMiB} MiB` : "—" }
                    MetricRow { Layout.fillWidth: true; label: "NVIDIA temp / power"; value: root.nvidia.available ? `${root.nvidia.temperature}°C  ·  ${root.nvidia.powerW} W  ·  ${root.nvidia.pstate}` : "—" }
                    UsageBar { Layout.fillWidth: true; label: "AMD Radeon 780M"; value: root.integratedGpu.usage ?? 0 }
                    MetricRow { Layout.fillWidth: true; label: "Integrated GPU temp"; value: `${root.integratedGpu.temperature ?? 0}°C` }
                }

                Panel {
                    title: "Wi‑Fi & traffic"; icon: "wifi"
                    UsageBar { Layout.fillWidth: true; label: root.network.ssid ?? "Network"; value: root.network.signal ?? 0; detail: `${root.network.signal ?? 0}%` }
                    MetricRow { Layout.fillWidth: true; label: "Interface / IP"; value: `${root.network.interface ?? "—"}  ·  ${root.network.ip ?? "—"}` }
                    MetricRow { Layout.fillWidth: true; label: "Link rate"; value: root.network.rate ?? "—" }
                    MetricRow { Layout.fillWidth: true; label: "Security"; value: root.network.security ?? "—" }
                    MetricRow { Layout.fillWidth: true; label: "Download now"; value: `${root.formatBytes(root.network.downBps)}/s` }
                    MetricRow { Layout.fillWidth: true; label: "Upload now"; value: `${root.formatBytes(root.network.upBps)}/s` }
                    MetricRow { Layout.fillWidth: true; label: "Session totals"; value: `↓ ${root.formatBytes(root.network.rxBytes)}  ↑ ${root.formatBytes(root.network.txBytes)}` }
                }

                Panel {
                    title: "Thermals & fans"; icon: "device_thermostat"
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        Repeater {
                            model: root.snapshot.temperatures ?? []
                            delegate: MetricRow { required property var modelData; Layout.fillWidth: true; label: modelData.name; value: `${modelData.c}°C` }
                        }
                    }
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Appearance.colors.colOutlineVariant }
                    Repeater {
                        model: root.snapshot.fans ?? []
                        delegate: MetricRow { required property var modelData; Layout.fillWidth: true; icon: "mode_fan"; label: modelData.name; value: `${modelData.rpm} RPM` }
                    }
                }

                Panel {
                    Layout.columnSpan: 2
                    title: "Top processes"; icon: "monitoring"
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: 18
                        StyledText { text: "PID"; color: Appearance.colors.colSubtext; font.weight: Font.DemiBold }
                        StyledText { text: "Process"; color: Appearance.colors.colSubtext; font.weight: Font.DemiBold; Layout.fillWidth: true }
                        StyledText { text: "CPU"; color: Appearance.colors.colSubtext; font.weight: Font.DemiBold }
                        StyledText { text: "RAM"; color: Appearance.colors.colSubtext; font.weight: Font.DemiBold }
                        Repeater {
                            model: root.snapshot.processes ?? []
                            delegate: Repeater {
                                required property var modelData
                                model: [modelData.pid, modelData.name, `${modelData.cpu}%`, `${modelData.memory}%`]
                                delegate: StyledText { required property int index; required property var modelData; text: modelData; color: Appearance.colors.colOnLayer1; font.pixelSize: Appearance.font.pixelSize.smaller; Layout.fillWidth: index === 1 }
                            }
                        }
                    }
                }

                Panel {
                    title: "System"; icon: "computer"
                    MetricRow { Layout.fillWidth: true; label: "Host"; value: root.system.hostname ?? "—" }
                    MetricRow { Layout.fillWidth: true; label: "Operating system"; value: root.system.os ?? "—" }
                    MetricRow { Layout.fillWidth: true; label: "Kernel"; value: root.system.kernel ?? "—" }
                    MetricRow { Layout.fillWidth: true; label: "Uptime"; value: root.uptimeText(root.system.uptimeSeconds) }
                    MetricRow { Layout.fillWidth: true; label: "Available ASUS profiles"; value: (root.asus.profiles ?? []).join(" · ") }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.errorText.length > 0
                text: root.errorText
                color: Appearance.colors.colError
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
