// =============================================================================
// ZCU102Configs.scala
// Phase 2: ZCU102(XCZU9EG)용 Rocket Core SoC Config
//
// 배치 위치(포팅 시):
//   chipyard/fpga/src/main/scala/zcu102/Configs.scala
//   (또는 커뮤니티 포크에서 정의한 chipyard.fpga.zcu102 패키지)
//
// 주의: 업스트림 Chipyard는 ZCU102를 공식 지원하지 않습니다.
//       이 파일은 ZCU106 Config를 기반으로 한 "골격"이며,
//       실제 Harness/주소맵/클럭은 ZCU102에 맞게 조정해야 합니다.
// =============================================================================

package chipyard.fpga.zcu102

import chisel3._
import freechips.rocketchip.config.{Config, Parameters}
import freechips.rocketchip.diplomacy.LazyModule
import freechips.rocketchip.subsystem._
import freechips.rocketchip.rocket.WithNHugeCores

// ---------------------------------------------------------------------------
// 보드 트윅: DDR 크기, 주파수, JTAG 등 ZCU102 전용 설정
// ---------------------------------------------------------------------------
class WithZCU102Tweaks extends Config((site, here, up) => {
  // JTAG은 PS(JTAG-to-AXI)를 사용하므로 PL JTAG 드라이버는 두지 않음
  case chipyard.iobinders.JTAGChipIOKey =>
    up(chipyard.iobinders.JTAGChipIOKey, site).copy(driver = None)
})

// ---------------------------------------------------------------------------
// Rocket 단독 Config (Gemmini 없음) — Phase 2 검증용
// ---------------------------------------------------------------------------
class RocketZCU102Config extends Config(
  new chipyard.config.WithSystemBusWidth(128) ++        // PS AXI(HP)에 맞춘 폭
  new WithZCU102Tweaks ++
  new WithNHugeCores(1) ++                              // 단일 Rocket 코어
  new chipyard.config.AbstractConfig)

// ---------------------------------------------------------------------------
// FPGA 최상위 TestHarness (별도 구현 필요)
//   → ZCU106FPGATestHarness 를 복제하여 다음을 수정:
//     * PS AXI HP 포트 연결 (주소/폭)
//     * 클럭/RESET 소스
//     * UART / 시리얼 바인더
// ---------------------------------------------------------------------------
// class ZCU102FPGATestHarness extends chipyard.fpga.zcu102.ZCU102FPGATestHarness
