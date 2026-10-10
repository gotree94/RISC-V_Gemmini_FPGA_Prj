// =============================================================================
// GemminiKriaConfigs.scala
// Phase 4: Kria K26 + Gemmini 시스톨릭 어레이 가속기 Config
//
// 배치 위치(포팅 시): chipyard/fpga/src/main/scala/kria/GemminiConfigs.scala
//
// ⚠️ K26 리소스 한계:
//   - CLB LUT 117,120 / BRAM 144(36Kb) / URAM 64(288Kb) / DSP 1,248
//   - 8x8 Gemmini 단독이 ZU7EV에서 ~90K LUT → K26(117K)에서는 ~77% (Rocket 포함 초과 위험)
//   - BRAM 부족 → SP/ACC는 URAM 매핑 또는 용량 축소 필요
//
// 전략: 4x4로 시작 → 합성 성공 후 8x8 확장. 리소스 초과 시 기능 Off/용량 축소.
// =============================================================================

package chipyard.fpga.kria

import chisel3._
import freechips.rocketchip.config.{Config, Parameters}
import freechips.rocketchip.diplomacy.LazyModule
import freechips.rocketchip.rocket.WithNHugeCores
import gemmini._
import chipyard.fpga.kria.WithKriaTweaks

// ---------------------------------------------------------------------------
// Gemmini 부착 Config (K26 리소스 예산 반영: 4x4 시작)
// ---------------------------------------------------------------------------
class WithKriaGemmini extends Config((site, here, up) => {
  case BuildRoCC => up(BuildRoCC) ++ Seq(
    (p: Parameters) => {
      implicit val q = p
      val gemmini = LazyModule(new Gemmini(GemminiConfigs.defaultConfig.copy(
        // ---- 시스톨릭 어레이 크기 (Kria: 4x4부터) ----
        meshRows    = 4,                          // 8로 확장 가능(리소스 허용 시)
        meshColumns = 4,

        // ---- 온칩 메모리 (BRAM 부족 → URAM 매핑/축소) ----
        sp_capacity  = CapacityInKilobytes(32),   // Scratchpad 32KB (여유 시 64)
        acc_capacity = CapacityInKilobytes(16),   // Accumulator 16KB

        // ---- 기능 블록 ----
        dataflow            = Dataflow.WS,         // Weight Stationary
        has_training_convs  = false,               // 로직 절약
        has_max_pool        = false,
        has_im2col          = true,                // 컨볼루션용 (여유 없으면 false)
        has_nonlinear_activations = true,

        // ---- 큐 깊이 ----
        ld_queue_length = 4,
        st_queue_length = 2,
        ex_queue_length = 4
      )))
      gemmini
    }
  )
})

// ---------------------------------------------------------------------------
// 최상위 SoC Config (Rocket + Gemmini)
//   ⚠️ Gemmini는 128bit 시스템 버스가 필요
// ---------------------------------------------------------------------------
class GemminiKriaConfig extends Config(
  new WithKriaGemmini ++
  new chipyard.config.WithBroadcastManager ++
  new chipyard.config.WithSystemBusWidth(128) ++   // Gemmini 필수
  new WithKriaTweaks ++
  new WithNHugeCores(1) ++
  new chipyard.config.AbstractConfig)

// ---------------------------------------------------------------------------
// 참고: SP/ACC는 기본적으로 BRAM(SeqMem) 기반이므로,
// BRAM이 부족하면 Vivado synthesis attribute(RAM_STYLE=ultra)로 URAM에 강제 매핑하거나
// Gemmini 소스의 메모리 파라미터를 조정하세요.
// ---------------------------------------------------------------------------
