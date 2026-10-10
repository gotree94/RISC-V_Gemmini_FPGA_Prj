// =============================================================================
// GemminiZCU102Configs.scala
// Phase 4: ZCU102(XCZU9EG) + Gemmini 시스톨릭 어레이 가속기 Config
//
// 배치 위치(포팅 시): chipyard/fpga/src/main/scala/zcu102/GemminiConfigs.scala
//
// ZU9EG 리소스(LUT ~274K / BRAM 912 / DSP ~2520) 기준으로 16x16 SA를 목표.
// 리소스 부족 시 8x8 + 소용량으로 축소.
// =============================================================================

package chipyard.fpga.zcu102

import chisel3._
import freechips.rocketchip.config.{Config, Parameters}
import freechips.rocketchip.diplomacy.LazyModule
import freechips.rocketchip.rocket.WithNHugeCores
import gemmini._

// ---------------------------------------------------------------------------
// Gemmini 부착 Config
// ---------------------------------------------------------------------------
class WithZCU102Gemmini extends Config((site, here, up) => {
  case BuildRoCC => up(BuildRoCC) ++ Seq(
    (p: Parameters) => {
      implicit val q = p
      val gemmini = LazyModule(new Gemmini(GemminiConfigs.defaultConfig.copy(
        // ---- 시스톨릭 어레이 크기 ----
        meshRows    = 16,                          // 16x16 (리소스 부족 시 8)
        meshColumns = 16,

        // ---- 온칩 메모리 (전부 BRAM) ----
        sp_capacity  = CapacityInKilobytes(256),   // Scratchpad 256KB
        acc_capacity = CapacityInKilobytes(64),    // Accumulator 64KB

        // ---- 기능 블록 ----
        dataflow            = Dataflow.WS,         // Weight Stationary
        has_training_convs  = false,               // 학습용 conv 비활성(리소스 절약)
        has_max_pool        = false,
        has_im2col          = true,                // 컨볼루션용 im2col HW
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
class GemminiZCU102Config extends Config(
  new WithZCU102Gemmini ++
  new chipyard.config.WithBroadcastManager ++
  new chipyard.config.WithSystemBusWidth(128) ++   // Gemmini 필수
  new WithZCU102Tweaks ++
  new WithNHugeCores(1) ++
  new chipyard.config.AbstractConfig)
