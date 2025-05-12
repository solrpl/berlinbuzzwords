### GCP info
# image: Rocky Linux 9 Accelerator Optimized, with NVidia 570 driver built on 2025-04
# 8 CPUs, 30GB RAM, 50GB disk

### install llama.cpp
sudo dnf install git cmake -y
git clone https://github.com/ggml-org/llama.cpp.git

# install dependencies
sudo dnf groupinstall "Development Tools" -y           # gcc, g++, make, etc.

# CUDA toolkit
sudo dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo
sudo dnf install cuda-toolkit -y
sudo reboot

# build
cd llama.cpp
export PATH=${PATH}:/usr/local/cuda-12.9/bin # https://docs.nvidia.com/cuda/cuda-installation-guide-linux/index.html#environment-setup
cmake -B build -DGGML_CUDA=ON -DLLAMA_CURL=OFF
cmake --build build --config Release -j8 # 8 threads

### get the model
curl -L https://huggingface.co/unsloth/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q5_K_M.gguf -o Llama-3.2-3B-Instruct-Q5_K_M.gguf

### run the benchmark
build/bin/llama-bench -m Llama-3.2-3B-Instruct-Q5_K_M.gguf -p 2000 -n 300 -b 2048 -fa 1