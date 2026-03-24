#!/bin/bash
# =============================================================================
# Test script — HunyuanVideo-Foley (singolo video)
# =============================================================================
# Usage:
#   cd /workspace/HunyuanVideo-Foley
#   source .venv/bin/activate
#   bash test_foley.sh
#
# Puoi sovrascrivere qualsiasi variabile:
#   VIDEO=/workspace/media/mio_video.mp4 \
#   PROMPT="rain falling on a tin roof" \
#   bash test_foley.sh
#
# Variabili disponibili:
#   VIDEO          Percorso del video di input
#   PROMPT         Descrizione del suono da generare
#   NEG_PROMPT     Prompt negativo (default: "noisy, harsh")
#   MODEL_SIZE     xl / xxl (default: xxl)
#   ENABLE_OFFLOAD 1 = CPU offload per VRAM ridotta (default: 0)
#   STEPS          Numero di passi di denoising (default: 50)
#   GUIDANCE       Guidance scale (default: 4.5)
# =============================================================================

# ── MODIFICA QUI ─────────────────────────────────────────────────
VIDEO="${VIDEO:-assets/examples/video1.mp4}"
PROMPT="${PROMPT:-footsteps on a wooden floor}"
NEG_PROMPT="${NEG_PROMPT:-noisy, harsh}"
MODEL_SIZE="${MODEL_SIZE:-xxl}"
ENABLE_OFFLOAD="${ENABLE_OFFLOAD:-0}"
STEPS="${STEPS:-50}"
GUIDANCE="${GUIDANCE:-4.5}"
# ─────────────────────────────────────────────────────────────────

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/models"
OUTPUT_DIR="$SCRIPT_DIR/outputs"

echo "============================================================"
echo " HunyuanVideo-Foley — Test singolo video"
echo "============================================================"
echo "  Video:   $VIDEO"
echo "  Prompt:  $PROMPT"
echo "  Modello: $MODEL_SIZE"
echo "  Steps:   $STEPS  |  Guidance: $GUIDANCE"
if [ "$ENABLE_OFFLOAD" = "1" ]; then
    echo "  Offload: abilitato"
fi
echo "  Output:  $OUTPUT_DIR/"
echo "============================================================"
echo ""

mkdir -p "$OUTPUT_DIR"

# Costruisci il comando
CMD=(
    python infer.py
    --model_path "$MODELS_DIR"
    --model_size "$MODEL_SIZE"
    --single_video "$VIDEO"
    --single_prompt "$PROMPT"
    --neg_prompt "$NEG_PROMPT"
    --output_dir "$OUTPUT_DIR"
    --num_inference_steps "$STEPS"
    --guidance_scale "$GUIDANCE"
)

if [ "$ENABLE_OFFLOAD" = "1" ]; then
    CMD+=(--enable_offload)
fi

CUDA_VISIBLE_DEVICES=0 "${CMD[@]}"

echo ""
echo "============================================================"
echo " Done! Output salvato in: $OUTPUT_DIR/"
echo "============================================================"
