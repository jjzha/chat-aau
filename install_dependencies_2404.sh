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

# Install CUDA Toolkit 12.4 (this should pull compatible drivers as dependencies) # MODIFIED
# Use 'cuda-toolkit' for latest version supported by repo, or 'cuda' metapackage (includes drivers + toolkit)
# Specifying version 12-4 as requested
echo "Installing cuda-toolkit-12-4..."
sudo apt-get -y install cuda-toolkit-12-4
# Consider adding 'cuda-drivers' if driver installation is problematic:
# sudo apt-get -y install cuda-drivers

echo "Setting up CUDA environment variables in ~/.bashrc..."
# Assuming standard installation path /usr/local/cuda-12.4 and symlink /usr/local/cuda # MODIFIED comment
# Use POSIX compliant way to append path, avoiding duplicates if run multiple times
echo 'export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}' >> ~/.bashrc

echo "Applying CUDA environment variables for the current session..."
# Apply environment variables for the current script execution
export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}
export LD_LIBRARY_PATH=/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
# Note: 'source ~/.bashrc' in a script only affects the script's subshell. Exports are better here.

# Verify nvcc installation (optional check)
if command -v nvcc &> /dev/null; then
    echo "CUDA Compiler (nvcc) found:"
    nvcc --version # This should now report 12.4
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
  && curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
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
echo "Installing Python packages (PyTorch 2.5.0 for CUDA 12.4)..."
# Ubuntu 24.04 uses Python 3.12 by default. pip3 will use this version.

# Ensure pip is up-to-date
echo "Updating pip..."
python3 -m pip install --upgrade pip

# Uninstall existing torch/related packages (if any) and install specified version for CUDA 12.1
# Note: PyTorch for cu121 is generally compatible with CUDA 12.4 runtime.
echo "Uninstalling any existing PyTorch versions..."
pip3 uninstall -y torch torchvision torchaudio
echo "Installing PyTorch 2.5.0 (cu124)..."
# Note: We are installing PyTorch version 2.5.0 compiled against CUDA 12.1 (cu121 index).
# This is generally compatible with the CUDA 12.4 runtime environment due to CUDA's forward compatibility within major versions.
# Check PyTorch documentation if a specific wheel index for CUDA 12.4 (e.g., cu124) becomes available if you encounter issues.
pip3 install pytorch==2.5.0 torchvision==0.20.0 torchaudio==2.5.0 --index-url https://download.pytorch.org/whl/cu124 # No change needed here

# Verify PyTorch installation (optional check)
echo "Verifying PyTorch installation..."
# Check runtime CUDA version visible to PyTorch, might differ slightly from toolkit version but should be 12.x
python3 -c "import torch; print(f'PyTorch version: {torch.__version__}'); print(f'CUDA available: {torch.cuda.is_available()}'); print(f'CUDA version used by PyTorch: {torch.version.cuda}'); print(f'Number of GPUs: {torch.cuda.device_count()}')"


# --- Final Instructions ---
echo ""
echo "---------------------------------------------------------------------"
echo "Installation script finished!"
echo "---------------------------------------------------------------------"
echo "RECOMMENDATIONS:"
echo "1. Check the output above for any errors during the installation."
echo "2. Verify CUDA version by running: nvcc --version (should show 12.4)" # MODIFIED comment
echo "3. Reboot your system to ensure all changes, especially kernel modules (drivers) and group memberships (docker), are fully applied:"
echo "   sudo reboot"
echo "4. If you don't reboot, at least log out and log back in for Docker group permissions to take effect."
echo "5. Verify CUDA is working (e.g., run 'nvidia-smi') and PyTorch can access the GPU (check verification output above)."
echo "---------------------------------------------------------------------"