#!/usr/bin/env bash
# =============================================================================
# build_zcu102.sh
# Phase 2/4 ZCU102 비트스트림 빌드 자동화 스크립트
#
# 용도: Verilog 생성 → 비트스트림 합성 → (선택) BOOT.BIN
# 주의: Vivado 경로/버전, SUB_PROJECT 명칭은 환경에 맞게 수정하세요.
#       업스트림 Chipyard에는 zcu102 SUB_PROJECT가 없습니다(포크/포팅 필요).
# =============================================================================
set -euo pipefail

# ---- 설정 ----------------------------------------------------------------
CHIPYARD_DIR="${CHIPYARD_DIR:-$HOME/chipyard}"
VIVADO_SETTINGS="${VIVADO_SETTINGS:-/tools/Xilinx/Vivado/2022.2/settings64.sh}"
SUB_PROJECT="${SUB_PROJECT:-zcu102}"
CONFIG="${1:-RocketZCU102Config}"     # 또는 GemminiZCU102Config
MODE="${2:-verilog}"                  # verilog | bitstream | all

echo "==> Chipyard: ${CHIPYARD_DIR}"
echo "==> SUB_PROJECT=${SUB_PROJECT}  CONFIG=${CONFIG}  MODE=${MODE}"

# ---- Chipyard 환경 -------------------------------------------------------
cd "${CHIPYARD_DIR}"
# shellcheck disable=SC1091
source env.sh

run_verilog() {
  echo "==> [1/2] Verilog 생성 (Config 검증)"
  make -C fpga SUB_PROJECT="${SUB_PROJECT}" CONFIG="${CONFIG}" verilog
}

run_bitstream() {
  if [ -f "${VIVADO_SETTINGS}" ]; then
    # shellcheck disable=SC1091
    source "${VIVADO_SETTINGS}"
  else
    echo "!! Vivado settings 없음: ${VIVADO_SETTINGS}"
    echo "   VIVADO_SETTINGS 환경변수로 경로를 지정하세요."
    exit 1
  fi
  echo "==> [2/2] 비트스트림 합성 (30분~2시간+)"
  make -C fpga SUB_PROJECT="${SUB_PROJECT}" CONFIG="${CONFIG}" bitstream
}

case "${MODE}" in
  verilog)   run_verilog ;;
  bitstream) run_bitstream ;;
  all)       run_verilog; run_bitstream ;;
  *) echo "사용법: $0 [CONFIG] [verilog|bitstream|all]"; exit 1 ;;
esac

echo ""
echo "==> 완료. 산출물:"
echo "    fpga/generated-src/<LONG_NAME>/obj/*.bit"
echo "    (BOOT.BIN은 Phase2 문서의 bootgen 절차 참고)"
