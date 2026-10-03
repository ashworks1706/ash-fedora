import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    required property bool active
    property var snapshot: ({})
    property var cpuHistory: []
    property var memoryHistory: []
    property var gpuHistory: []
    property var networkHistory: []
    property string errorText: ""

    readonly property var system: snapshot.system ?? ({})
    readonly property var cpu: snapshot.cpu ?? ({})
    readonly property var memory: snapshot.memory ?? ({})
    readonly property var battery: snapshot.battery ?? ({})
    readonly property var network: snapshot.network ?? ({})
    readonly property var graphics: snapshot.graphics ?? ({})
    readonly property var nvidia: graphics.nvidia ?? ({})
    readonly property var integratedGpu: graphics.integrated ?? ({})
    readonly property var disk: snapshot.disk ?? ({})
    readonly property var asus: snapshot.asus ?? ({})
    readonly property color terminalForeground: Appearance.colors.colOnLayer0
    readonly property color terminalMuted: Appearance.colors.colSubtext
    readonly property color terminalAccent: Appearance.colors.colPrimary
    readonly property string monoFont: "JetBrainsMono Nerd Font"

    implicitWidth: 1740
    implicitHeight: 820
    color: Qt.rgba(0.025, 0.03, 0.04, 0.97)
    border.width: 1
    border.color: Appearance.colors.colOutlineVariant
    radius: Appearance.rounding.small

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

    function historyPush(history, value) {
        const next = history.slice(-74);
        next.push(Number(value ?? 0));
        return next;
    }

    function spark(values, width = 64, fixedMaximum = 100) {
        const glyphs = "▁▂▃▄▅▆▇█";
        const data = (values ?? []).slice(-width);
        const maximum = fixedMaximum > 0 ? fixedMaximum : Math.max(1, ...data);
        let output = "";
        for (let padding = data.length; padding < width; padding++) output += "▁";
        for (const value of data) {
            const index = Math.max(0, Math.min(7, Math.floor(Number(value) / maximum * 7)));
            output += glyphs[index];
        }
        return output;
    }

    function bar(value, width = 18) {
        const count = Math.round(Math.max(0, Math.min(100, Number(value ?? 0))) * width / 100);
        return "█".repeat(count) + "░".repeat(width - count);
    }

    function uptime(seconds) {
        const value = Number(seconds ?? 0);
        const days = Math.floor(value / 86400);
        const hours = Math.floor((value % 86400) / 3600);
        const minutes = Math.floor((value % 3600) / 60);
        return `${days ? `${days}d ` : ""}${hours}h ${minutes}m`;
    }

    function coreTable() {
        const values = cpu.perCore ?? [];
        const rows = [];
        for (let offset = 0; offset < values.length; offset += 4) {
            const columns = [];
            for (let index = offset; index < Math.min(values.length, offset + 4); index++) {
                columns.push(`${String(index).padStart(2, "0")} ${bar(values[index], 8)} ${String(Math.round(values[index])).padStart(3, " ")}%`);
            }
            rows.push(columns.join("    "));
        }
        return rows.join("\n");
    }

    function thermalTable() {
        const values = snapshot.temperatures ?? [];
        if (!values.length) return "no readable hwmon sensors";
        return values.map(item => `${String(item.name).padEnd(18, " ").slice(0, 18)} ${String(item.c).padStart(5, " ")}°C`).join("\n");
    }

    function fanTable() {
        const values = snapshot.fans ?? [];
        if (!values.length) return "fan telemetry unavailable";
        return values.map(item => `${String(item.name).padEnd(18, " ").slice(0, 18)} ${String(item.rpm).padStart(5, " ")} rpm`).join("\n");
    }

    function processTable() {
        const values = snapshot.processes ?? [];
        const header = " PID     CPU    MEM   COMMAND";
        return header + "\n" + values.slice(0, 9).map(item =>
            `${String(item.pid).padStart(6, " ")}  ${String(item.cpu).padStart(5, " ")}% ${String(item.memory).padStart(5, " ")}%  ${String(item.name).slice(0, 24)}`
        ).join("\n");
    }

    function refresh() {
        if (active && !snapshotProcess.running) snapshotProcess.running = true;
    }

    onActiveChanged: if (active) refresh()

    Timer {
        interval: 2500
        repeat: true
        running: root.active
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
                    root.cpuHistory = root.historyPush(root.cpuHistory, next.cpu?.usage ?? 0);
                    root.memoryHistory = root.historyPush(root.memoryHistory, root.percent(next.memory?.used, next.memory?.total));
                    root.gpuHistory = root.historyPush(root.gpuHistory, next.graphics?.nvidia?.available ? next.graphics.nvidia.usage : next.graphics?.integrated?.usage ?? 0);
                    root.networkHistory = root.historyPush(root.networkHistory, (Number(next.network?.downBps ?? 0) + Number(next.network?.upBps ?? 0)) / 1048576);
                    root.errorText = "";
                } catch (error) {
                    root.errorText = "snapshot parse error";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) root.errorText = text.trim()
        }
    }

    component TerminalText: Text {
        color: root.terminalForeground
        font.family: root.monoFont
        font.pixelSize: 14
        font.letterSpacing: 0
        renderType: Text.NativeRendering
        textFormat: Text.PlainText
    }

    component SectionTitle: TerminalText {
        color: root.terminalAccent
        font.bold: true
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 6

        TerminalText {
            Layout.fillWidth: true
            text: `┌─ SYSTEM TELEMETRY // ${root.system.hostname ?? "waiting"} // ${root.system.kernel ?? ""}`
            color: root.terminalAccent
            font.bold: true
            font.pixelSize: 16
        }
        TerminalText {
            Layout.fillWidth: true
            text: `│ ${root.system.os ?? "collecting metrics..."}  •  up ${root.uptime(root.system.uptimeSeconds)}  •  refresh 2.5s  •  collector: ${root.active ? "ACTIVE" : "STOPPED"}`
            color: root.terminalMuted
        }
        TerminalText { Layout.fillWidth: true; text: "├" + "─".repeat(150); color: root.terminalMuted }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            columnSpacing: 34

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1080
                spacing: 4

                SectionTitle { text: "├─ LOAD / HISTORY" }
                TerminalText { text: `CPU  ${String(Math.round(root.cpu.usage ?? 0)).padStart(3, " ")}%  ${root.bar(root.cpu.usage, 20)}  ${(root.cpu.frequencyMHz ?? 0)} MHz  load ${(root.cpu.load ?? []).join("/")}` }
                TerminalText { text: `     ${root.spark(root.cpuHistory, 88)}`; color: root.terminalAccent }
                TerminalText { text: `MEM  ${String(Math.round(root.percent(root.memory.used, root.memory.total))).padStart(3, " ")}%  ${root.bar(root.percent(root.memory.used, root.memory.total), 20)}  ${root.formatBytes(root.memory.used)} / ${root.formatBytes(root.memory.total)}` }
                TerminalText { text: `     ${root.spark(root.memoryHistory, 88)}`; color: Appearance.colors.colSecondary }
                TerminalText {
                    text: `GPU  ${String(Math.round(root.nvidia.available ? root.nvidia.usage ?? 0 : root.integratedGpu.usage ?? 0)).padStart(3, " ")}%  ${root.bar(root.nvidia.available ? root.nvidia.usage : root.integratedGpu.usage, 20)}  ${root.nvidia.available ? root.nvidia.name : "AMD Radeon 780M / NVIDIA suspended"}`
                }
                TerminalText { text: `     ${root.spark(root.gpuHistory, 88)}`; color: Appearance.colors.colTertiary }
                TerminalText { text: `NET  ↓ ${root.formatBytes(root.network.downBps)}/s  ↑ ${root.formatBytes(root.network.upBps)}/s  ${root.network.interface ?? "—"} @ ${root.network.ssid ?? "disconnected"}` }
                TerminalText { text: `     ${root.spark(root.networkHistory, 88, 0)}`; color: Appearance.colors.colSecondary }

                SectionTitle { Layout.topMargin: 8; text: "├─ LOGICAL CORES" }
                TerminalText { text: root.coreTable(); lineHeight: 1.18 }

                SectionTitle { Layout.topMargin: 8; text: "├─ MEMORY / STORAGE / NETWORK" }
                TerminalText {
                    text: [
                        `RAM     ${root.formatBytes(root.memory.used).padStart(10, " ")} / ${root.formatBytes(root.memory.total)}`,
                        `SWAP    ${root.formatBytes(root.memory.swapUsed).padStart(10, " ")} / ${root.formatBytes(root.memory.swapTotal)}`,
                        `ROOT    ${root.formatBytes(root.disk.used).padStart(10, " ")} / ${root.formatBytes(root.disk.total)}  ${root.disk.source ?? ""}`,
                        `DISK    read ${root.formatBytes(root.disk.readBps)}/s  write ${root.formatBytes(root.disk.writeBps)}/s`,
                        `LINK    ${root.network.rate ?? "—"}  signal ${root.network.signal ?? 0}%  ${root.network.ip ?? ""}`,
                        `TOTAL   rx ${root.formatBytes(root.network.rxBytes)}  tx ${root.formatBytes(root.network.txBytes)}`
                    ].join("\n")
                    lineHeight: 1.18
                }
                Item { Layout.fillHeight: true }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 560
                spacing: 4

                SectionTitle { text: "├─ POWER / ASUS" }
                TerminalText {
                    text: [
                        `battery  ${root.battery.available ? `${Math.round(root.battery.percent ?? 0)}% ${root.battery.status ?? ""}` : "unavailable"}`,
                        `draw     ${root.battery.powerW ?? 0} W @ ${root.battery.voltageV ?? 0} V`,
                        `health   ${root.battery.health ?? 0}%  cycles ${root.battery.cycles ?? 0}`,
                        `limit    ${root.battery.limit ?? 0}%`,
                        `profile  ${String(root.asus.profile ?? "—").split("\n")[0]}`,
                        `gfx mode ${root.graphics.mode ?? "—"}`,
                        `dGPU     ${root.graphics.powerStatus ?? "—"}`
                    ].join("\n")
                    lineHeight: 1.18
                }

                SectionTitle { Layout.topMargin: 8; text: "├─ GPU DETAIL" }
                TerminalText {
                    text: root.nvidia.available ? [
                        `${root.nvidia.name}`,
                        `load  ${root.nvidia.usage}%  state ${root.nvidia.pstate}`,
                        `vram  ${root.nvidia.memoryUsedMiB}/${root.nvidia.memoryTotalMiB} MiB`,
                        `temp  ${root.nvidia.temperature}°C  power ${root.nvidia.powerW} W`
                    ].join("\n") : [
                        "NVIDIA telemetry idle",
                        "dGPU is not woken for this panel",
                        `iGPU  ${root.integratedGpu.usage ?? 0}% @ ${root.integratedGpu.temperature ?? 0}°C`
                    ].join("\n")
                    lineHeight: 1.18
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    columns: 2
                    columnSpacing: 24
                    ColumnLayout {
                        SectionTitle { text: "├─ THERMALS" }
                        TerminalText { text: root.thermalTable(); lineHeight: 1.16 }
                    }
                    ColumnLayout {
                        SectionTitle { text: "├─ FANS" }
                        TerminalText { text: root.fanTable(); lineHeight: 1.16 }
                    }
                }

                SectionTitle { Layout.topMargin: 8; text: "├─ TOP PROCESSES" }
                TerminalText { text: root.processTable(); lineHeight: 1.15 }
                Item { Layout.fillHeight: true }
            }
        }

        TerminalText {
            Layout.fillWidth: true
            text: root.errorText ? `└─ ERROR // ${root.errorText}` : "└─ on-demand telemetry; leaving this tab stops all sampling"
            color: root.errorText ? Appearance.colors.colError : root.terminalMuted
        }
    }
}
