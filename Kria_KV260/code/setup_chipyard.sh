#!/usr/bin/env bash
# =============================================================================
# setup_chipyard.sh (Kria KV260)
# Phase 0 환경 구축 자동화 스크립트
#
# 용도: Chipyard(업스트림) 클론 + 툴체인 빌드 + conda 환경 구성
# 주의: Kria/K26은 Chipyard 공식 지원이 아니며, 업스트림 기반으로 포팅합니다.
#       경로/버전은 환경에 맞게 수정하세요. 툴체인 빌드는 30분~2시간 소요.
# =============================================================================
set -euo pipefail

# ---- 설정 ----------------------------------------------------------------
CHIPYARD_URL_UP="https://github.com/ucb-bar/chipyard.git"
WORKDIR="${HOME}"
CHIPYARD_DIR="${WORKDIR}/chipyard"

echo "==> Chipyard 설치 시작 (Kria KV260 / 업스트림 기반)"

# ---- 1. 시스템 패키지 ----------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
  echo "==> 필수 패키지 설치"
  sudo apt-get update
  sudo apt-get install -y \
    autoconf automake autotools-dev curl libmpc-dev libmpfr-dev libgmp-dev \
    gawk build-essential bison flex texinfo gperf libtool patchutils bc \
    zlib1g-dev libexpat-dev git wget python3 python3-pip python3-dev \
    device-tree-compiler libusb-1.0-0-dev default-jre
else
  echo "!! apt-get 없음: 패키지는 수동 설치하세요."
fi

# ---- 2. Conda ------------------------------------------------------------
if ! command -v conda >/dev/null 2>&1; then
  echo "==> Miniconda 설치"
  wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh
  bash /tmp/miniconda.sh -b -p "${HOME}/miniconda3"
  eval "$(${HOME}/miniconda3/bin/conda shell.bash hook)"
  conda init
fi

# ---- 3. Chipyard 클론 (업스트림 → Kria 포팅) -----------------------------
echo "==> 업스트림 Chipyard 클론"
git clone "${CHIPYARD_URL_UP}" "${CHIPYARD_DIR}" 2>/dev/null || true
cd "${CHIPYARD_DIR}"
git checkout main
./scripts/init-submodules-no-riscv-tools.sh

# ---- 4. RISC-V 툴체인 빌드 ----------------------------------------------
echo "==> RISC-V 툴체인 빌드 (오래 걸림)"
./scripts/build-toolchains.sh riscv-tools

# ---- 5. Conda 환경 -------------------------------------------------------
echo "==> Conda 환경 생성"
if [ -f conda-reqs/conda-reqs.conda-lock.yml ]; then
  conda env create -f conda-reqs/conda-reqs.conda-lock.yml || true
elif [ -f conda-reqs/chipyard.yaml ]; then
  conda env create -f conda-reqs/chipyard.yaml || true
fi
# shellcheck disable=SC1091
source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate chipyard

# ---- 6. 환경 로드 --------------------------------------------------------
echo "==> env.sh 로드"
# shellcheck disable=SC1091
source env.sh

# ---- 7. 스모크 테스트 ----------------------------------------------------
echo "==> 스모크 테스트: Verilog 생성"
make -C sims/verilator verilog CONFIG=RocketConfig

echo ""
echo "==> 완료. 다음 단계:"
echo "    cd ${CHIPYARD_DIR} && source env.sh"
echo "    (Vivado 2022.2 + Kria/K26 보드파일, bootgen/xsct 별도 설치: Phase0 문서 참고)"
echo "    Kria 포팅: fpga/fpga-shells 에 kria 서브프로젝트 신설 (Phase2 문서 참고)"
