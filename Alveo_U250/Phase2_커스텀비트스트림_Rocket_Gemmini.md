# Phase 2 — 커스텀 비트스트림 (Rocket + Gemmini)

> 목표: FireSim에서 Rocket Core + Gemmini 가속기를 포함한 **커스텀 TARGET_CONFIG**를 정의하고,
> Alveo U250용 비트스트림을 빌드한다.

---

## 0. 요약 체크리스트

- [ ] FireSim용 Gemmini TARGET_CONFIG 작성
- [ ] Gemmini 파라미터(SA/SP/ACC/im2col) 결정
- [ ] `sample_config_build_recipes.yaml`에 새 레시피 추가
- [ ] Verilog 생성 검증 (`firesim` pre-build step)
- [ ] 비트스트림 빌드 + HWDB 등록

---

## 1. FireSim에서 Gemmini 사용

FireSim의 타깃 설계는 Chipyard의 Config 체계를 그대로 사용합니다.
따라서 **Chipyard Config에 Gemmini를 붙이고, 이를 FireSim TARGET_CONFIG로 지정**하면 됩니다.

- FireSim은 Gemmini를 포함한 SoC RTL을 Golden Gate로 변환하여 FPGA에서 사이클 정확 실행.
- **Gemmini 원논문의 성능 수치가 바로 이 FireSim + 젬미니 조합에서 측정**되었습니다.
- 리눅스 사용자 공간에서 Gemmini 호출 가능(논문의 end-to-end 평가 조건).

---

## 2. Gemmini TARGET_CONFIG 예시

FireSim 프로젝트(`sims/firesim-staging/sample_project` 등)의 Scala 소스에 Config 추가.

```scala
package firesim.sample_project   // 실제 패키지에 맞게

import chisel3._
import freechips.rocketchip.config.{Config, Parameters}
import freechips.rocketchip.diplomacy.LazyModule
import freechips.rocketchip.rocket.WithNHugeCores
import gemmini._

// ---- Alveo U250용 대형 Gemmini Config ----
// U250: LUT 1.728M / DSP 12,288 / DDR 64GB → 16x16~32x32 현실적
class WithU250Gemmini extends Config((site, here, up) => {
  case BuildRoCC => up(BuildRoCC) ++ Seq(
    (p: Parameters) => {
      implicit val q = p
      val gemmini = LazyModule(new Gemmini(GemminiConfigs.defaultConfig.copy(
        // 시스톨릭 어레이 (16x16 기준, 여유 있으면 32x32)
        meshRows    = 16,
        meshColumns = 16,

        // 온칩 메모리 (BRAM/URAM)
        sp_capacity  = CapacityInKilobytes(256),
        acc_capacity = CapacityInKilobytes(64),

        // 기능
        dataflow   = Dataflow.WS,
        has_im2col = true,                    // 컨볼루션 가속용
        has_training_convs = false,
        has_max_pool       = false,
        has_nonlinear_activations = true
      )))
      gemmini
    }
  )
})

// ---- FireSim Rocket + Gemmini 타깃 ----
class FireSimGemminiRocketConfig extends Config(
  new WithU250Gemmini ++
  new chipyard.config.WithBroadcastManager ++
  new chipyard.config.WithSystemBusWidth(128) ++   // Gemmini 필수
  new WithNHugeCores(1) ++
  new chipyard.config.AbstractConfig)
```

> 32×32 SA도 U250에서는 리소스상 가능하지만, 면적/타이밍/전력 부담이 큽니다(면적 ≈3.3배).
> 처음엔 **16×16 + im2col + WS**로 기준점을 잡고 DSE(Phase 4)로 확장하세요.

---

## 3. 빌드 레시피 추가

`sims/firesim-staging/sample_config_build_recipes.yaml`:

```yaml
alveo_u250_gemmini_rocket_16x16:
    DESIGN: FireSim
    TARGET_CONFIG: FireSimGemminiRocketConfig
    PLATFORM_CONFIG: WithAutoILA
    platform_config_args:
        fpga_frequency: 100          # 타이밍 여유에 따라 조정
        # mem0: DDR 채널 설정
    deploy_strategy: no_nic
    TARGET_PROJECT_MAKEFRAG: firesim/sample_project/Makefrag
    bit_builder_recipe: bit-builder-recipes/xilinx_alveo_u250.yaml
    sim_type: fireboom              # 또는 rocket
```

그리고 `deploy/config_build.yaml`:

```yaml
builds_to_run:
    - alveo_u250_gemmini_rocket_16x16
```

---

## 4. Verilog 생성 검증 (합성 전)

RTL 오류를 합성 전에 잡습니다(FIRRTL/Chisel 에러 조기 발견).

```bash
cd ~/firesim
source sourceme-manager.sh
# Chipyard 쪽에서 또는 firesim의 pre-build 단계로 Verilog 생성
cd sims/firesim-staging   # (버전별 경로)
make -C ../../sims/verilator verilog CONFIG=FireSimGemminiRocketConfig
```

> FireSim에 맞는 Verilog 생성 경로/변수는 버전에 따라 다릅니다.
> `firesim buildbitstream`의 pre-build 단계만 먼저 실행해도 됩니다(캐시됨).

---

## 5. 비트스트림 빌드 + 등록

```bash
firesim buildbitstream -r deploy/config_build.yaml
```

완료 후 출력되는 HWDB 항목을 `config_hwdb.yaml`에 붙여넣기:

```yaml
alveo_u250_gemmini_rocket_16x16:
    bitstream_tar: deploy/results-build/<...>/<...>.tar.gz
    deploy_manager: XilinxAlveoU250InstanceDeployManager
```

---

## 6. 리소스 예상 (U250, 16×16 Gemmini)

| 리소스 | 예상 사용 | 비고 |
|---|---|---|
| LUT | 수십만 | 여유 충분 |
| BRAM/URAM | SP/ACC 지배 | 256KB+64KB → 여유 |
| DSP | int8이면 적음 | 12,288 중 일부 |

> int8 GEMM은 DSP를 많이 쓰지 않을 수 있습니다(합성 옵션 의존). timing/배선이 실제 관건.

---

## 7. 완료 기준

- [ ] `FireSimGemminiRocketConfig` Verilog 생성 성공
- [ ] 레시피 추가 후 `buildbitstream` 성공
- [ ] HWDB 등록 완료
- [ ] (선택) 32×32 SA 빌드 검증

→ 다음: [Phase 3 — 가속기 워크로드 구동](Phase3_가속기_워크로드_구동.md)

---

## 8. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| Verilog 에러 | GemminiConfig 파라미터 불일치 | Chipyard 버전 `configs.scala` 확인 |
| timing 실패 | 32×32/im2col/주파수 | SA 축소, `fpga_frequency` 하향 |
| BRAM 부족 | SP/ACC 과다 | 용량 축소 |
| FireSim이 Gemmini 미인식 | import/경로 | `package gemmini._` 및 빌드 클래스패스 확인 |
| SIM 종료 안 됨 | litmus 등 | `terminate_on_completion` 설정 |
