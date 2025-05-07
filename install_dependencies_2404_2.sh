#!/bin/bash
set -e

# Marker to know when driver install+reboot is done
MARKER_FILE="/root/.driver_install_done"

echo "=== GPU + Docker + PyTorch Environment Setup ==="

# 1) Host NVIDIA Driver Installation (only once)
if [ ! -f "$MARKER_FILE" ]; then
  echo ""
  echo ">>> Installing NVIDIA driver on host..."
  apt-get update
  apt-get install -y \
    build-essential \
    dkms \
    software-properties-common \
    ubuntu-drivers-common

  # Auto-detect and install the recommended NVIDIA driver
  ubuntu-drivers autoinstall

  # Create marker and reboot so the new kernel module is loaded
  touch "$MARKER_FILE"
  echo ""
  echo ">> Installation of NVIDIA driver complete."
  echo ">> Rebooting now to load the new driver module..."
  reboot
  # Script stops here; rerun automatically after reboot to continue
fi

# --- From here on, the NVIDIA driver is installed & loaded ---

# 2) System Preparation & Essential Packages
echo ""
echo ">>> Installing essential packages..."
apt-get update
apt-get install -y \
  curl \
  wget \
  ca-certificates \
  gnupg \
  lsb-release \
  python3-pip \
  python3-venv

# 3) CUDA Toolkit 12.6 Installation (toolkit only, no drivers)
echo ""
echo ">>> Installing CUDA Toolkit 12.6 (no drivers)..."
# Add NVIDIA CUDA repo keyring
CUDA_KEYRING_DEB="cuda-keyring_1.1-1_all.deb"
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/${CUDA_KEYRING_DEB}
dpkg -i ${CUDA_KEYRING_DEB}
rm -f ${CUDA_KEYRING_DEB}

apt-get update
apt-get install -y cuda-toolkit-12-6

# 4) CUDA Environment Variables
echo ""
echo ">>> Configuring CUDA environment variables..."
CUDA_PATH="/usr/local/cuda-12.6"
BASHRC_UPDATED_MARKER="$HOME/.cuda126_bashrc"
if ! grep -q "${CUDA_PATH}" "$HOME/.bashrc"; then
  cat <<EOF >> "$HOME/.bashrc"

# CUDA 12.6
export PATH=${CUDA_PATH}/bin:\$PATH
export LD_LIBRARY_PATH=${CUDA_PATH}/lib64:\$LD_LIBRARY_PATH
EOF
fi

# Apply for current session
export PATH=${CUDA_PATH}/bin:$PATH
export LD_LIBRARY_PATH=${CUDA_PATH}/lib64:$LD_LIBRARY_PATH

# Optional check
if command -v nvcc &>/dev/null; then
  echo "nvcc found: $(nvcc --version | head -n1)"
else
  echo "Warning: nvcc not in PATH—reload your shell or log out/in."
fi

# 5) Docker CE Installation
echo ""
echo ">>> Installing Docker CE..."
# Remove old conflicting packages
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  apt-get remove -y $pkg >/dev/null 2>&1 || true
done
apt-get autoremove -y

# Install prerequisites
apt-get install -y ca-certificates gnupg

# Add Docker GPG key & repo
install -m0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo \$VERSION_CODENAME) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Quick hello-world test
docker run --rm hello-world

# 6) NVIDIA Container Toolkit for Docker
echo ""
echo ">>> Installing NVIDIA Container Toolkit..."
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -sL "https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list" \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# 7) Post-install: Docker group
echo ""
echo ">>> Adding user '$SUDO_USER' to 'docker' group..."
if ! getent group docker >/dev/null; then
  groupadd docker
fi
usermod -aG docker "$SUDO_USER"
echo "NOTE: You must log out and back in (or run 'newgrp docker') before using docker without sudo."

# 8) Python Virtualenv & PyTorch (CUDA-enabled)
echo ""
echo ">>> Setting up Python venv and installing PyTorch (cu126)..."
VENV_PATH="$HOME/pytorch_venv_cu126"
python3 -m venv "$VENV_PATH"
"$VENV_PATH/bin/python" -m pip install --upgrade pip

# Clean slate, then install
"$VENV_PATH/bin/pip" uninstall -y torch torchvision torchaudio || true
"$VENV_PATH/bin/pip" install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126

# Verify
"$VENV_PATH/bin/python" - <<EOF
import torch
print(f"PyTorch {torch.__version__}, CUDA available? {torch.cuda.is_available()}, CUDA {torch.version.cuda}")
EOF

# 9) Final Instructions
echo ""
echo "========================================"
echo "Setup Complete!"
echo ""
echo "• To use CUDA tools: open a fresh shell (so ~/.bashrc is loaded)."
echo "• To use Python + PyTorch: "
echo "    source $VENV_PATH/bin/activate"
echo "    python -c \"import torch; print(torch.cuda.is_available())\""
echo ""
echo "• If you haven’t rebooted since adding the driver, please do so now:"
echo "    sudo reboot"
echo "========================================"
