// =============================================================================
// KriaConfigs.scala
// Phase 2: Kria K26 (Zynq UltraScale+ MPSoC)용 Rocket Core SoC Config
//
// 배치 위치(포팅 시):
//   chipyard/fpga/src/main/scala/kria/Configs.scala
//   (또는 포팅에서 정의한 chipyard.fpga.kria 패키지)
//
// 주의: 업스트림 Chipyard는 Kria/K26을 공식 지원하지 않습니다.
//       이 파일은 ZCU106 Config를 기반으로 한 "골격"이며,
//       실제 Harness/주소맵/클럭/캐리어 IO는 Kria에 맞게 조정해야 합니다.
// =============================================================================

package chipyard.fpga.kria

import chisel3._
import freechips.rocketchip.config.{Config, Parameters}
import freechips.rocketchip.diplomacy.LazyModule
import freechips.rocketchip.subsystem._
import freechips.rocketchip.rocket.WithNHugeCores

// ---------------------------------------------------------------------------
// 보드 트윅: Kria 전용 설정
//   - JTAG은 PS(JTAG-to-AXI) 경유 → PL JTAG 드라이버 None
// ---------------------------------------------------------------------------
class WithKriaTweaks extends Config((site, here, up) => {
  case chipyard.iobinders.JTAGChipIOKey =>
    up(chipyard.iobinders.JTAGChipIOKey, site).copy(driver = None)
})

// ---------------------------------------------------------------------------
// Rocket 단독 Config (Gemmini 없음) — Phase 2 검증용
// ---------------------------------------------------------------------------
class RocketKriaConfig extends Config(
  new chipyard.config.WithSystemBusWidth(128) ++        // PS AXI(HP) 폭
  new WithKriaTweaks ++
  new WithNHugeCores(1) ++                              // 단일 Rocket 코어
  new chipyard.config.AbstractConfig)

// ---------------------------------------------------------------------------
// FPGA 최상위 TestHarness (별도 구현 필요)
//   → ZCU106FPGATestHarness 를 복제하여 다음을 수정:
//     * PS AXI HP 포트 연결 (주소/폭)
//     * 캐리어 카드 PL 클럭/RESET 소스 (KV260: 100/200/300MHz 등)
//     * 캐리어별 IO (UART/SD/Ethernet) 바인딩
// ---------------------------------------------------------------------------
// class KriaFPGATestHarness extends chipyard.fpga.kria.KriaFPGATestHarness
