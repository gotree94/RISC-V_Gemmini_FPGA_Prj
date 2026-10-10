# Phase 3 — 리눅스 부팅

> 목표: PL의 RISC-V 코어에서 OpenSBI + Linux 커널 + 루트파일시스템을 실행하여
> 인터랙티브 셸 프롬프트까지 도달한다.

---

## 0. 요약 체크리스트

- [ ] Linux 커널 빌드 (RISC-V 64, SBI 콘솔)
- [ ] Buildroot 루트파일시스템 빌드
- [ ] OpenSBI(`fw_payload`)로 커널+루트fs 패키징
- [ ] RISC-V 이미지를 DDR에 적재 (ARM 서빙 SW / JTAG)
- [ ] 콘솔 확인 (`hvc0` 경로)
- [ ] (권장) SD 카드로 파일 전송 체계 구축

---

## 1. 리눅스 부팅 4계층 복습

```
BootROM(WFI) → [이미지 적재] → OpenSBI(M-mode) → Linux(S-mode) → BusyBox(U-mode)
                                    │
                            SBI (ecall 인터페이스)
```

- **M-mode**: OpenSBI. 최초 실행, 하드웨어 초기화, SBI 제공.
- **S-mode**: Linux. OpenSBI의 SBI 호출(`ecall`)로 콘솔/타이머 사용.
- **U-mode**: 사용자 프로그램(BusyBox 셸 등).

---

## 2. 소프트웨어 스택 구성 요소

| 계층 | 도구/소스 | 산출물 |
|---|---|---|
| 펌웨어 | OpenSBI | `fw_payload.elf` (커널 내장) |
| 커널 | Linux (riscv) | `Image` |
| 루트fs | Buildroot | `rootfs.cpio.gz` (initramfs) |
| 이미지 빌드 | FireMarshal | 통합 이미지 |
| 서빙 | ARM 펌웨어 (포크 제공) | RISC-V 이미지를 DDR에 적재 |

---

## 3. 커널 콘솔 설정 (⚠️ Zynq/FPGA 공통 함정)

PL UART를 TSI/서빙 프로토콜이 점유하는 구성에서는 Linux가 UART 하드웨어에 직접 접근할 수 없습니다.
이 경우 **SBI 가상 콘솔(`hvc0`)** 을 사용합니다.

커널 `.config` 핵심:
```
CONFIG_RISCV_SBI_V01=y
CONFIG_HVC_RISCV_SBI=y
CONFIG_SERIAL_EARLYCON_RISCV_SBI=y
CONFIG_CMDLINE="console=hvc0 earlycon=sbi loglevel=4 nowatchdog"
CONFIG_CMDLINE_FORCE=y
```

> PL에 별도 UART를 노출한 구성이면 `console=ttyS0`도 가능하지만, 서빙/디버그와 겹치지 않게 주의.

---

## 4. FireMarshal로 이미지 빌드

```bash
cd $CHIPYARD_DIR
source env.sh
cd software/firemarshal
./init-submodules.sh        # 최초 1회 (Phase 0에서 완료)

# br-base.json 기반 Buildroot 이미지 (기본 프로필)
./marshal -v build br-base.json
./marshal -v install br-base.json
```

산출물 예:
- `images/prototype/br-base/br-base-bin-nodisk-flat` (플랫 바이너리)
- 루트fs 관련 `*.cpio.gz`

> 커널은 FireMarshal 프로필이 자동 구성하거나, 커스텀 `.config`를 프로필에 넣어 빌드합니다.

---

## 5. OpenSBI `fw_payload` 패키징

OpenSBI의 `fw_payload` 모드는 커널을 펌웨어에 **내장**하여 단일 ELF로 만듭니다.

```bash
cd $CHIPYARD_DIR/software/opensbi   # 또는 포크에 포함된 경로
mkdir -p build && cd build

# 예: make PLATFORM=generic FW_PAYLOAD_PATH=<Image> ...
make PLATFORM=generic \
     CROSS_COMPILE=riscv64-unknown-elf- \
     FW_PAYLOAD_PATH=/path/to/Image \
     FW_FDT_PATH=/path/to/*.dtb
```

산출물: `build/platform/generic/firmware/fw_payload.elf`

실행 흐름:
- 부팅 엔트리(예: `0x8000_0000`)에서 OpenSBI 시작
- 초기화 후 커널 엔트리(예: `0x8020_0000`)로 점프

> 정확한 엔트리/주소는 ZCU102 Config의 메모리맵에 맞춰야 합니다.

---

## 6. DDR에 이미지 적재

ZCU102는 RISC-V가 PS DDR을 사용하므로, **PS(ARM) 서빙 프로그램**이 이미지를 DDR에 씁니다.

### 6.1 서빙 프로그램 방식 (포크 표준)

1. `BOOT.BIN`(FSBL+PMUFW+bit)으로 PL 구성
2. ARM에서 서빙 ELF 실행 → `fw_payload.elf`를 DDR의 로드 주소로 기록
3. RISC-V 코어 리셋 해제 → OpenSBI/Linux 부팅

### 6.2 JTAG 직접 적재 (디버그)

Vitis/JTAG로 DDR 주소에 ELF 세그먼트를 직접 write 후 코어 기동.

### 6.3 UART-TSI 방식 (PL UART 노출 시)

Nexys Video/VCU118처럼 UART로 호스트가 DDR에 기록하는 방식. ZCU102에서는
PS 경유가 일반적이므로 보조 수단으로 고려.

---

## 7. 콘솔 및 상호작용

- PS UART(예: UART0/USB-UART)를 115200 8N1로 접속.
- 부팅 로그: OpenSBI 배너 → 커널 메시지 → BusyBox 셸 프롬프트.
- `hvc0` 콘솔이므로 SBI ecall → (서빙 경로) → 호스트로 출력됩니다.

```text
# 로그인 후 예시
$ uname -a
$ cat /proc/cpuinfo      # RISC-V hart 정보
$ ls /
```

---

## 8. SD 카드로 파일 전송 체계 구축 (권장)

initramfs에 매번 프로그램을 넣으면 재빌드가 잦습니다. SD 카드(SPI/SDHCI)를
리눅스에 노출하면 파일 교체가 쉬워집니다.

1. Config에 SD 컨트롤러(PS SDHCI 또는 PL SPI) 바인딩 추가
2. 커널에 해당 드라이버 + `CONFIG_MMC`/`CONFIG_MMC_SDHCI` 활성화
3. 부팅 후 `mount /dev/mmcblkXpY /mnt`

---

## 9. 완료 기준

- [ ] OpenSBI 배너 출력
- [ ] 커널 부팅 완료 (init까지)
- [ ] BusyBox 셸에서 명령 실행 (`ls`, `uname`)
- [ ] (권장) SD 마운트 성공

→ 다음: [Phase 4 — Gemmini 통합](Phase4_Gemmini_통합.md)

---

## 10. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| 출력 없음 | 서빙/DDR 적재 실패 | 로드 주소, AXI 연결 재확인 |
| 커널 패닉(early) | 콘솔 미지정 | `console=hvc0 earlycon=sbi` |
| 부팅 중 멈춤 | watchdog | `nowatchdog`, dts 타이머 확인 |
| 로그인 불가 | rootfs 비밀번호 | FireMarshal 설정에서 패스워드 제거 |
| SD 인식 실패 | 드라이버/dts 누락 | 커널 config + dts 노드 추가 |
