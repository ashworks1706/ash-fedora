#!/bin/bash

echo "running!";

INTERVAL=2
TOTAL_DURATION=30
MIN_VALID_RESULT_LENGTH=300
SOURCE_TYPE="monitor"  # monitor | input
TMP_PATH="/tmp/quickshell/media/songrec"
TMP_RAW="$TMP_PATH/recording.wav"
TMP_MP3="$TMP_PATH/recording.mp3"
RECORDER=""
FFMPEG_INPUT_ARGS=()

while getopts "i:t:s:" opt; do
  case $opt in
    i) INTERVAL=$OPTARG ;;
    t) TOTAL_DURATION=$OPTARG ;;
    s) SOURCE_TYPE=$OPTARG ;;
    *) exit 1 ;;
  esac
done

get_default_sink() {
    if command -v wpctl >/dev/null 2>&1; then
        wpctl status | awk '/^\\s*\\*\\s+[0-9]+\\./ {gsub("\\\\.", "", $2); print $2; exit}'
    elif command -v pactl >/dev/null 2>&1; then
        pactl info 2>/dev/null | awk -F': ' '/Default Sink:/ {print $2}'
    fi
}

get_default_source() {
    if command -v wpctl >/dev/null 2>&1; then
        wpctl status | awk '/^ {2}\\*\\s+[0-9]+\\./ {gsub("\\\\.", "", $2); print $2; exit}'
    elif command -v pactl >/dev/null 2>&1; then
        pactl info 2>/dev/null | awk -F': ' '/Default Source:/ {print $2}'
    fi
}

get_monitor_source() {
    wpctl status | awk '
        /Sources:/ { in_sources=1; next }
        in_sources && NF==0 { exit }
        in_sources && $0 ~ /^[[:space:]]*[0-9]+\./ {
            if ($0 ~ /[Mm]onitor/) {
                gsub("\\\\.", "", $2);
                print $2;
                exit;
            }
        }
    '
}

if [ "$SOURCE_TYPE" = "monitor" ]; then
    MONITOR_SOURCE=$(get_monitor_source)
    if [ -z "$MONITOR_SOURCE" ]; then
        MONITOR_SOURCE=$(get_default_sink)
    fi
elif [ "$SOURCE_TYPE" = "input" ]; then
    MONITOR_SOURCE=$(get_default_source)
else
    echo "Invalid source type"
    exit 1
fi

if ! command -v songrec >/dev/null 2>&1 || ! command -v ffmpeg >/dev/null 2>&1; then
    exit 1
fi

if command -v pw-record >/dev/null 2>&1; then
    RECORDER="pw-record"
    FFMPEG_INPUT_ARGS=("-i" "$TMP_RAW")
elif command -v parec >/dev/null 2>&1; then
    RECORDER="parec"
    FFMPEG_INPUT_ARGS=("-f" "s16le" "-ar" "44100" "-ac" "2" "-i" "$TMP_RAW")
else
    exit 1
fi

if [ -z "$MONITOR_SOURCE" ]; then
    # Fallback: try default source if monitor sink detection failed
    MONITOR_SOURCE=$(get_default_source)
fi

if [ -z "$MONITOR_SOURCE" ]; then
    exit 1
fi

cleanup() {
    rm -f "$TMP_RAW" "$TMP_MP3"
    pkill -P $$ $RECORDER >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$TMP_PATH"
if [ "$RECORDER" = "pw-record" ]; then
    pw-record --target="$MONITOR_SOURCE" --channels=2 --rate=44100 "$TMP_RAW" &
else
    parec --device="$MONITOR_SOURCE" --format=s16le --rate=44100 --channels=2 > "$TMP_RAW" &
fi
START_TIME=$(date +%s)

while true; do
    sleep "$INTERVAL"
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if (( ELAPSED >= TOTAL_DURATION )); then
        exit 0
    fi

    ffmpeg "${FFMPEG_INPUT_ARGS[@]}" -acodec libmp3lame -y -hide_banner -loglevel error "$TMP_MP3" 2>/dev/null
    RESULT=$(songrec audio-file-to-recognized-song "$TMP_MP3" 2>/dev/null || true)

    if echo "$RESULT" | grep -q '"matches": \[' && [ ${#RESULT} -gt $MIN_VALID_RESULT_LENGTH ]; then
        echo "$RESULT"
        exit 0
    fi
done
