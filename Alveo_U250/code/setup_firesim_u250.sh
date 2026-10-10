#!/usr/bin/env bash
# =============================================================================
# setup_firesim_u250.sh
# Phase 0: Alveo U250 + FireSim 환경 구축 자동화 (개념 스크립트)
#
# 주의: FireSim은 버전별로 절차/옵션이 다릅니다. 공식 문서를 우선 확인하세요.
#       Vivado 2021.1 (U250/U280 필수), XDMA 드라이버, au250 BSP가 필요합니다.
# =============================================================================
set -euo pipefail

VIVADO_VER="2021.1"
VIVADO_SETTINGS="${VIVADO_SETTINGS:-/tools/Xilinx/Vivado/${VIVADO_VER}/settings64.sh}"
BOARDS_DIR="${BOARDS_DIR:-/tools/Xilinx/Vivado/${VIVADO_VER}/data/xhub/boards/XilinxBoardStore/boards/Xilinx}"
WORKDIR="${HOME}"
FIRESIM_DIR="${WORKDIR}/firesim"

echo "==> FireSim + Alveo U250 환경 구축 시작"

# ---- 1. 호스트 패키지 ----------------------------------------------------
if command -v apt-get >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y build-essential linux-headers-$(uname -r) \
    git wget curl python3 python3-pip device-tree-compiler
fi

# ---- 2. Vivado 버전 확인 -------------------------------------------------
if [ -f "${VIVADO_SETTINGS}" ]; then
  # shellcheck disable=SC1091
  source "${VIVADO_SETTINGS}"
  echo "==> Vivado: $(vivado -version 2>/dev/null | head -1)"
else
  echo "!! Vivado ${VIVADO_VER} 설정 파일을 찾을 수 없음: ${VIVADO_SETTINGS}"
fi

# ---- 3. au250 BSP 설치 ---------------------------------------------------
if [ ! -d "${BOARDS_DIR}/au250" ]; then
  echo "==> au250 BSP 설치"
  git clone https://github.com/Xilinx/open-nic-shell.git /tmp/open-nic-shell 2>/dev/null || true
  mkdir -p "${BOARDS_DIR}"
  cp -r /tmp/open-nic-shell/board_files/Xilinx/au250 "${BOARDS_DIR}/"
else
  echo "==> au250 BSP 이미 설치됨"
fi

# ---- 4. FireSim 클론 + 초기 빌드 ----------------------------------------
if [ ! -d "${FIRESIM_DIR}" ]; then
  git clone https://github.com/firesim/firesim.git "${FIRESIM_DIR}"
fi
cd "${FIRESIM_DIR}"
git submodule update --init --recursive

echo "==> FireSim 초기 설정 (build-setup)"
./build-setup.sh fast

# ---- 5. FPGA 인식 확인 ---------------------------------------------------
echo "==> PCIe 장치 확인"
lspci -d 10ee: || echo "!! Alveo 장치가 보이지 않습니다 (슬롯/전원 확인)"

echo ""
echo "==> 완료. 다음 세션에서:"
echo "    cd ${FIRESIM_DIR} && source sourceme-manager.sh"
echo "    (XDMA 드라이버는 커널 버전에 맞춰 별도 빌드/로드 필요)"
