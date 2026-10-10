# Phase 4 — Gemmini 통합 (Kria KV260)

> 목표: Rocket Core에 Gemmini 시스톨릭 어레이 가속기를 RoCC 포트로 부착하고,
> 리눅스 사용자 공간에서 Gemmini 커스텀 명령어를 실행할 수 있게 한다.

> ⚠️ **이 Phase가 Kria 프로젝트의 핵심 난관입니다.** K26은 BRAM이 144개뿐이라
> **Gemmini 리소스 예산**(특히 SP/ACC)을 반드시 관리해야 합니다.
> 공통 개념은 [ZCU102 Phase 4](../ZCU102/Phase4_Gemmini_통합.md) 참고.

---

## 0. 요약 체크리스트

- [ ] Gemmini Config 작성 (K26 리소스에 맞춘 파라미터, **URAM 활용**)
- [ ] 시스템 버스 폭 128bit 설정 (Gemmini 필수)
- [ ] Verilog 생성 → 합성 → **리소스 초과 여부 확인**
- [ ] OpenSBI에서 RoCC 권한 활성화 (`mstatus.XS`)
- [ ] Linux 커널 `CONFIG_RISCV_ROCC=y`
- [ ] 리눅스 재부팅 후 권한 확인

---

## 1. ⚠️ Kria 리소스 예산 (먼저 계산할 것)

| 리소스 | K26 총량 | 8×8 Gemmini 단독 추정 | 여유 | 판정 |
|---|---|---|---|---|
| CLB LUT | 117,120 | ≈ 90,000 (ZU7EV 기준 8×8) | ≈ 27,000 | ⚠️ Rocket 포함 시 초과 위험 |
| BRAM(36Kb) | 144 | SP/ACC가 지배 | 적음 | ⚠️ URAM 활용 필요 |
| URAM(288Kb) | 64 (≈18Mb) | SP/ACC 매핑에 사용 | 충분 | ✅ SP/ACC를 URAM으로 |
| DSP | 1,248 | SA가 소량 사용 | 충분 | ✅ |

**전략 요약**:
1. **SP/ACC를 URAM에 매핑**해 BRAM 압박을 제거 (Gemmini는 URAM 옵션/수정 필요).
2. **SA를 4×4~8×8로 축소**, `has_training_convs=false`, `has_max_pool=false`로 로직 절감.
3. **반드시 `4×4`부터 성공**시킨 뒤 8×8로 확장.
4. 그래도 부족하면 **ZCU102/ZCU104로 이전**을 권장.

> 참고: ZU7EV(ZCU104, 230K LUT)에서 **8×8 Gemmini가 ~90K LUT(39%)** 를 사용합니다.
> K26(117K LUT)에서는 같은 구성이 ~77% → Rocket+uncore까지 더하면 초과가 유력합니다.

---

## 2. Kria용 Gemmini Config

```scala
package chipyard.fpga.kria

import chisel3._
import freechips.rocketchip.config.{Config, Parameters}
import freechips.rocketchip.diplomacy.LazyModule
import freechips.rocketchip.rocket.WithNHugeCores
import gemmini._
import chipyard.fpga.kria.WithKriaTweaks

// ---- Gemmini 부착 Config (K26 리소스 예산 반영) ----
class WithKriaGemmini extends Config((site, here, up) => {
  case BuildRoCC => up(BuildRoCC) ++ Seq(
    (p: Parameters) => {
      implicit val q = p
      val gemmini = LazyModule(new Gemmini(GemminiConfigs.defaultConfig.copy(
        meshRows    = 4,                          // ★ 4x4부터 (성공 후 8로 확장)
        meshColumns = 4,

        // 온칩 메모리: BRAM 부족 → URAM에 매핑/용량 축소
        sp_capacity  = CapacityInKilobytes(32),   // Scratchpad 32KB (여유 시 64)
        acc_capacity = CapacityInKilobytes(16),   // Accumulator 16KB

        dataflow            = Dataflow.WS,
        has_training_convs  = false,              // 로직 절약
        has_max_pool        = false,
        has_im2col          = true,               // 컨볼루션용 (여유 없으면 false)
        has_nonlinear_activations = true,

        ld_queue_length = 4,
        st_queue_length = 2,
        ex_queue_length = 4
      )))
      gemmini
    }
  )
})

// ---- 최상위 SoC Config ----
class GemminiKriaConfig extends Config(
  new WithKriaGemmini ++
  new chipyard.config.WithBroadcastManager ++
  new chipyard.config.WithSystemBusWidth(128) ++      // Gemmini 필수
  new WithKriaTweaks ++
  new WithNHugeCores(1) ++
  new chipyard.config.AbstractConfig)
```

> 실제 파일: `code/GemminiKriaConfigs.scala`
> **8×8 확장 시**: `mesh=8`, `sp_capacity=32~64KB`. 합성 후 리소스 리포트를 보고 판단.

### 2.1 URAM 매핑 포인트
Gemmini의 SP/ACC는 기본적으로 BRAM(`SeqMem`) 기반입니다. Kria에서 BRAM이 부족하면:
- Gemmini 소스의 SP/ACC `SeqMem`을 **URAM으로 강제 매핑**(Vivado `RAM_STYLE` 제약 또는 RTL 속성),
- 또는 SP 용량을 줄여 BRAM 사용을 낮춘 뒤 URAM은 대형 버퍼에 배치.

> Chipyard/Gemmini 버전에 따라 URAM 옵션이 다르므로, `generators/gemmini/src/main/scala/gemmini/*`의
> `SeqMem` 정의와 Vivado synthesis attribute를 확인하세요.

---

## 3. 버스 폭 (필수)

```scala
new chipyard.config.WithSystemBusWidth(128) ++
```

`dma_buswidth`는 SoC SystemBus `beatBytes`와 정합해야 합니다.

---

## 4. Verilog 생성 & 합성 (리소스 확인 필수)

```bash
cd $CHIPYARD_DIR && source env.sh
source /tools/Xilinx/Vivado/2022.2/settings64.sh

make -C fpga SUB_PROJECT=kria CONFIG=GemminiKriaConfig verilog     # 검증
make -C fpga SUB_PROJECT=kria CONFIG=GemminiKriaConfig bitstream   # 1~3시간+
```

합성 후 **반드시** 리포트 확인:
```tcl
open_run impl_1
report_utilization -file util.rpt
```
- LUT < ~85%, BRAM < ~90%, Timing WNS ≥ 0 이면 성공.
- 초과 시 SA/SP 축소(4×4, SP 16KB) 후 재합성.

---

## 5. ⚠️ RoCC 권한 활성화 (없으면 SIGILL)

RISC-V는 유저 공간의 커스텀 명령어 실행을 기본 금지합니다. **두 계층 모두** 처리.

### 5.1 OpenSBI (M-mode): `mstatus.XS`
```c
/* opensbi/lib/sbi/sbi_hart.c 등 hart 초기화 경로 */
unsigned long mstatus = csr_read(CSR_MSTATUS);
mstatus |= MSTATUS_XS;      /* XS 필드를 Non-zero로 */
csr_write(CSR_MSTATUS, mstatus);
```

### 5.2 Linux 커널: `CONFIG_RISCV_ROCC=y`
```
CONFIG_RISCV_ROCC=y
```
커널이 새 프로세스 생성 시 `sstatus.XS = Initial`을 세팅.

> 둘 중 하나라도 빠지면 유저 프로그램에서 **SIGILL**(RoCC 명령, badaddr) 발생.
> 패치 파일: `code/opensbi_rocc.patch`

---

## 6. 동작 확인 (스모크)

```bash
# 커널 ROCC 지원 확인 (config.gz 활성화 시)
zcat /proc/config.gz | grep RISCV_ROCC
# 이후 Phase 5의 gemmini 테스트 실행
```

---

## 7. 완료 기준

- [ ] `GemminiKriaConfig` Verilog 생성 성공
- [ ] 비트스트림 합성 성공 + **리소스 초과 없음** (LUT/BRAM 여유)
- [ ] OpenSBI 패치 적용 후 리눅스 부팅 성공
- [ ] 유저 공간에서 Gemmini 명령어 실행 시 SIGILL 없음

→ 다음: [Phase 5 — 행렬곱/컨볼루션](Phase5_행렬곱_컨볼루션.md)

---

## 8. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| 합성 실패(BRAM/LUT) | K26 리소스 초과 | SA 4×4, SP↓, URAM 매핑, 기능 Off |
| SIGILL | RoCC 권한 미설정 | `mstatus.XS` + `CONFIG_RISCV_ROCC` |
| Timing 실패 | 128bit 버스 + SA | PL 클럭 하향, SA 축소 |
| Verilog 에러 | GemminiConfig 파라미터명 불일치 | 해당 Chipyard 버전 `configs.scala` 확인 |
| DMA 오류 | 버스 폭 미정합 | `dma_buswidth` vs `beatBytes` 일치 |
