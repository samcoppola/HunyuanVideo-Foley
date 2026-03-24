#!/bin/bash
# =============================================================================
# RunPod Setup Script — HunyuanVideo-Foley
# =============================================================================
# Esegui una volta dopo aver collegato il Network Volume al pod.
# Usage:
#   bash setup_runpod.sh                  # modello XXL (default, 20 GB VRAM)
#   MODEL_SIZE=xl bash setup_runpod.sh    # modello XL (16 GB VRAM)
#
#   Per VRAM limitata, attiva l'offload:
#   ENABLE_OFFLOAD=1 bash setup_runpod.sh              # XXL + offload (12 GB)
#   MODEL_SIZE=xl ENABLE_OFFLOAD=1 bash setup_runpod.sh  # XL + offload (8 GB)
#
# Cosa fa:
#   1. Clona la repo
#   2. Crea un venv Python 3.11 e installa le dipendenze
#   3. Scarica i pesi del modello da HuggingFace
#   4. Verifica la struttura dei file
#
# Requisiti:
#   - Network Volume montato su /workspace
#   - Nessun token HuggingFace necessario (tutti i modelli sono pubblici)
# =============================================================================

set -e

WORKSPACE="/workspace"
REPO_DIR="$WORKSPACE/HunyuanVideo-Foley"
MODELS_DIR="$REPO_DIR/models"

# Salva la cache HuggingFace sul Network Volume così non si riscarica
# ad ogni riavvio del pod (SigLIP2 + CLAP = ~1.5 GB)
export HF_HOME="$WORKSPACE/.hf_cache"
mkdir -p "$HF_HOME"
MODEL_SIZE="${MODEL_SIZE:-xxl}"
ENABLE_OFFLOAD="${ENABLE_OFFLOAD:-0}"

echo "============================================================"
echo " HunyuanVideo-Foley — RunPod Setup"
echo " Modello:  $MODEL_SIZE"
if [ "$ENABLE_OFFLOAD" = "1" ]; then
    echo " Offload:  abilitato (VRAM ridotta)"
else
    echo " Offload:  disabilitato"
fi
echo "============================================================"

# ── 1. Clona repo ────────────────────────────────────────────────
if [ ! -d "$REPO_DIR" ]; then
    echo "[1/4] Cloning repo..."
    cd "$WORKSPACE"
    git clone https://github.com/samcoppola/HunyuanVideo-Foley.git
else
    echo "[1/4] Repo già presente, aggiornamento..."
    cd "$REPO_DIR"
    git pull
fi

cd "$REPO_DIR"

# ── 2. Crea venv e installa dipendenze ───────────────────────────
echo ""
echo "[2/4] Setting up Python virtual environment..."

if ! command -v python3.11 &>/dev/null; then
    apt-get install -y python3.11 python3.11-venv
fi

if [ ! -d ".venv" ]; then
    python3.11 -m venv .venv
fi

source .venv/bin/activate

pip install --upgrade pip -q
pip install -r requirements.txt
pip install -e . -q

echo "    Dipendenze installate."

# ── 3. Scarica i pesi ─────────────────────────────────────────────
echo ""
if [ "$MODEL_SIZE" = "xxl" ]; then
    echo "[3/4] Downloading model weights (XXL, ~12 GB)..."
else
    echo "[3/4] Downloading model weights (XL, ~9 GB)..."
fi

mkdir -p "$MODELS_DIR"

export MODELS_DIR MODEL_SIZE
"$REPO_DIR/.venv/bin/python" - <<'PYEOF'
import os
from huggingface_hub import snapshot_download

local_dir  = os.environ.get("MODELS_DIR", "/workspace/HunyuanVideo-Foley/models")
model_size = os.environ.get("MODEL_SIZE", "xxl")
token      = os.environ.get("HF_TOKEN", None)

# Scarica sempre: VAE e Synchformer (condivisi tra XXL e XL)
# Scarica solo il modello principale scelto
if model_size == "xl":
    ignore_patterns = ["hunyuanvideo_foley.pth"]   # salta XXL
    print("Incluso:  hunyuanvideo_foley_xl.pth, vae_128d_48k.pth, synchformer_state_dict.pth")
    print("Saltato:  hunyuanvideo_foley.pth (XXL)")
else:
    ignore_patterns = ["hunyuanvideo_foley_xl.pth"]  # salta XL
    print("Incluso:  hunyuanvideo_foley.pth, vae_128d_48k.pth, synchformer_state_dict.pth")
    print("Saltato:  hunyuanvideo_foley_xl.pth (XL)")

print(f"Destinazione: {local_dir}")
print()

snapshot_download(
    repo_id="tencent/HunyuanVideo-Foley",
    local_dir=local_dir,
    ignore_patterns=ignore_patterns,
    token=token,
    local_dir_use_symlinks=False,
)
print("Download completo!")
PYEOF

# ── 4. Verifica struttura ─────────────────────────────────────────
echo ""
echo "[4/4] Verifying model files..."

export MODELS_DIR MODEL_SIZE
"$REPO_DIR/.venv/bin/python" - <<'PYEOF'
import os

base       = os.environ.get("MODELS_DIR", "/workspace/HunyuanVideo-Foley/models")
model_size = os.environ.get("MODEL_SIZE", "xxl")

main_model = "hunyuanvideo_foley.pth" if model_size == "xxl" else "hunyuanvideo_foley_xl.pth"

required = [
    main_model,
    "vae_128d_48k.pth",
    "synchformer_state_dict.pth",
]

all_ok = True
for fname in required:
    full   = os.path.join(base, fname)
    status = "OK" if os.path.exists(full) else "MISSING"
    if status == "MISSING":
        all_ok = False
    print(f"  [{status}] {fname}")

if all_ok:
    print("\nTutti i file presenti. Pronto per la generazione!")
else:
    print("\nAlcuni file mancanti. Controlla i log del download.")
PYEOF

# ── Done ──────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo " Setup complete!"
echo "============================================================"
echo ""
echo "Next steps:"
echo ""
echo "  cd $REPO_DIR && source .venv/bin/activate"
echo ""
echo "  1. Test rapido su un singolo video:"
echo "     bash test_foley.sh"
echo ""
echo "  2. Test personalizzato:"
echo "     VIDEO=/workspace/media/mio_video.mp4 \\"
echo "     PROMPT=\"footsteps on gravel\" \\"
echo "     bash test_foley.sh"
echo ""
echo "  3. Batch da CSV:"
echo "     bash test_foley_batch.sh"
echo ""
echo "  4. Web UI (Gradio):"
echo "     HIFI_FOLEY_MODEL_PATH=$MODELS_DIR MODEL_SIZE=$MODEL_SIZE \\"
if [ "$ENABLE_OFFLOAD" = "1" ]; then
    echo "     ENABLE_OFFLOAD=true python gradio_app.py"
else
    echo "     python gradio_app.py"
fi
echo ""
echo "  Output: $REPO_DIR/outputs/"
echo "============================================================"
