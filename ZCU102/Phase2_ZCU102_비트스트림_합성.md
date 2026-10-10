# Phase 2 — ZCU102 비트스트림 합성

> 목표: Rocket Core SoC를 ZCU102의 PL에 배치하고, PS(ARM)를 메모리/부팅 서비스 계층으로 연결하여
> 비트스트림(`.bit`)과 부팅 이미지(`boot.bin`)를 만든다.

---

## 0. 개요 및 경고

ZCU102는 **PS(ARM) + PL(FPGA)** 구조이며 DDR이 PS에 붙어 있어,
단순 `.bit` 플래시만으로는 동작하지 않습니다. 다음 산출물이 필요합니다.

1. **`.bit` 비트스트림** — PL에 RISC-V SoC 구성
2. **FSBL**(First Stage Boot Loader) — PS 부팅 + DDR 초기화 + PL 로드
3. **PMU Firmware**(`pmufw.elf`) — 전력/보안 관리
4. **PL↔PS AXI 연결** — RISC-V가 PS DDR을 통해 메모리 접근
5. **(Phase 3)** 서빙 프로그램 — ARM에서 RISC-V 바이너리를 DDR에 적재

> 업스트림 Chipyard에 ZCU102가 없으므로, ZCU106의 `fpga`/`fpga-shells` 코드를 ZCU102로 포팅합니다.
> 커뮤니티 포크(`rocketchip-zcu102/chipyard`)에는 이 작업이 일부 반영돼 있습니다.

---

## 1. 전체 데이터 경로

```
        ┌─────────────────────────── ZCU102 ───────────────────────────┐
        │  PS (ARM Cortex-A53)                 PL (FPGA)               │
        │  ┌──────────────┐  AXI HP    ┌────────────────────────┐     │
        │  │ FSBL/서빙 SW │◀──────────▶│ Rocket + (Gemmini) SoC  │     │
        │  └──────┬───────┘            │  ┌────────┐            │     │
        │         │ DDR4               │  │ Rocket │            │     │
        │  ┌──────▼───────┐            │  └───┬────┘            │     │
        │  │ DDR 컨트롤러 │◀── AXI ───│  Mem Interface          │     │
        │  └──────────────┘            └────────────────────────┘     │
        │  UART/SD/Ethernet(PS MIO)                                   │
        └─────────────────────────────────────────────────────────────┘
```

---

## 2. ZCU102용 Config 작성

`fpga/src/main/scala/zcu102/Configs.scala` (또는 업스트림이면 `chipyard.fpga.zcu102` 패키지) 신설.

ZCU106 Config를 기반으로 파트/메모리/주파수만 ZCU102에 맞게 조정합니다.

```scala
package chipyard.fpga.zcu102

import chisel3._
import freechips.rocketchip.config.{Config, Parameters}
import freechips.rocketchip.diplomacy.{LazyModule}
import chipyard.{ExtTLMem}
import chipyard.fpga.zcu102.{ZCU102FPGATestHarness}

// ---- 보드 트윅: DDR 크기, 주파수, 시리얼 등 ----
class WithZCU102Tweaks extends Config((site, here, up) => {
  case chipyard.iobinders.JTAGChipIOKey => up(chipyard.iobinders.JTAGChipIOKey, site)
    .copy(driver = None)                       // PS JTAG 사용
})

// ---- Rocket Core 기반 SoC (FPGA용) ----
class RocketZCU102Config extends Config(
  new chipyard.config.WithSystemBusWidth(128) ++   // AXI 폭
  new freechips.rocketchip.subsystem.WithNBigCores(1) ++
  new WithZCU102Tweaks ++
  new chipyard.config.AbstractConfig)

// ---- 최상위 TestHarness ----
class ZCU102FPGATestHarness extends chipyard.fpga.zcu102.ZCU102FPGATestHarness
```

> 실제 Harness(`ZCU102FPGATestHarness`)는 ZCU106 Harness를 복제해
> - PS AXI HP 포트 주소/폭
> - 클럭/RESET 소스
> - UART/시리얼 바인더
> 를 ZCU102에 맞게 수정합니다. 초기에는 커뮤니티 포크의 구현을 그대로 사용하는 것이 빠릅니다.
>
> 이 저장소의 `code/ZCU102Configs.scala`를 참고하세요.

---

## 3. XDC 핀 제약

ZCU102 보드의 PL 핀맵에 맞춰 클럭/리셋/UART/LED 등을 제약합니다.

`fpga/src/main/resources/zcu102/`(또는 fpga-shells의 zcu106 대응 위치)에 XDC 배치.

핵심 항목:
- PL 클럭 입력 (예: `CLK_125MHZ` 계열 핀)
- 외부 리셋 (`CPU_RESET` 계열)
- UART (PS MIO 사용 시 PL XDC 불필요 / PL UART면 TX/RX 핀)
- `create_clock` 제약 (예: 100MHz / 125MHz)
- (선택) LED, GPIO

> 정확한 핀/전압은 **ZCU102 Board User Guide (UG1182)** 와
> 보드파일의 마스터 XDC(`part0`)를 기준으로 작성합니다.
> `code/xdc/README.md`에 안내를 두었습니다.

---

## 4. Verilog 생성 (합성 전 검증)

```bash
cd $CHIPYARD_DIR
source env.sh

# ZCU106 방식(SUB_PROJECT) 예시 — ZCU102 포크에 맞게 조정
make -C fpga SUB_PROJECT=zcu102 CONFIG=RocketZCU102Config verilog
```

성공 시 `fpga/generated-src/...` 아래 최상위 Verilog/SystemVerilog가 생성됩니다.
**이 단계에서 FIRRTL/Chisel 오류를 먼저 잡습니다** (합성 전 필수).

---

## 5. 비트스트림 합성

```bash
# Vivado 환경 로드
source /tools/Xilinx/Vivado/2022.2/settings64.sh

make -C fpga SUB_PROJECT=zcu102 CONFIG=RocketZCU102Config bitstream
```

- Vivado가 PS 블록디자인 + PL SoC + AXI 연결을 TCL로 구성하고 합성/배치배선.
- 산출물: `fpga/generated-src/<LONG_NAME>/obj/*.bit`, `.xsa` 등.
- **소요: 30분 ~ 2시간** (Rocket 단독 기준; Gemmini 추가 시 증가).

> 합성은 이 저장소의 `code/build_zcu102.sh`로 자동화할 수 있습니다.

---

## 6. PS 부팅 이미지(boot.bin) 생성

Zynq MPSoC는 `boot.bin`(=BOOT.BIN)으로 부팅합니다. 구성:

| 구성 요소 | 설명 |
|---|---|
| `zynqmp_fsbl.elf` | FSBL, DDR 초기화 + PL 로드 |
| `pmufw.elf` | PMU Firmware |
| `system.bit` | PL 비트스트림 |
| (ARM 앱) | RISC-V 이미지를 DDR에 실어주는 서빙 프로그램 (Phase 3) |
| (bl31.elf) | ATF, ARM 리눅스 부팅 시 |

생성 방법(Vivado/Vitis 2022.x):

**GUI**: Vitis → Create Boot Image → 위 파일들 순서대로 추가 → `BOOT.BIN` 생성.

**CLI(xsct)**:
```tcl
# boot.bif 예시
the_ROM_image:
{
  [bootloader, destination_cpu=a53-0] zynqmp_fsbl.elf
  [pmufw_image] pmufw.elf
  [destination_device=pl] system.bit
  [destination_cpu=a53-0, exception_level=el-2] riscv_boot.elf
}
```
```bash
bootgen -image boot.bif -arch zynqmp -o BOOT.BIN -w on
```

---

## 7. 보드에 올리기

### 7.1 JTAG로 일시 플래시 (개발 중 권장)

1. ZCU102 부팅 모드를 **JTAG**(SW6 설정)로, 전원 ON.
2. Vivado Hardware Manager → Open Target → Auto Connect.
3. `system.bit` Program Device.
4. Vitis에서 `zynqmp_fsbl.elf` + `pmufw.elf` + 서빙 ELF를 순차 run.
5. PS UART 콘솔 확인(UART0/USB-UART, 115200 8N1).

### 7.2 SD 카드 부팅 (배포/반복 부팅)

1. SD 카드를 FAT32(MBR)로 포맷.
2. `BOOT.BIN`(+ 필요 시 `image.ub`)을 루트에 복사.
3. ZCU102 부팅 모드 **SD**(SW6) → 전원 ON.

> ZCU102의 QSPI32 부팅: `SW6[4:1]=0010` 설정 후 `.mcs` 플래시.

---

## 8. 완료 기준

- [ ] `make verilog` 성공 (오류 0)
- [ ] `bitstream` 합성 성공 (timing met)
- [ ] `BOOT.BIN` 생성 성공
- [ ] 보드에서 PS UART로 FSBL 로그 출력 확인
- [ ] (핵심) PL의 RISC-V 코어가 기동 (콘솔 신호 확인)

→ 다음: [Phase 3 — 리눅스 부팅](Phase3_리눅스_부팅.md)

---

## 9. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| Timing 미충족 | 클럭 과다/배선 혼잡 | 주파수 하향, 파이프라인/Constrained 루트 |
| PS→PL AXI 접속 실패 | 주소/폭 불일치 | HP 포트 폭(128bit), 주소맵 재확인 |
| 부팅 안 됨 | boot.bin 순서/누락 | FSBL→PMUFW→bit→앱 순서 확인 |
| 보드파트 불일치 | XDC board part | Vivado Board Store에서 zcu102 설치 |
| 합성 시간 과다 | Gemmini 로직 | Phase 2에선 Rocket만 먼저 검증 |
