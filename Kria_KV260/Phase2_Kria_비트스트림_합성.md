# Phase 2 — Kria 비트스트림 합성

> 목표: Rocket Core SoC를 Kria K26의 PL에 배치하고, PS(ARM)를 메모리/부팅 서비스 계층으로 연결하여
> 비트스트림(`.bit`)과 부팅 이미지(`BOOT.BIN`)를 만든다.

> 공통 개념(PS+PL, boot.bin 구성, AXI HP 경로)은 [ZCU102 Phase 2](../ZCU102/Phase2_ZCU102_비트스트림_합성.md)와 동일합니다.
> 이 문서는 **Kria 포팅 특이사항**에 집중합니다.

---

## 0. 개요 및 경고

- Kria K26은 **PS(ARM) + PL(FPGA)** 구조이며 DDR이 PS에 붙어 있어, 단순 `.bit` 플래시로는 동작하지 않습니다.
- 필요 산출물:
  1. **`.bit`** — PL에 RISC-V SoC 구성
  2. **FSBL** — PS 부팅 + DDR 초기화 + PL 로드
  3. **PMU Firmware(`pmufw.elf`)** — 전력/보안 관리
  4. **(ARM 리눅스 부팅 시) ATF `bl31.elf`**
  5. **PL↔PS AXI HP 연결**
  6. **(Phase 3)** ARM 서빙 프로그램 — RISC-V 이미지를 DDR에 적재
- **업스트림 Chipyard에 Kria가 없으므로 ZCU106의 `fpga`/`fpga-shells`를 Kria로 포팅**합니다.

---

## 1. 전체 데이터 경로

```
        ┌──────────────────────── Kria (SOM + Carrier) ───────────────────────┐
        │  PS (ARM Cortex-A53)                PL (FPGA, K26)                 │
        │  ┌──────────────┐  AXI HP   ┌────────────────────────┐            │
        │  │ FSBL/서빙 SW │◀─────────▶│ Rocket + (Gemmini) SoC  │            │
        │  └──────┬───────┘           │  ┌────────┐            │            │
        │         │ DDR4              │  │ Rocket │            │            │
        │  ┌──────▼───────┐           │  └───┬────┘            │            │
        │  │ DDR 컨트롤러 │◀── AXI ──│  Mem Interface          │            │
        │  └──────────────┘           └────────────────────────┘            │
        │  UART/SD/Ethernet(PS MIO, 캐리어별)                                │
        └────────────────────────────────────────────────────────────────────┘
```

> ⚠️ **Kria 특이점**: 캐리어 카드마다 노출되는 IO(UART, SD, Ethernet)가 다릅니다.
> KV260은 보드에 PS UART가 없어 **USB-JTAG/UART로 PS 콘솔**을 잡거나, PL UART를 노출해야 합니다.
> KR260은 PS UART/Ethernet이 더 잘 노출됩니다.

---

## 2. Kria용 Config 작성 (포팅)

신설 위치(예): `fpga/src/main/scala/kria/Configs.scala` + `KriaFPGATestHarness`.
ZCU106 Harness를 기반으로 다음을 Kria에 맞게 조정합니다.

- PS AXI HP 포트 주소/폭 (128bit)
- TRNG/GEM/Ethernet 등 캐리어 IO 바인딩
- 클럭/RESET 소스 (**캐리어 카드가 제공하는 PL 클럭** 사용)
- JTAG은 PS(JTAG-to-AXI) 사용 → PL JTAG 드라이버 None

```scala
package chipyard.fpga.kria

import chisel3._
import freechips.rocketchip.config.{Config, Parameters}
import freechips.rocketchip.rocket.WithNHugeCores

// ---- 보드 트윅: JTAG을 PS 경유로 ----
class WithKriaTweaks extends Config((site, here, up) => {
  case chipyard.iobinders.JTAGChipIOKey =>
    up(chipyard.iobinders.JTAGChipIOKey, site).copy(driver = None)
})

// ---- Rocket 단독 Config (Phase 2 검증용, Gemmini 없음) ----
class RocketKriaConfig extends Config(
  new chipyard.config.WithSystemBusWidth(128) ++   // PS AXI(HP) 폭
  new WithKriaTweaks ++
  new WithNHugeCores(1) ++
  new chipyard.config.AbstractConfig)
```

> 실제 파일: `code/KriaConfigs.scala`, `code/GemminiKriaConfigs.scala`
> Harness(`KriaFPGATestHarness`)는 ZCU106 Harness를 복제해 주소맵/클럭/IO만 수정합니다.

---

## 3. 클럭 (Kria 특이사항)

Kria SOM에는 PL용 클럭이 외부 핸들이 아니라 **PS가 PL로 공급하는 클럭(PL clock)** 이 기본입니다.
캐리어 카드/Vivado 보드파일에서 제공하는 클럭(예: 100/200/300MHz)을 사용합니다.

- KV260 플랫폼은 일반적으로 **100/200/300/400MHz** PL 클럭을 제공.
- RISC-V 코어 주파수는 타이밍 마진을 고려해 **50~100MHz**에서 시작 권장.
- XDC `create_clock` 제약은 보드파일의 기본 제약을 따르거나, 사용 PL 클럭 포트에 맞춰 작성.

```tcl
create_clock -period 10.000 -name pl_clk0 [get_ports pl_clk0]   # 100 MHz 예시
```

---

## 4. XDC 핀 제약

Kria는 SOM+캐리어 구조라 핀맵이 **보드파일(XPFM/Vivado board file)** 에 정의되어 있습니다.
가급적 보드파일 제약을 그대로 사용하고, PL UART/LED 등 추가 IO만 작성합니다.

핵심 항목: PL 클럭, 외부 리셋, (노출 시) UART TX/RX, LED.
정확한 핀/전압은 **Kria SOM/KV260 문서 + Vivado 보드파일**을 기준으로 합니다.
→ `code/xdc/README.md` 참고.

---

## 5. Verilog 생성 (합성 전 검증)

```bash
cd $CHIPYARD_DIR && source env.sh

# SUB_PROJECT 명칭은 포팅 시 정한 이름(kria/k26) 사용
make -C fpga SUB_PROJECT=kria CONFIG=RocketKriaConfig verilog
```

성공 시 `fpga/generated-src/...` 아래 최상위 Verilog/SystemVerilog 생성 → **합성 전 FIRRTL/Chisel 오류 제거**.

---

## 6. 비트스트림 합성

```bash
source /tools/Xilinx/Vivado/2022.2/settings64.sh
make -C fpga SUB_PROJECT=kria CONFIG=RocketKriaConfig bitstream
```

- Vivado가 PS 블록디자인(FSBL에 필요한 설정 포함) + PL SoC + AXI 연결을 TCL로 구성.
- 산출물: `fpga/generated-src/<LONG_NAME>/obj/*.bit`, `.xsa`.
- **소요: 30분~3시간** (Gemmini 추가 시 증가).

> 자동화: `code/build_kria.sh`

---

## 7. 부팅 이미지(BOOT.BIN) 생성 (Kria 특이)

Kria(Zynq MPSoC)는 `BOOT.BIN`으로 부팅합니다. **FSBL/PMUFW/ATF는 Kria BSP 기준**으로 만드는 것이 안전합니다.

| 구성 요소 | 설명 | Kria 주의 |
|---|---|---|
| `zynqmp_fsbl.elf` | FSBL (DDR 초기화 + PL 로드) | **Kria/K26 BSP**로 빌드 |
| `pmufw.elf` | PMU Firmware | Kria BSP |
| `bl31.elf` | ATF (ARM 리눅스 부팅 시) | Kria BSP |
| `system.bit` | PL 비트스트림 | Chipyard 합성 결과 |
| (서빙 ELF) | RISC-V 이미지 적재 (Phase 3) | a53-0 |

Vitis에서 `Create Boot Image`로 위 파일을 순서대로 묶거나 `bootgen` 사용:

```tcl
# boot.bif 예시
the_ROM_image:
{
  [bootloader, destination_cpu=a53-0] zynqmp_fsbl.elf
  [pmufw_image] pmufw.elf
  [destination_device=pl] system.bit
  [destination_cpu=a53-0, exception_level=el-2] bl31.elf
  [destination_cpu=a53-0, exception_level=el-1] riscv_boot.elf   ; Phase 3 서빙 앱
}
```
```bash
bootgen -image boot.bif -arch zynqmp -o BOOT.BIN -w on
```

> KV260은 Kria Starter Kit의 **플랫폼(XPFM)** 위에 올리는 경로도 있으나,
> Chipyard 커스텀 PL을 쓰려면 위 **custom BOOT.BIN** 경로가 일반적입니다.

---

## 8. 보드에 올리기

### 8.1 JTAG로 일시 플래시 (개발 중 권장)
1. 부팅 모드를 **JTAG**로, 전원 ON.
2. Vivado Hardware Manager → Open Target → Auto Connect.
3. `system.bit` Program Device.
4. Vitis에서 FSBL + PMUFW + (서빙 ELF) 순차 run.
5. **PS UART 콘솔** 확인(KV260은 USB-UART 브리지, KR260은 PS UART 핀).

### 8.2 SD 카드 부팅 (반복 부팅)
1. SD 카드를 FAT32(MBR)로 포맷.
2. `BOOT.BIN`(+ 필요 시 ARM `image.ub`)을 루트에 복사.
3. 부팅 모드 **SD** → 전원 ON.

---

## 9. 완료 기준

- [ ] `make verilog` 성공 (오류 0)
- [ ] `bitstream` 합성 성공 (timing met)
- [ ] `BOOT.BIN` 생성 성공
- [ ] PS UART로 FSBL 로그 확인
- [ ] (핵심) PL의 RISC-V 코어 기동 신호 확인

→ 다음: [Phase 3 — 리눅스 부팅](Phase3_리눅스_부팅.md)

---

## 10. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| PS 콘솔 안 보임 | KV260은 PS UART 미노출 | USB-JTAG/UART 또는 PL UART 노출 |
| Timing 미충족 | 클럭 과다/배선 혼잡 | PL 클럭 하향(50~100MHz), 주소맵 단순화 |
| PS→PL AXI 실패 | 주소/폭 불일치 | HP 포트 폭(128bit), 주소맵 재확인 |
| 부팅 안 됨 | BOOT.BIN 순서/누락 | FSBL→PMUFW→bit→ATF→앱 순서 |
| 보드파일 불일치 | Kria board 미설치 | Vivado Board Store / Vitis Kria 플랫폼 |
| BRAM 부족(Phase4) | SP/ACC 과다 | URAM 활용, 용량 축소 |
