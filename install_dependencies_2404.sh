#!/bin/bash

# Exit script if any command fails
set -e

# --- System Preparation ---
echo "Updating package list and upgrading system..."
sudo apt-get update && sudo apt-get upgrade -y

echo "Installing essential packages and Python 3 pip..."
# Note: Python 3.12 is default on Ubuntu 24.04, satisfying 3.11+ requirement.
# We removed the specific 'nvidia-driver-xxx'. CUDA installation below should handle drivers.
# If driver issues occur, consider 'sudo ubuntu-drivers autoinstall' or installing 'cuda-drivers' package separately.
sudo apt-get install -y build-essential dkms curl wget ca-certificates gnupg lsb-release software-properties-common python3-pip

# --- NVIDIA CUDA Toolkit Installation (Ubuntu 24.04 Method) ---
echo "Installing NVIDIA CUDA Toolkit 12.4 for Ubuntu 24.04..." # MODIFIED

# Add NVIDIA GPG key and repository (Network Installer Method for Ubuntu 24.04)
# Reference: Check NVIDIA CUDA download page for the latest specific commands for 24.04 if issues arise.
# This keyring method is standard.
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update
# Clean up downloaded keyring package immediately after use
sudo rm cuda-keyring_1.1-1_all.deb

# Install CUDA Toolkit 12.6 (this should pull compatible drivers as dependencies) # MODIFIED
# Use 'cuda-toolkit' for latest version supported by repo, or 'cuda' metapackage (includes drivers + toolkit)
echo "Installing cuda-toolkit-12-6..."
sudo apt-get -y install cuda-toolkit-12-6
# Consider adding 'cuda-drivers' if driver installation is problematic:
sudo apt-get -y install cuda-drivers

echo "Setting up CUDA environment variables in ~/.bashrc..."
# Assuming standard installation path /usr/local/cuda-12.6 and symlink /usr/local/cuda
# Use POSIX compliant way to append path, avoiding duplicates if run multiple times
echo 'export PATH=/usr/local/cuda-12.6/bin${PATH:+:${PATH}}' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' >> ~/.bashrc

echo "Applying CUDA environment variables for the current session..."
# Apply environment variables for the current script execution
export PATH=/usr/local/cuda-12.6/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda-12.6/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
# Note: 'source ~/.bashrc' in a script only affects the script's subshell. Exports are better here.

# Verify nvcc installation (optional check)
if command -v nvcc &> /dev/null; then
    echo "CUDA Compiler (nvcc) found:"
    nvcc --version # This should now report 12.6
else
    echo "Warning: nvcc not found in PATH immediately. Check CUDA installation and environment variables."
    echo "You might need to reload your shell profile (e.g., source ~/.bashrc) or reboot."
fi

# --- Docker Installation ---
echo "Installing Docker..."

# Remove old versions if any for clean install
echo "Removing potentially conflicting Docker packages..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y $pkg > /dev/null 2>&1 || true # Ignore errors if package not installed
done
sudo apt-get autoremove -y
# Optionally remove old Docker data - uncomment with caution!
# echo "Removing old Docker data directories..."
# sudo rm -rf /var/lib/docker
# sudo rm -rf /var/lib/containerd

# Install Docker dependencies
sudo apt-get install -y ca-certificates gnupg

# Add Docker's official GPG key and repository
echo "Setting up Docker repository..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo rm -f /etc/apt/keyrings/docker.gpg # Remove if it exists
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Use VERSION_CODENAME which should be 'noble' for Ubuntu 24.04
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker packages
echo "Installing Docker packages..."
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify Docker installation (optional check)
echo "Verifying Docker installation..."
sudo docker run hello-world

# --- NVIDIA Container Toolkit Installation ---
echo "Installing NVIDIA Container Toolkit..."
# distribution variable handles OS version automatically (should be ubuntu24.04)
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)

echo "Setting up NVIDIA Container Toolkit repository for $distribution..."
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
  && curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

echo "Installing NVIDIA Container Toolkit package..."
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# Configure NVIDIA Container Toolkit for Docker
echo "Configuring Docker to use NVIDIA runtime..."
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# --- Docker Post-installation Steps ---
echo "Adding current user ($USER) to the docker group..."
# Check if group exists, create if not (though install should create it)
if ! getent group docker > /dev/null; then
    sudo groupadd docker
fi
sudo usermod -aG docker $USER
echo "IMPORTANT: You need to log out and log back in, or start a new shell (e.g., using 'newgrp docker') for group changes to take effect."

# --- Python Package Installation ---
echo "Installing Python packages (PyTorch for CUDA 12.6)..."
# Ubuntu 24.04 uses Python 3.12 by default.

# 1. Ensure python3-venv is installed (add it to the initial apt install if not already)
echo "Ensuring python3-venv is installed..."
sudo apt-get install -y python3-venv # Add this line if not already present earlier

# 2. Define path for virtual environment
VENV_PATH="$HOME/pytorch_venv_cu126" # Changed name slightly for clarity
echo "Creating Python virtual environment at $VENV_PATH..."

# 3. Create the virtual environment
python3 -m venv "$VENV_PATH"

# 4. Ensure pip is up-to-date within the venv
echo "Updating pip within the virtual environment..."
"$VENV_PATH/bin/python" -m pip install --upgrade pip

# 5. Install PyTorch using the venv's pip
# Uninstall existing torch/related packages (if any) - likely not needed in a fresh venv but safe
echo "Uninstalling any existing PyTorch versions from venv (if any)..."
"$VENV_PATH/bin/pip" uninstall -y torch torchvision torchaudio
echo "Installing PyTorch (cu126) into the virtual environment..."
# Using the specific pip from the virtual environment
# Check PyTorch website (https://pytorch.org/get-started/locally/) if the cu126 index URL causes issues.
# CUDA 12.1 wheels (cu121) are generally compatible with newer CUDA 12.x runtimes if needed.
"$VENV_PATH/bin/pip" install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126

# 6. Verify PyTorch installation using the venv's python
echo "Verifying PyTorch installation within the virtual environment..."
# Using the specific python from the virtual environment
"$VENV_PATH/bin/python" -c "import torch; print(f'PyTorch version: {torch.__version__}'); print(f'CUDA available: {torch.cuda.is_available()}'); print(f'CUDA version used by PyTorch: {torch.version.cuda}'); print(f'Number of GPUs: {torch.cuda.device_count()}')"

# echo 'source /path/to/pytorch_venv_cu126/bin/activate' >> ~/.bashrc
# source ~/.bashrc

# --- Add note about activating the venv for later use ---
echo ""
echo "---------------------------------------------------------------------"
echo "Python packages installed in virtual environment: $VENV_PATH"
echo "To use these packages (like PyTorch) in your terminal, activate the environment:"
echo "source $VENV_PATH/bin/activate"
echo "To deactivate, simply type: deactivate"
echo "---------------------------------------------------------------------"


# --- Final Instructions ---
echo ""
echo "---------------------------------------------------------------------"
echo "Installation script finished!"
echo "---------------------------------------------------------------------"
echo "IMPORTANT - ACTION REQUIRED:"
echo "============================"
echo "A REBOOT IS STRONGLY RECOMMENDED to ensure all changes are applied:"
echo "  sudo reboot"
echo ""
echo "Why reboot?"
echo "1. NVIDIA Drivers: Ensures kernel modules are correctly loaded."
echo "2. Docker Group: Applies your user's membership to the 'docker' group."
echo "3. CUDA PATH: Finalizes the system configuration (alternatives system)"
echo "   so the '/usr/local/cuda' symlink works correctly and commands like 'nvcc'"
echo "   are found in new terminal sessions."
echo ""
echo "If you don't reboot, you MUST AT LEAST log out and log back in, or start"
echo "a new terminal session for the Docker group and CUDA PATH changes to take effect."
echo ""
echo "After rebooting/re-logging in, verify:"
echo "- Run 'id' to check if 'docker' is listed in your groups."
echo "- Run 'nvidia-smi' to check driver status."
echo "- Run 'nvcc --version' to check CUDA toolkit access (should show 12.6)."
echo "- Check PyTorch GPU access via the Python virtual environment (activate it first!)."
echo "---------------------------------------------------------------------"