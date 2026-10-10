#!/usr/bin/env bash
# =============================================================================
# build_kria.sh (Kria KV260)
# Phase 2/4 비트스트림 빌드 자동화 스크립트
#
# 용도: Verilog 생성 → 비트스트림 합성 → (선택) 리소스 리포트 확인
# 주의: Kria SUB_PROJECT는 포팅 시 신설한 이름(kria/k26)을 사용하세요.
#       업스트림 Chipyard에는 kria SUB_PROJECT가 없습니다.
# =============================================================================
set -euo pipefail

# ---- 설정 ----------------------------------------------------------------
CHIPYARD_DIR="${CHIPYARD_DIR:-$HOME/chipyard}"
VIVADO_SETTINGS="${VIVADO_SETTINGS:-/tools/Xilinx/Vivado/2022.2/settings64.sh}"
SUB_PROJECT="${SUB_PROJECT:-kria}"          # 포팅 시 정한 이름
CONFIG="${1:-RocketKriaConfig}"             # 또는 GemminiKriaConfig
MODE="${2:-verilog}"                         # verilog | bitstream | all

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
  echo "==> [2/2] 비트스트림 합성 (1~3시간+)"
  make -C fpga SUB_PROJECT="${SUB_PROJECT}" CONFIG="${CONFIG}" bitstream
  echo "==> 합성 후 리소스 확인 권장: Vivado에서 impl_1 열고 report_utilization"
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
echo "    BOOT.BIN은 Phase2 문서의 Kria BSP(FSBL/PMUFW/ATF) + bootgen 절차 참고"
