pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool enabled: Config.options?.search?.fileSearch?.enable ?? true
    property int maxResults: Config.options?.search?.fileSearch?.maxResults ?? 24
    property int indexLimit: Config.options?.search?.fileSearch?.indexLimit ?? 8000
    property int maxDepth: Config.options?.search?.fileSearch?.maxDepth ?? 6
    property bool followSymlinks: Config.options?.search?.fileSearch?.followSymlinks ?? false
    property bool startupRefresh: Config.options?.search?.fileSearch?.startupRefresh ?? false
    property list<string> configuredPaths: Config.options?.search?.fileSearch?.searchPaths ?? []
    property list<string> configuredStartupPaths: Config.options?.search?.fileSearch?.startupSearchPaths ?? []
    property list<string> configuredPriorityPaths: Config.options?.search?.fileSearch?.priorityPaths ?? []
    property list<string> configuredExcludeGlobs: Config.options?.search?.fileSearch?.excludeGlobs ?? []

    property string fdBinary: "/usr/bin/fd"
    property string cacheDir: FileUtils.trimFileProtocol(`${Directories.state}/user`)
    property string cachePath: FileUtils.trimFileProtocol(`${Directories.state}/user/file-search-index-v2.json`)
    property int cacheVersion: 2

    readonly property int perScanLimit: Math.max(1, Math.floor(indexLimit / 2))
    readonly property string homePath: FileUtils.trimFileProtocol(Directories.home)

    readonly property list<string> resolvedSearchPaths: normalizePaths(configuredPaths.length > 0 ? configuredPaths : [
        `${Directories.config}/hypr`,
        `${Directories.config}/illogical-impulse`,
        Directories.documents,
        Directories.downloads,
        Directories.pictures,
        Directories.music,
        Directories.videos
    ])

    readonly property list<string> startupSearchPaths: normalizePaths(configuredStartupPaths.length > 0
        ? configuredStartupPaths
        : [
            `${Directories.config}/hypr`,
            `${Directories.config}/illogical-impulse`
        ])

    readonly property list<string> priorityPaths: normalizePaths(configuredPriorityPaths.length > 0 ? configuredPriorityPaths : [
        `${Directories.config}/hypr`,
        `${Directories.config}/illogical-impulse`
    ])

    readonly property list<string> excludeGlobs: configuredExcludeGlobs.length > 0 ? configuredExcludeGlobs : [
        "**/.git/**",
        "**/node_modules/**",
        "**/.cache/**",
        "**/.local/share/Trash/**",
        "**/.npm/**",
        "**/.venv/**",
        "**/.direnv/**",
        "**/.next/**",
        "**/.turbo/**",
        "**/dist/**",
        "**/build/**",
        "**/target/**",
        "**/__pycache__/**",
        "**/.pytest_cache/**",
        "**/.ruff_cache/**",
        "**/.mypy_cache/**",
        "**/.gradle/**",
        "**/.m2/**"
    ]

    property list<var> entries: []
    property var preppedEntries: []
    property var pathMtimes: ({})

    property bool ready: false
    property bool indexing: false
    property bool cacheLoaded: false

    property bool pendingRefreshForce: false
    property list<string> pendingRefreshPaths: []

    property list<string> activeRefreshPaths: []
    property var activeRefreshMtimes: ({})
    property bool activeFullRefresh: false

    function normalizePaths(paths) {
        const seen = {};
        const cleaned = [];
        for (let i = 0; i < paths.length; ++i) {
            const trimmed = FileUtils.trimFileProtocol(paths[i] ?? "").replace(/[\\/]+$/, "");
            if (!trimmed || seen[trimmed]) continue;
            seen[trimmed] = true;
            cleaned.push(trimmed);
        }
        return cleaned;
    }

    function prettyPath(path) {
        const trimmed = FileUtils.trimFileProtocol(path ?? "");
        if (trimmed.startsWith(homePath + "/")) {
            return "~/" + trimmed.slice(homePath.length + 1);
        }
        return trimmed || path;
    }

    function isPriority(path) {
        for (let i = 0; i < priorityPaths.length; ++i) {
            if (path.startsWith(priorityPaths[i])) return true;
        }
        return false;
    }

    function rebuildPreparedEntries() {
        preppedEntries = entries.map(entry => ({
            name: Fuzzy.prepare(`${entry.name} ${entry.parent}`),
            entry: entry
        }));
    }

    function removeEntriesUnderPaths(paths) {
        const keep = entries.filter(entry => {
            for (let i = 0; i < paths.length; ++i) {
                const base = paths[i];
                if (entry.path === base) return false;
                if (entry.path.startsWith(base + "/")) return false;
            }
            return true;
        });
        entries = keep;
        rebuildPreparedEntries();
    }

    function appendEntries(lines, isDir) {
        const seen = new Set(entries.map(e => e.path));
        const collected = [];
        for (let i = 0; i < lines.length; ++i) {
            if (entries.length + collected.length >= indexLimit) break;
            const raw = FileUtils.trimFileProtocol(lines[i] ?? "");
            if (!raw || seen.has(raw)) continue;
            seen.add(raw);
            const path = raw.replace(/[\\/]+$/, "");
            const parent = FileUtils.parentDirectory(path);
            collected.push({
                key: path,
                name: isDir ? FileUtils.folderNameForPath(path) : FileUtils.fileNameForPath(path),
                path: path,
                parent: prettyPath(parent),
                isDir: isDir,
                priority: isPriority(path)
            });
        }

        if (collected.length > 0) {
            entries = entries.concat(collected);
            rebuildPreparedEntries();
        }
    }

    function baseCommandArgs(type, paths) {
        const args = [fdBinary, "--hidden", "--color", "never"];
        if (followSymlinks) args.push("-L");
        if (maxDepth > 0) args.push("--max-depth", `${maxDepth}`);
        if (perScanLimit > 0) args.push("--max-results", `${perScanLimit}`);
        for (let i = 0; i < excludeGlobs.length; ++i) {
            args.push("--exclude", excludeGlobs[i]);
        }
        if (type) args.push("-t", type);
        args.push("");
        return args.concat(paths);
    }

    function parsePathMtimeLines(lines) {
        const mtimes = {};
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i];
            const splitIdx = line.lastIndexOf("\t");
            if (splitIdx <= 0) continue;
            const path = line.slice(0, splitIdx);
            const mtimeStr = line.slice(splitIdx + 1);
            const mtimeNum = parseInt(mtimeStr);
            mtimes[path] = Number.isNaN(mtimeNum) ? -1 : mtimeNum;
        }
        return mtimes;
    }

    function pruneMtimes() {
        const allowed = new Set(resolvedSearchPaths);
        const next = {};
        for (const key in pathMtimes) {
            if (allowed.has(key)) next[key] = pathMtimes[key];
        }
        pathMtimes = next;
    }

    function startScan(paths, mtimes, fullRefresh = false) {
        if (paths.length === 0) {
            ready = true;
            indexing = false;
            return;
        }

        indexing = true;
        ready = false;

        activeRefreshPaths = paths;
        activeRefreshMtimes = mtimes;
        activeFullRefresh = fullRefresh;

        if (activeFullRefresh) {
            entries = [];
            preppedEntries = [];
            pathMtimes = {};
        } else {
            removeEntriesUnderPaths(paths);
        }

        fileIndexProc.buffer = [];
        dirIndexProc.buffer = [];
        fileIndexProc.command = baseCommandArgs("f", paths);
        dirIndexProc.command = baseCommandArgs("d", paths);
        fileIndexProc.running = true;
    }

    function refresh(force = false, customPaths = []) {
        if (!enabled) {
            entries = [];
            preppedEntries = [];
            pathMtimes = {};
            ready = true;
            indexing = false;
            saveCache();
            return;
        }

        const paths = normalizePaths(customPaths.length > 0 ? customPaths : resolvedSearchPaths);
        if (paths.length === 0) {
            console.warn("[FileSearch] No search paths configured");
            ready = true;
            indexing = false;
            return;
        }

        if (!cacheLoaded) {
            pendingRefreshForce = force;
            pendingRefreshPaths = paths;
            return;
        }

        if (indexing || pathMtimeProc.running)
            return;

        pendingRefreshForce = force;
        pendingRefreshPaths = paths;
        pathMtimeProc.buffer = [];
        pathMtimeProc.command = [
            "bash", "-lc",
            "for p in \"$@\"; do if [ -e \"$p\" ]; then m=$(stat -c %Y \"$p\" 2>/dev/null || echo -1); else m=-1; fi; printf \"%s\\t%s\\n\" \"$p\" \"$m\"; done",
            "_"
        ].concat(paths);
        pathMtimeProc.running = true;
    }

    function finishIndexing() {
        indexing = false;
        ready = true;

        for (let i = 0; i < activeRefreshPaths.length; ++i) {
            const path = activeRefreshPaths[i];
            pathMtimes[path] = activeRefreshMtimes[path] ?? -1;
        }

        pruneMtimes();
        rebuildPreparedEntries();
        saveCache();
    }

    function fuzzyQuery(search) {
        if (!enabled || !ready) return [];
        if (!search || search.trim() === "") return [];

        const prefixes = Config.options.search.prefix;
        const hasOtherPrefix = [
            prefixes.action,
            prefixes.app,
            prefixes.clipboard,
            prefixes.emojis,
            prefixes.math,
            prefixes.shellCommand,
            prefixes.webSearch
        ].some(prefix => prefix && search.startsWith(prefix));

        const cleaned = StringUtils.cleanPrefix(search, prefixes.files).trim();
        if (hasOtherPrefix && !search.startsWith(prefixes.files)) return [];

        const query = cleaned.length === 0 ? search.trim() : cleaned;
        if (query.length === 0) return [];

        const results = Fuzzy.go(query, preppedEntries, {
            all: true,
            key: "name"
        }).map(r => r.obj.entry);

        const prioritized = [];
        const others = [];
        for (let i = 0; i < results.length; ++i) {
            (results[i].priority ? prioritized : others).push(results[i]);
        }
        return prioritized.concat(others).slice(0, maxResults);
    }

    function saveCache() {
        if (!cacheLoaded)
            return;

        const payload = {
            version: cacheVersion,
            updatedAt: Date.now(),
            entries: entries,
            pathMtimes: pathMtimes
        };
        cacheFileView.setText(JSON.stringify(payload));
    }

    function handleCacheReady() {
        cacheLoaded = true;
        ready = true;
        indexing = false;
        rebuildPreparedEntries();

        if (startupRefresh) {
            refresh(false, startupSearchPaths);
        } else if (pendingRefreshPaths.length > 0) {
            refresh(pendingRefreshForce, pendingRefreshPaths);
        }
    }

    Process {
        id: pathMtimeProc
        property list<string> buffer: []
        command: []

        stdout: SplitParser {
            onRead: line => {
                if (line)
                    pathMtimeProc.buffer.push(line);
            }
        }

        onExited: (exitCode, exitStatus) => {
            const mtimes = parsePathMtimeLines(pathMtimeProc.buffer);
            const changedPaths = [];

            for (let i = 0; i < pendingRefreshPaths.length; ++i) {
                const path = pendingRefreshPaths[i];
                if (pendingRefreshForce || pathMtimes[path] !== mtimes[path]) {
                    changedPaths.push(path);
                }
            }

            if (changedPaths.length === 0) {
                ready = true;
                return;
            }

            const changedMtimes = {};
            for (let i = 0; i < changedPaths.length; ++i) {
                const path = changedPaths[i];
                changedMtimes[path] = mtimes[path] ?? -1;
            }

            const fullRefresh = pendingRefreshForce && changedPaths.length === resolvedSearchPaths.length;
            startScan(changedPaths, changedMtimes, fullRefresh);
        }
    }

    Process {
        id: fileIndexProc
        property list<string> buffer: []
        command: []

        stdout: SplitParser {
            onRead: line => {
                if (line && fileIndexProc.buffer.length < root.indexLimit)
                    fileIndexProc.buffer.push(line);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("[FileSearch] File scan exited with", exitCode, exitStatus);
            }
            appendEntries(buffer, false);
            dirIndexProc.running = true;
        }
    }

    Process {
        id: dirIndexProc
        property list<string> buffer: []
        command: []

        stdout: SplitParser {
            onRead: line => {
                if (line && dirIndexProc.buffer.length < root.indexLimit)
                    dirIndexProc.buffer.push(line);
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("[FileSearch] Directory scan exited with", exitCode, exitStatus);
            }
            appendEntries(buffer, true);
            finishIndexing();
        }
    }

    FileView {
        id: cacheFileView
        path: Qt.resolvedUrl(root.cachePath)

        onLoaded: {
            try {
                const payload = JSON.parse(cacheFileView.text());
                entries = Array.isArray(payload.entries) ? payload.entries : [];
                pathMtimes = (payload.pathMtimes && typeof payload.pathMtimes === "object") ? payload.pathMtimes : {};
                pruneMtimes();
            } catch (e) {
                console.warn("[FileSearch] Failed to parse cache, resetting", e);
                entries = [];
                pathMtimes = {};
            }
            handleCacheReady();
        }

        onLoadFailed: (error) => {
            if (error !== FileViewError.FileNotFound) {
                console.warn("[FileSearch] Failed to load cache file:", error);
            }
            entries = [];
            pathMtimes = {};
            handleCacheReady();
        }
    }

    Component.onCompleted: {
        Quickshell.execDetached(["mkdir", "-p", cacheDir]);
        cacheFileView.reload();
    }
}
