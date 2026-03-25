#!/bin/bash
# =============================================================================
# Download script — HunyuanVideo-Foley (CPU pod)
# =============================================================================
# Esegui su un pod CPU economico per scaricare tutti i modelli sul Network
# Volume prima di passare al pod GPU.
#
# Usage:
#   bash download_models.sh              # modello XL (default, ~10 GB)
#   MODEL_SIZE=xxl bash download_models.sh  # modello XXL (~13 GB)
#
# Requisiti:
#   - Network Volume montato su /workspace
#   - Nessun token HuggingFace necessario
# =============================================================================

set -e

WORKSPACE="/workspace"
REPO_DIR="$WORKSPACE/HunyuanVideo-Foley"
MODELS_DIR="$REPO_DIR/models"
MODEL_SIZE="${MODEL_SIZE:-xl}"

# Cache HF sul Network Volume (SigLIP2 + CLAP, ~1.5 GB)
export HF_HOME="$WORKSPACE/.hf_cache"
mkdir -p "$HF_HOME"

echo "============================================================"
echo " HunyuanVideo-Foley — Download modelli (CPU pod)"
echo " Modello: $MODEL_SIZE"
echo "============================================================"

# ── 1. Clona repo ────────────────────────────────────────────────
if [ ! -d "$REPO_DIR" ]; then
    echo "[1/3] Cloning repo..."
    cd "$WORKSPACE"
    git clone https://github.com/samcoppola/HunyuanVideo-Foley.git
else
    echo "[1/3] Repo già presente, aggiornamento..."
    cd "$REPO_DIR"
    git pull
fi

# ── 2. Scarica i pesi principali ──────────────────────────────────
echo ""
if [ "$MODEL_SIZE" = "xxl" ]; then
    echo "[2/3] Downloading model weights (XXL, ~12 GB)..."
else
    echo "[2/3] Downloading model weights (XL, ~10 GB)..."
fi

mkdir -p "$MODELS_DIR"

# Installa huggingface_hub se non disponibile (CPU pod minimale)
if ! python3 -c "import huggingface_hub" 2>/dev/null; then
    python3 -m pip install huggingface_hub -q
fi

export MODELS_DIR MODEL_SIZE
python3 - <<'PYEOF'
import os
from huggingface_hub import snapshot_download

local_dir  = os.environ["MODELS_DIR"]
model_size = os.environ.get("MODEL_SIZE", "xl")

if model_size == "xl":
    ignore_patterns = ["hunyuanvideo_foley.pth"]
    print("Incluso:  hunyuanvideo_foley_xl.pth, vae_128d_48k.pth, synchformer_state_dict.pth")
    print("Saltato:  hunyuanvideo_foley.pth (XXL)")
else:
    ignore_patterns = ["hunyuanvideo_foley_xl.pth"]
    print("Incluso:  hunyuanvideo_foley.pth, vae_128d_48k.pth, synchformer_state_dict.pth")
    print("Saltato:  hunyuanvideo_foley_xl.pth (XL)")

print(f"Destinazione: {local_dir}")
print()

snapshot_download(
    repo_id="tencent/HunyuanVideo-Foley",
    local_dir=local_dir,
    ignore_patterns=ignore_patterns,
    local_dir_use_symlinks=False,
)
print("Download completo!")
PYEOF

# ── 3. Pre-scarica cache HuggingFace (SigLIP2 + CLAP) ────────────
echo ""
echo "[3/3] Pre-downloading HuggingFace model cache (SigLIP2 + CLAP, ~1.5 GB)..."
echo "      Questo evita il re-download ad ogni riavvio del pod GPU."

python3 - <<'PYEOF'
from huggingface_hub import snapshot_download

print("Scaricando google/siglip2-base-patch16-512...")
snapshot_download(repo_id="google/siglip2-base-patch16-512", local_dir_use_symlinks=False)

print("Scaricando laion/larger_clap_general...")
snapshot_download(repo_id="laion/larger_clap_general", local_dir_use_symlinks=False)

print("Cache HuggingFace scaricata!")
PYEOF

# ── Verifica ──────────────────────────────────────────────────────
echo ""
echo "Verifica file..."

export MODELS_DIR MODEL_SIZE
python3 - <<'PYEOF'
import os

base       = os.environ["MODELS_DIR"]
model_size = os.environ.get("MODEL_SIZE", "xl")
main_model = "hunyuanvideo_foley.pth" if model_size == "xxl" else "hunyuanvideo_foley_xl.pth"

for fname in [main_model, "vae_128d_48k.pth", "synchformer_state_dict.pth"]:
    full   = os.path.join(base, fname)
    status = "OK" if os.path.exists(full) else "MISSING"
    print(f"  [{status}] {fname}")
PYEOF

echo ""
echo "============================================================"
echo " Download completo!"
echo "============================================================"
echo ""
echo " Ora spegni questo pod CPU e avvia un pod GPU con lo stesso"
echo " Network Volume, poi esegui:"
echo ""
echo "   bash /workspace/HunyuanVideo-Foley/setup_runpod.sh"
echo "============================================================"
