### GCP info
# image: Rocky Linux 9 Accelerator Optimized, with NVidia 570 driver built on 2025-04
# 8 CPUs, 30GB RAM, 50GB disk

# check if the card is recognized
nvidia-smi

# CUDA toolkit + driver
sudo dnf config-manager --set-enabled crb
sudo dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo

### in case it's not recognized, let's get the latest driver
sudo dnf install epel-release -y
sudo dnf module enable nvidia-driver:latest-dkms -y
sudo dnf install cuda-drivers --allowerasing -y
# only this should be enough + crb and add-repo?
sudo dnf install cuda -y --nobest --allowerasing

sudo dnf install cuda-toolkit -y --nobest --allowerasing
sudo reboot

# check if the card is recognized
nvidia-smi

# install llama.cpp
sudo dnf install git cmake -y
git clone https://github.com/ggml-org/llama.cpp.git

# install dependencies
sudo dnf groupinstall "Development Tools" -y           # gcc, g++, make, etc.

# build
cd llama.cpp
export PATH=${PATH}:/usr/local/cuda-12.9/bin # https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#environment-setup
cmake -B build -DGGML_CUDA=ON -DLLAMA_CURL=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release -j$(nproc) # use all cores

### get the model
curl -L https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q5_K_M.gguf -o Llama-3.2-3B-Instruct-Q5_K_M.gguf

### run the benchmark
build/bin/llama-bench -m Llama-3.2-3B-Instruct-Q5_K_M.gguf -p 2000 -n 300 -b 2048 -fa 1