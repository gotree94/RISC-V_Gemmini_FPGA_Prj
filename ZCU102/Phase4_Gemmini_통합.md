# Phase 4 — Gemmini 통합

> 목표: Rocket Core에 Gemmini 시스톨릭 어레이 가속기를 RoCC 포트로 부착하고,
> 리눅스 사용자 공간에서 Gemmini 커스텀 명령어를 실행할 수 있게 한다.

---

## 0. 요약 체크리스트

- [ ] Gemmini Config 작성 (ZCU102 리소스에 맞춘 파라미터)
- [ ] 시스템 버스 폭 128bit 설정 (Gemmini 필수)
- [ ] Verilog 생성 → 비트스트림 재합성
- [ ] OpenSBI에서 RoCC 권한 활성화 (`mstatus.XS`)
- [ ] Linux 커널 `CONFIG_RISCV_ROCC=y`
- [ ] 리눅스 재부팅 후 권한 확인

---

## 1. Gemmini 아키텍처 요약

```
Rocket Core ──RoCC──▶ Gemmini
                        ├── 시스톨릭 어레이 (meshRows × meshColumns)
                        ├── Scratchpad (BRAM)     ← 입력 저장
                        ├── Accumulator (BRAM)    ← 누산 저장
                        ├── DMA                   ← DRAM ↔ SP/ACC
                        └── (선택) im2col, pool, transpose
```

- 커스텀 명령어로 동작 → 유저 공간 실행에는 **권한 설정 필수**.
- SP/ACC가 전부 BRAM이므로 **BRAM이 주요 병목**.

---

## 2. ZCU102용 Gemmini Config

ZU9EG는 LUT ~274K / BRAM 912 / DSP ~2,520 으로, 16×16 SA까지 현실적입니다.
우선 **16×16 + SP256KB + ACC64KB + im2col** 을 목표로 합니다.

```scala
package chipyard.fpga.zcu102

import chisel3._
import freechips.rocketchip.config.{Config, Parameters}
import freechips.rocketchip.diplomacy.LazyModule
import freechips.rocketchip.rocket.WithNHugeCores
import gemmini._
import chipyard.fpga.zcu102.{WithZCU102Tweaks}

// ---- Gemmini 부착 Config ----
class WithZCU102Gemmini extends Config((site, here, up) => {
  case BuildRoCC => up(BuildRoCC) ++ Seq(
    (p: Parameters) => {
      implicit val q = p
      val gemmini = LazyModule(new Gemmini(GemminiConfigs.defaultConfig.copy(
        meshRows    = 16,                          // 16x16 systolic array
        meshColumns = 16,
        sp_capacity  = CapacityInKilobytes(256),   // Scratchpad 256KB
        acc_capacity = CapacityInKilobytes(64),    // Accumulator 64KB
        dataflow     = Dataflow.WS,                // Weight Stationary
        has_training_convs  = false,
        has_max_pool        = false,
        has_im2col          = true,                // 컨볼루션용 im2col HW
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
class GemminiZCU102Config extends Config(
  new WithZCU102Gemmini ++
  new chipyard.config.WithBroadcastManager ++
  new chipyard.config.WithSystemBusWidth(128) ++      // Gemmini 필수: 128bit 버스
  new WithZCU102Tweaks ++
  new freechips.rocketchip.rocket.WithNHugeCores(1) ++
  new chipyard.config.AbstractConfig)
```

> 리소스가 부족하면 `meshRows/Columns=8`, `sp_capacity=64KB`, `acc_capacity=32KB`로 축소하고
> `has_im2col=false` (im2col을 CPU에서 처리) 로 완화합니다.
> 실제 파일: `code/GemminiZCU102Configs.scala`

---

## 3. 버스 폭 (필수)

Gemmini DMA는 넓은 버스를 요구합니다.

```scala
new chipyard.config.WithSystemBusWidth(128) ++
```

`dma_buswidth`는 SoC SystemBus의 `beatBytes`와 연동되므로 128bit 설정과 정합해야 합니다.

---

## 4. Verilog 생성 & 비트스트림 재합성

```bash
cd $CHIPYARD_DIR && source env.sh
source /tools/Xilinx/Vivado/2022.2/settings64.sh

# 1) Config 검증 (오류 조기 발견)
make -C fpga SUB_PROJECT=zcu102 CONFIG=GemminiZCU102Config verilog

# 2) 합성 (Gemmini 추가로 1~2시간+)
make -C fpga SUB_PROJECT=zcu102 CONFIG=GemminiZCU102Config bitstream
```

---

## 5. ⚠️ RoCC 권한 활성화 (없으면 SIGILL)

RISC-V는 유저 공간의 커스텀 명령어 실행을 기본 금지합니다. 두 계층 모두 처리해야 합니다.

### 5.1 OpenSBI (M-mode): `mstatus.XS` 설정

M-mode 초기화에서 `mstatus.XS`를 Non-zero로 설정해야 유저 공간의 RoCC 상태 접근이 허용됩니다.

```c
/* opensbi/lib/sbi/sbi_hart.c 등, hart 초기화 경로에 추가 */
unsigned long mstatus = csr_read(CSR_MSTATUS);
mstatus |= MSTATUS_XS;      /* XS 필드를 Non-zero로 */
csr_write(CSR_MSTATUS, mstatus);
```

> 정확한 위치/필드값은 사용 중인 OpenSBI 버전에 맞춰 조정. (아래 패치 파일 제공)

### 5.2 Linux 커널: `CONFIG_RISCV_ROCC`

커널이 새 프로세스 생성 시 `sstatus.XS = Initial`을 세팅하도록 활성화합니다.

```c
/* arch/riscv/kernel/process.c : start_thread() */
#ifdef CONFIG_RISCV_ROCC
    regs->status |= SR_XS_INITIAL;
#endif
```

`.config`:
```
CONFIG_RISCV_ROCC=y
```

> 두 단계 중 하나라도 빠지면 `dmesg`에 `SIGILL`/`badaddr`(RoCC 명령어)이 찍힙니다.

패치 파일: `code/opensbi_rocc.patch`

---

## 6. 동작 확인 (간단 스모크)

리눅스 부팅 후, Gemmini 테스트 바이너리를 실행하기 전에 권한만 먼저 확인:

```bash
# 커널에 ROCC 지원이 켜졌는지
zcat /proc/config.gz | grep RISCV_ROCC   # (config.gz 활성화 시)

# 간단한 gemmini 테스트 (Phase 5에서 상세)
```

---

## 7. 완료 기준

- [ ] `GemminiZCU102Config` Verilog 생성 성공
- [ ] 비트스트림 합성 성공 (timing met, BRAM/LUT 여유 확인)
- [ ] OpenSBI 패치 적용 후 리눅스 부팅 성공
- [ ] 유저 공간에서 Gemmini 명령어 실행 시 SIGILL 없음

→ 다음: [Phase 5 — 행렬곱/컨볼루션](Phase5_행렬곱_컨볼루션.md)

---

## 8. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| SIGILL | RoCC 권한 미설정 | OpenSBI `mstatus.XS` + `CONFIG_RISCV_ROCC` |
| 합성 BRAM 부족 | SP/ACC 과다 | 용량 축소, SA 8×8 |
| Timing 실패 | 버스 128bit + SA | 주파수 하향, SA 축소 |
| Verilog 에러 | GemminiConfig 파라미터명 불일치 | Chipyard 버전의 `configs.scala` 파라미터 확인 |
| DMA 오류 | 버스 폭 미정합 | `dma_buswidth` vs `SystemBus beatBytes` 일치 |
