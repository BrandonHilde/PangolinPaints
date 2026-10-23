#!/bin/sh
# Builds ./PangolinPaints (requires the Odin compiler on PATH; raylib ships with Odin's vendor: collection)
set -e
cd "$(dirname "$0")"
odin build src -out:PangolinPaints -o:speed
echo "Built PangolinPaints"
