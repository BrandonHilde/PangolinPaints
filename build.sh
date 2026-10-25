#!/bin/sh
# Builds ./PangolinPaints (requires the Odin compiler on PATH; SDL3 and stb come from its vendor: collection, the font is embedded)
set -e
cd "$(dirname "$0")"
odin build src -out:PangolinPaints -o:speed
echo "Built PangolinPaints"
