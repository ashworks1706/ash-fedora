#!/bin/bash
# Keyboard backlight cycle script for ASUS laptops

# Get current brightness level
current=$(asusctl -k 2>&1 | grep -oP "(?<=brightness: )\w+")

case "$1" in
    --down)
        case "$current" in
            "High") asusctl -k med ;;
            "Med") asusctl -k low ;;
            "Low") asusctl -k off ;;
            "Off") asusctl -k off ;;
        esac
        ;;
    --up)
        case "$current" in
            "Off") asusctl -k low ;;
            "Low") asusctl -k med ;;
            "Med") asusctl -k high ;;
            "High") asusctl -k high ;;
        esac
        ;;
    *)
        echo "Usage: $0 [--down|--up]"
        exit 1
        ;;
esac
