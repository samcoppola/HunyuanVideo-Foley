#!/bin/bash
# =============================================================================
# Download script — HunyuanVideo-Foley (CPU pod)
# =============================================================================
# Scarica modelli e cache HuggingFace sul Network Volume.
# Funziona su qualsiasi pod minimale, indipendentemente dal mount point.
#
# Usage:
#   bash download_models.sh                        # XL (default, ~10 GB)
#   MODEL_SIZE=xxl bash download_models.sh         # XXL (~12 GB)
#   WORKSPACE=/vol bash download_models.sh         # workspace custom
# =============================================================================

set -e

WORKSPACE="${WORKSPACE:-/workspace}"
REPO_DIR="$WORKSPACE/HunyuanVideo-Foley"
MODELS_DIR="$REPO_DIR/models"
MODEL_SIZE="${MODEL_SIZE:-xl}"
export HF_HOME="$WORKSPACE/.hf_cache"

echo "============================================================"
echo " HunyuanVideo-Foley — Download modelli"
echo " Workspace: $WORKSPACE"
echo " Modello:   $MODEL_SIZE"
echo "============================================================"

mkdir -p "$MODELS_DIR" "$HF_HOME"

# ── 1. Trova Python >= 3.9 ───────────────────────────────────────
echo ""
echo "[1/4] Ricerca Python..."
PYTHON=""
for candidate in python3.13 python3.12 python3.11 python3.10 python3.9 python3; do
    if command -v "$candidate" &>/dev/null; then
        version=$("$candidate" -c "import sys; print(sys.version_info[:2])" 2>/dev/null)
        if "$candidate" -c "import sys; exit(0 if sys.version_info >= (3,9) else 1)" 2>/dev/null; then
            PYTHON="$candidate"
            echo "    Trovato: $PYTHON ($version)"
            break
        fi
    fi
done

if [ -z "$PYTHON" ]; then
    echo "ERRORE: nessun Python >= 3.9 trovato. Installane uno prima."
    exit 1
fi

# ── 2. Bootstrap pip se mancante ─────────────────────────────────
echo ""
echo "[2/4] Verifica pip..."
if ! "$PYTHON" -m pip --version &>/dev/null; then
    echo "    pip non trovato, installazione via get-pip.py..."
    curl -sS https://bootstrap.pypa.io/get-pip.py | "$PYTHON"
    echo "    pip installato."
else
    echo "    pip già disponibile."
fi

"$PYTHON" -m pip install huggingface_hub -q
echo "    huggingface_hub pronto."

# ── 3. Clona repo ────────────────────────────────────────────────
echo ""
echo "[3/4] Repo..."
if [ ! -d "$REPO_DIR" ]; then
    if command -v git &>/dev/null; then
        cd "$WORKSPACE"
        git clone https://github.com/samcoppola/HunyuanVideo-Foley.git
    else
        apt-get install -y git -q
        cd "$WORKSPACE"
        git clone https://github.com/samcoppola/HunyuanVideo-Foley.git
    fi
else
    echo "    Repo già presente."
fi

# ── 4. Download modelli ───────────────────────────────────────────
echo ""
echo "[4/4] Download modelli da HuggingFace..."

export MODELS_DIR MODEL_SIZE HF_HOME

"$PYTHON" - <<'PYEOF'
import os
from huggingface_hub import snapshot_download

models_dir = os.environ["MODELS_DIR"]
model_size = os.environ.get("MODEL_SIZE", "xl")

# ── Modello principale + VAE + Synchformer ──
if model_size == "xl":
    ignore = ["hunyuanvideo_foley.pth"]
    included = "hunyuanvideo_foley_xl.pth, vae_128d_48k.pth, synchformer_state_dict.pth"
else:
    ignore = ["hunyuanvideo_foley_xl.pth"]
    included = "hunyuanvideo_foley.pth, vae_128d_48k.pth, synchformer_state_dict.pth"

print(f"  Incluso:  {included}")
print(f"  Dest:     {models_dir}")

snapshot_download(
    repo_id="tencent/HunyuanVideo-Foley",
    local_dir=models_dir,
    ignore_patterns=ignore,
    local_dir_use_symlinks=False,
)
print("  Modello scaricato!")

# ── Cache HuggingFace (SigLIP2 + CLAP) ──
# Vengono usati a runtime — meglio averli già sul volume
print("\n  Scaricando google/siglip2-base-patch16-512 (~400 MB)...")
snapshot_download(repo_id="google/siglip2-base-patch16-512", local_dir_use_symlinks=False)

print("  Scaricando laion/larger_clap_general (~600 MB)...")
snapshot_download(repo_id="laion/larger_clap_general", local_dir_use_symlinks=False)

print("\n  Cache HuggingFace pronta!")

# ── Verifica ──
print("\n--- Verifica file ---")
main = "hunyuanvideo_foley.pth" if model_size == "xxl" else "hunyuanvideo_foley_xl.pth"
all_ok = True
for f in [main, "vae_128d_48k.pth", "synchformer_state_dict.pth"]:
    path = os.path.join(models_dir, f)
    ok = os.path.exists(path)
    print(f"  [{'OK' if ok else 'MISSING'}] {f}")
    if not ok:
        all_ok = False

if all_ok:
    print("\nTutto OK — pronto per il pod GPU!")
else:
    print("\nAlcuni file mancanti, controlla i log.")
    exit(1)
PYEOF

echo ""
echo "============================================================"
echo " Download completo!"
echo " Ora spegni questo pod e avvia un pod GPU con lo stesso"
echo " Network Volume, poi:"
echo "   bash $REPO_DIR/setup_runpod.sh"
echo "============================================================"
