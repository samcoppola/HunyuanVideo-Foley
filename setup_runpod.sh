#!/bin/bash
# =============================================================================
# RunPod Setup Script — HunyuanVideo-Foley (GPU pod)
# =============================================================================
# Esegui sul pod GPU dopo aver collegato il Network Volume.
# Se hai già eseguito download_models.sh su un pod CPU, salta il download.
#
# Usage:
#   bash setup_runpod.sh                  # modello XL (default, 16 GB VRAM)
#   MODEL_SIZE=xxl bash setup_runpod.sh   # modello XXL (20 GB VRAM)
#
#   Per VRAM limitata, attiva l'offload:
#   ENABLE_OFFLOAD=1 bash setup_runpod.sh              # XL + offload (8 GB)
#   MODEL_SIZE=xxl ENABLE_OFFLOAD=1 bash setup_runpod.sh  # XXL + offload (12 GB)
#
# Cosa fa:
#   1. Clona la repo (o aggiorna se già presente)
#   2. Crea venv riutilizzando il PyTorch CUDA del pod
#   3. Scarica i pesi (salta se già presenti da download_models.sh)
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
MODEL_SIZE="${MODEL_SIZE:-xl}"
ENABLE_OFFLOAD="${ENABLE_OFFLOAD:-0}"

# Cache HuggingFace sul Network Volume (evita re-download a ogni riavvio)
export HF_HOME="$WORKSPACE/.hf_cache"
mkdir -p "$HF_HOME"

echo "============================================================"
echo " HunyuanVideo-Foley — RunPod Setup (GPU)"
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

# ffmpeg sul Network Volume — persiste tra riavvii del pod
mkdir -p "$WORKSPACE/bin"
export PATH="$WORKSPACE/bin:$PATH"
if ! command -v ffmpeg &>/dev/null; then
    echo "    ffmpeg non trovato, installazione su Network Volume..."
    wget -q https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz
    tar xf ffmpeg-release-amd64-static.tar.xz
    cp ffmpeg-*-amd64-static/ffmpeg "$WORKSPACE/bin/"
    rm -rf ffmpeg-*-amd64-static ffmpeg-release-amd64-static.tar.xz
    echo "    ffmpeg installato in $WORKSPACE/bin/"
else
    echo "    ffmpeg già presente."
fi
if ! command -v python3.11 &>/dev/null; then
    apt-get install -y python3.11 python3.11-venv
fi

if [ ! -d ".venv" ]; then
    # --system-site-packages: riusa il PyTorch CUDA già installato nel pod
    python3.11 -m venv .venv --system-site-packages
fi

source .venv/bin/activate

pip install --upgrade pip

if python -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then
    echo "    PyTorch CUDA già disponibile: $(python -c 'import torch; print(torch.__version__)')"
else
    echo "    PyTorch CUDA non trovato, installazione da requirements..."
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124
fi

# Installa tutte le dipendenze (inclusa la versione custom di transformers già in requirements.txt)
pip install -r requirements.txt
pip install -e .

echo "    Dipendenze installate."

# ── 3. Scarica i pesi (salta se già presenti) ─────────────────────
echo ""
MAIN_MODEL="hunyuanvideo_foley_xl.pth"
[ "$MODEL_SIZE" = "xxl" ] && MAIN_MODEL="hunyuanvideo_foley.pth"

if [ -f "$MODELS_DIR/$MAIN_MODEL" ] && [ -f "$MODELS_DIR/vae_128d_48k.pth" ] && [ -f "$MODELS_DIR/synchformer_state_dict.pth" ]; then
    echo "[3/4] Modelli già presenti, download saltato."
else
    if [ "$MODEL_SIZE" = "xxl" ]; then
        echo "[3/4] Downloading model weights (XXL, ~12 GB)..."
    else
        echo "[3/4] Downloading model weights (XL, ~10 GB)..."
    fi

    mkdir -p "$MODELS_DIR"

    export MODELS_DIR MODEL_SIZE
    "$REPO_DIR/.venv/bin/python" - <<'PYEOF'
import os
from huggingface_hub import snapshot_download

local_dir  = os.environ["MODELS_DIR"]
model_size = os.environ.get("MODEL_SIZE", "xl")

if model_size == "xl":
    ignore_patterns = ["hunyuanvideo_foley.pth"]
    print("Incluso:  hunyuanvideo_foley_xl.pth, vae_128d_48k.pth, synchformer_state_dict.pth")
else:
    ignore_patterns = ["hunyuanvideo_foley_xl.pth"]
    print("Incluso:  hunyuanvideo_foley.pth, vae_128d_48k.pth, synchformer_state_dict.pth")

print(f"Destinazione: {local_dir}")
snapshot_download(
    repo_id="tencent/HunyuanVideo-Foley",
    local_dir=local_dir,
    ignore_patterns=ignore_patterns,
    local_dir_use_symlinks=False,
)
print("Download completo!")
PYEOF
fi

# ── 4. Verifica struttura ─────────────────────────────────────────
echo ""
echo "[4/4] Verifying model files..."

export MODELS_DIR MODEL_SIZE
"$REPO_DIR/.venv/bin/python" - <<'PYEOF'
import os

base       = os.environ["MODELS_DIR"]
model_size = os.environ.get("MODEL_SIZE", "xl")
main_model = "hunyuanvideo_foley.pth" if model_size == "xxl" else "hunyuanvideo_foley_xl.pth"

all_ok = True
for fname in [main_model, "vae_128d_48k.pth", "synchformer_state_dict.pth"]:
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
echo "  cd $REPO_DIR && source .venv/bin/activate"
echo ""
echo "  1. Test rapido:"
echo "     bash test_foley.sh"
echo ""
echo "  2. Test personalizzato:"
echo "     VIDEO=/workspace/media/mio_video.mp4 \\"
echo "     PROMPT=\"footsteps on gravel\" \\"
echo "     bash test_foley.sh"
echo ""
echo "  3. Web UI (Gradio):"
echo "     HIFI_FOLEY_MODEL_PATH=$MODELS_DIR MODEL_SIZE=$MODEL_SIZE \\"
if [ "$ENABLE_OFFLOAD" = "1" ]; then
    echo "     ENABLE_OFFLOAD=true python gradio_app.py"
else
    echo "     python gradio_app.py"
fi
echo "============================================================"
