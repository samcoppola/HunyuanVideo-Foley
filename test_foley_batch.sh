#!/bin/bash
# =============================================================================
# Batch test script — HunyuanVideo-Foley (CSV)
# =============================================================================
# Usage:
#   cd /workspace/HunyuanVideo-Foley
#   source .venv/bin/activate
#   bash test_foley_batch.sh
#
# Oppure con CSV personalizzato:
#   CSV=/workspace/media/mia_lista.csv bash test_foley_batch.sh
#
# Formato CSV (obbligatorio):
#   video,prompt
#   /path/to/video1.mp4,"footsteps on gravel"
#   /path/to/video2.mp4,"rain falling on a tin roof"
#
# Variabili disponibili:
#   CSV            Percorso del file CSV di input
#   MODEL_SIZE     xl / xxl (default: xxl)
#   ENABLE_OFFLOAD 1 = CPU offload per VRAM ridotta (default: 0)
#   STEPS          Numero di passi di denoising (default: 50)
#   GUIDANCE       Guidance scale (default: 4.5)
#   SKIP_EXISTING  1 = salta file già generati (default: 1)
# =============================================================================

# ── MODIFICA QUI ─────────────────────────────────────────────────
MODEL_SIZE="${MODEL_SIZE:-xxl}"
ENABLE_OFFLOAD="${ENABLE_OFFLOAD:-0}"
STEPS="${STEPS:-50}"
GUIDANCE="${GUIDANCE:-4.5}"
SKIP_EXISTING="${SKIP_EXISTING:-1}"
# ─────────────────────────────────────────────────────────────────

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# ffmpeg è sul Network Volume
export PATH="/workspace/bin:$PATH"
MODELS_DIR="$SCRIPT_DIR/models"
OUTPUT_DIR="$SCRIPT_DIR/outputs"

# Crea un CSV di esempio se non ne viene fornito uno
if [ -z "$CSV" ]; then
    CSV="/tmp/foley_batch_$$.csv"
    cat > "$CSV" <<'CSVEOF'
video,prompt
assets/examples/video1.mp4,footsteps on a wooden floor
assets/examples/video2.mp4,water flowing in a stream
CSVEOF
    echo "Nessun CSV fornito — uso CSV di esempio: $CSV"
fi

echo "============================================================"
echo " HunyuanVideo-Foley — Batch Processing"
echo "============================================================"
echo "  CSV:     $CSV"
echo "  Modello: $MODEL_SIZE"
echo "  Steps:   $STEPS  |  Guidance: $GUIDANCE"
if [ "$ENABLE_OFFLOAD" = "1" ]; then
    echo "  Offload: abilitato"
fi
echo "  Output:  $OUTPUT_DIR/"
echo "============================================================"
echo ""

mkdir -p "$OUTPUT_DIR"

CMD=(
    python infer.py
    --model_path "$MODELS_DIR"
    --model_size "$MODEL_SIZE"
    --csv_path "$CSV"
    --output_dir "$OUTPUT_DIR"
    --num_inference_steps "$STEPS"
    --guidance_scale "$GUIDANCE"
)

if [ "$ENABLE_OFFLOAD" = "1" ]; then
    CMD+=(--enable_offload)
fi

if [ "$SKIP_EXISTING" = "1" ]; then
    CMD+=(--skip_existing)
fi

CUDA_VISIBLE_DEVICES=0 "${CMD[@]}"

echo ""
echo "============================================================"
echo " Done! Output salvato in: $OUTPUT_DIR/"
echo "============================================================"
