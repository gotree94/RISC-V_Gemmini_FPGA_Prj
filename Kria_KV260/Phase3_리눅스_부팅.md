# Phase 3 — 리눅스 부팅 (Kria KV260)

> 목표: PL의 RISC-V 코어에서 OpenSBI + Linux 커널 + 루트파일시스템을 실행하여
> 인터랙티브 셸 프롬프트까지 도달한다.

> 공통 절차는 [ZCU102 Phase 3](../ZCU102/Phase3_리눅스_부팅.md)와 거의 동일합니다.
> 이 문서는 Kria 차이(부팅 이미지, 콘솔, 파일 전송)에 집중합니다.

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

- **M-mode**: OpenSBI (하드웨어 초기화, SBI 제공)
- **S-mode**: Linux (`ecall`로 SBI 사용)
- **U-mode**: 사용자 프로그램 (BusyBox 셸)

> ⚠️ 여기서의 ARM(PS)은 **별개**다. PS는 FSBL/서빙 앱을 돌려 **RISC-V 이미지를 DDR에 적재**하는 조력자일 뿐이고,
> 실제 리눅스는 **PL의 RISC-V 코어**에서 돈다.

---

## 2. 소프트웨어 스택 구성 요소

| 계층 | 도구/소스 | 산출물 |
|---|---|---|
| 펌웨어 | OpenSBI | `fw_payload.elf` (커널 내장) |
| 커널 | Linux (riscv) | `Image` |
| 루트fs | Buildroot | `rootfs.cpio.gz` (initramfs) |
| 이미지 빌드 | FireMarshal | 통합 이미지 |
| 서빙 | ARM 앱(포크 제공) | RISC-V 이미지를 DDR에 적재 |

---

## 3. 커널 콘솔 설정 (⚠️ 공통 함정)

PL UART를 TSI/서빙 프로토콜이 점유하는 구성에서는 Linux가 UART HW에 직접 접근할 수 없어
**SBI 가상 콘솔(`hvc0`)** 을 사용합니다.

커널 `.config` 핵심:
```
CONFIG_RISCV_SBI_V01=y
CONFIG_HVC_RISCV_SBI=y
CONFIG_SERIAL_EARLYCON_RISCV_SBI=y
CONFIG_CMDLINE="console=hvc0 earlycon=sbi loglevel=4 nowatchdog"
CONFIG_CMDLINE_FORCE=y
```

> PL에 별도 UART를 노출했다면 `console=ttyS0`도 가능하나, 서빙/디버그 콘솔과 겹치지 않게 주의.

---

## 4. FireMarshal로 이미지 빌드

```bash
cd $CHIPYARD_DIR && source env.sh
cd software/firemarshal
./init-submodules.sh        # 최초 1회

./marshal -v build br-base.json
./marshal -v install br-base.json
```

산출물 예: `images/prototype/br-base/br-base-bin-nodisk-flat`(플랫 바이너리), `*.cpio.gz`.

---

## 5. OpenSBI `fw_payload` 패키징

```bash
cd $CHIPYARD_DIR/software/opensbi   # 또는 포크 포함 경로
mkdir -p build && cd build
make PLATFORM=generic \
     CROSS_COMPILE=riscv64-unknown-elf- \
     FW_PAYLOAD_PATH=/path/to/Image \
     FW_FDT_PATH=/path/to/*.dtb
```

산출물: `build/platform/generic/firmware/fw_payload.elf`.
엔트리 주소는 Kria Config의 메모리맵에 맞춰야 합니다.

---

## 6. DDR에 이미지 적재 (Kria)

Kria도 RISC-V가 **PS DDR**을 사용하므로 **PS(ARM) 서빙 프로그램**이 이미지를 DDR에 씁니다.

### 6.1 서빙 프로그램 방식 (표준)
1. `BOOT.BIN`(FSBL+PMUFW+bit[+ATF])으로 PL/PS 구성
2. ARM에서 서빙 ELF 실행 → `fw_payload.elf`를 DDR 로드 주소로 기록
3. RISC-V 코어 리셋 해제 → OpenSBI/Linux 부팅

### 6.2 JTAG 직접 적재 (디버그)
Vitis/JTAG로 DDR 주소에 ELF 세그먼트 write 후 코어 기동.

### 6.3 Kria용 주의
- KV260은 PS UART가 없으므로 **서빙 앱의 로그/콘솔은 USB-UART 또는 PL UART**로 본다.
- SD 카드 부팅 시 ARM 리눅스(`image.ub`)까지 함께 쓰면 파일 전송이 편리.

---

## 7. 콘솔 및 상호작용

- 콘솔 접속: 115200 8N1 (USB-UART/PL UART).
- 부팅 로그: OpenSBI 배너 → 커널 메시지 → BusyBox 프롬프트.

```text
$ uname -a
$ cat /proc/cpuinfo      # RISC-V hart 정보 (ARM이 아님에 주의)
$ ls /
```

---

## 8. SD 카드(파일 전송) 체계 (권장)

initramfs에 매번 넣지 않으려면 SD/SDHCI를 리눅스에 노출.

1. Config에 SD 컨트롤러(PS SDHCI 또는 PL SPI) 바인딩 추가
2. 커널 `CONFIG_MMC`/`CONFIG_MMC_SDHCI` 활성화
3. 부팅 후 `mount /dev/mmcblkXpY /mnt`

---

## 9. 완료 기준

- [ ] OpenSBI 배너 출력
- [ ] 커널 부팅 완료 (init까지)
- [ ] BusyBox 셸에서 `ls`, `uname` 동작
- [ ] (권장) SD 마운트 성공

→ 다음: [Phase 4 — Gemmini 통합](Phase4_Gemmini_통합.md)

---

## 10. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| 출력 없음 | 서빙/DDR 적재 실패 | 로드 주소, AXI 연결 재확인 |
| 커널 패닉(early) | 콘솔 미지정 | `console=hvc0 earlycon=sbi` |
| 부팅 중 멈춤 | watchdog | `nowatchdog`, dts 타이머 확인 |
| PS 콘솔 안 보임 | KV260 PS UART 미노출 | USB-UART/PL UART 사용 |
| SD 인식 실패 | 드라이버/dts 누락 | 커널 config + dts 노드 추가 |
