# FPGA 기반 RISC-V CPU + AI 가속기(Gemmini) 프로젝트 정리

> 순수 FPGA 위에 RISC-V 코어를 구현하고, 리눅스를 부팅한 뒤, Gemmini 시스톨릭 어레이 가속기로
> 행렬곱(GEMM)과 컨볼루션을 실행하여 ResNet / LLM 등의 AI 추론을 가속하는 프로젝트.
> 작성일: 2026-10-10

---

## 0. 한 줄 요약

UC Berkeley의 오픈소스 생태계 **Chipyard**를 사용해 **Rocket Chip(RISC-V CPU) + Gemmini(행렬곱/컨볼루션 가속기)** SoC를 Chisel로 생성하고,
시뮬레이션 → FPGA 비트스트림 합성 → OpenSBI + Linux 부팅 → 가속기 활용 AI 추론 순으로 진행한다.

---

## 1. 왜 이 조합인가 (기술 스택 이해)

| 구성요소 | 정체 | 역할 |
|---|---|---|
| **Rocket Chip** | UC Berkeley의 RISC-V SoC 생성기 | 순서형(in-order) 5단계 파이프라인 RISC-V CPU 코어. 64비트 RV64GC. |
| **BOOM** | Berkeley Out-of-Order Machine | Rocket의 비순서형(out-of-order) 버전. Config만 교체해 사용 가능. |
| **Gemmini** | 시스톨릭 어레이 DNN 가속기 생성기 | GEMM(행렬곱) + 컨볼루션/풀링/im2col 하드웨어. RoCC로 CPU에 연결. |
| **Chisel** | Scala 기반 하드웨어 기술 언어(HDL) | 파라미터화된 하드웨어 생성. Verilog로 변환(FIRRTL) 후 합성. |
| **Chipyard** | 통합 SoC 설계 프레임워크 | 위 요소 + 버스 + 메모리 컨트롤러 + 주변장치 + 시뮬레이션/FPGA/tapeout 흐름을 묶음. |
| **FireSim** | FPGA 가속 사이클 정확 시뮬레이터 | ASIC RTL을 FPGA에서 사이클 단위로 정확히 에뮬레이션. DNN 대형 워크로드 성능 측정에 사용. |

### 1.1 RoCC(Rocket Custom Coprocessor) 인터페이스
Gemmini는 CPU의 표준 명령어가 아닌 **커스텀 명령어**로 동작한다.
CPU가 커스텀 명령어를 만나면 opcode/operand를 RoCC 포트로 가속기에 전달 → 가속기가 연산 후 결과 회신.
- 소프트웨어 측은 `gemmini.h`의 C 함수(`tiled_matmul_auto` 등)가 RoCC 명령어를 래핑한다.
- RoCC는 Gemmini 전용이 아니라 **Chipyard의 커스텀 가속기 공통 부착 방식**이다. 즉 한 번 익히면 다른 가속기(CNN/암호/신호처리)에도 동일한 경로로 적용 가능.

### 1.2 Gemmini 내부 구조 (핵심만)
- **시스톨릭 어레이(SA)**: PE(Processing Element) 격자. 크기 `meshRows × meshColumns` (예: 8×8, 16×16, 32×32).
- **Scratchpad(SP)**: BRAM으로 구현되는 온칩 입력 저장소.
- **Accumulator(ACC)**: BRAM으로 구현되는 누산 저장소.
- **DMA**: DRAM ↔ Scratchpad, ACC ↔ DRAM 데이터 이동. 버스 폭(`dma_buswidth`)에 민감.
- **im2col**: 컨볼루션을 GEMM으로 변환하는 전처리. CPU에서 할지, 하드웨어에서 할지 선택(리소스 트레이드오프).
- **데이터플로우**: WS(Weight Stationary) / OS(Output Stationary). 작은 GEMM엔 WS, 큰 GEMM엔 OS가 유리.

### 1.3 ⚠️ FPGA 프로토타이핑 vs FireSim 구분 (중요)
두 가지 방법은 목적이 다르다.

| 구분 | FPGA 프로토타이핑 | FireSim |
|---|---|---|
| 무엇을 FPGA에 올리나 | Rocket+Gemmini 설계 자체를 FPGA에 직접 구현 | ASIC RTL을 FPGA에서 **사이클 정확 에뮬레이션** |
| 동작 주파수 | FPGA 실주파수(수십~수백 MHz) | 호스트 모델(예: 3.2 GHz)로 스케일 |
| 용도 | 실제 보드에서 리눅스 부팅/동작 확인 | DNN 대형 워크로드의 정확한 **성능 측정** |
| 대표 보드 | Nexys Video, VCU118, ZCU102/106 | VCU118 (FireSim 공식 지원) |

> 논문에서 흔히 보는 "수백~수천 배 스피드업"은 대부분 **FireSim 기반 측정** 또는 **약한 in-order CPU 대비** 수치임을 유의.

---

## 2. 성능에 대한 현실적 이해 ("5000배" 주장 검증)

Gemmini 원 논문(DAC 2021)의 공식 수치:
- **ResNet50**: in-order Rocket CPU 대비 **약 2,670배** (im2col 하드웨어 + Rocket @1GHz)
  - BOOM(비순서형) 대비로는 약 1,130배
- **AlexNet**: 79.3 FPS / **SqueezeNet**: 1,760배 / **BERT**: 144배
- **MobileNetV2**: 127배 (depthwise 컨볼루션이 시스톨릭 어레이에 비효율적)
- Gemmini 최초 논문(arXiv 1911.09925): ResNet-50 **약 70배**, ResNet-152 **약 90배** (캐시 최적화 CPU 대비), MLP는 2~3 자릿수(수백~수천 배)

정리:
- "5,000배"는 **가장 좋은 조건(ResNet50 + im2col + 약한 기준 CPU)**에서도 조금 과장이며, 실제 재현 시 **수백 ~ 약 2,000~2,700배** 범위가 현실적이다.
- 스피드업의 **기준(baseline)**이 무엇이냐에 따라 천차만별이다.
  - 느린 in-order Rocket CPU 대비 → 수백~수천 배
  - GPU/서버 CPU 대비 → FPGA 원시 성능은 훨씬 뒤질 수 있음
- 성능은 **가속기 설정 + 메모리 대역폭 + 버스 폭 + im2col 위치**에 크게 좌우된다.
- 컨볼루션은 GEMM으로 변환(im2col)했을 때 가장 효율적이며, GEMM 크기가 SA 차원과 같을 때 최고 효율.

---

## 3. FPGA 보드 선정 (가장 먼저 결정할 것)

### 3.1 선정 기준 체크리스트
1. **DDR 메모리 용량**: 리눅스 + 루트파일시스템 + DNN 모델을 담아야 하므로 **최소 512MB~1GB 이상** 권장.
2. **BRAM 용량**: Gemmini의 Scratchpad/Accumulator가 전부 BRAM이므로 **BRAM이 병목**. (8×8 + 32KB/16KB로도 Artix-7 BRAM의 ~96% 사용)
3. **로직(LUT/FF)**: SA 크기 키우면 LUT 급증(2배 확대 시 면적 약 3.3배).
4. **UART / SD카드**: 리눅스 콘솔 및 파일 전송 수단. SD카드가 있으면 매우 편리.
5. **Chipyard 공식 지원 여부**: 기성 Config + XDC(핀 제약) 파일 제공 → 초기 진입 난이도 대폭 하락.
6. **Vivado 지원**: AMD/Xilinx FPGA는 필수 요소 (Chipyard FPGA 흐름이 Vivado 기반).

### 3.2 Chipyard가 공식 지원하는 보드
Chipyard는 아래 보드의 **XDC + Config를 기본 제공**한다.
- **Nexys Video** (Artix-7 XC7A200T) — 초보 입문·튜토리얼 최다
- **VCU118** (Virtex UltraScale+ XCVU9P) — 풀 리눅스 + 대형 Gemmini + FireSim 권장
- **ZCU106** (Zynq UltraScale+ ZU7EV)
- **Arty A7** (리소스 적음, 베어메탈 위주)

### 3.3 추천 후보 비교

| 보드 | FPGA | 대략 가격 | 리눅스 | Gemmini | 비고 |
|---|---|---|---|---|---|
| **Nexys Video** | Artix-7 XC7A200T | ~ $500 ~ 600 | 가능(느림) | 8×8만 간신히 | **입문 최적**, 튜토리얼 풍부, SD카드 있음 |
| **Arty A7-100T/200T** | Artix-7 | ~ $300 ~ 500 | 부담 | 제한적 | 베어메탈 실습용. 리눅스+Gemmini엔 부족 |
| **ZCU104** | Zynq UltraScale+ ZU7EV | ~ $1,900 | 가능 | 8×8만(16×16은 LUT 초과) | 비전 AI용. 16×16은 리소스 부족 |
| **ZCU102** | Zynq UltraScale+ ZU9EG | ~ $3,000 | 가능 | 16×16 가능 | 종합 평가용 |
| **VCU118** | Virtex UltraScale+ XCVU9P (2.5M LC, 6840 DSP) | ~ $8,000 ~ 9,000 | 매우 원활 | 16×16+ 원활 | **FireSim 공식 보드**, 대형 SA/LLM 최적 |
| Alveo U250 등 | UltraScale+ / PCIe 카드 | 고가 | 특수 | 가능 | 서버/가속카드 형태, 초기 난이도 높음 |

### 3.4 보드 선정 결론 (추천 시나리오)
- **학습/입문 + 실제 보드 성공 경험 우선** → **Nexys Video** (Chipyard 공식 튜토리얼이 그대로 존재, 리눅스 부팅 + 8×8 Gemmini 검증 사례 다수)
- **본격 연구 + 대형 Gemmini + LLM + FireSim** → **VCU118** (비용은 크지만 가장 원활. FireSim로 정확한 성능 측정)
- **중간 예산 + 비전 AI** → **ZCU104** (단, 16×16 SA는 LUT 초과 → 8×8)
- 예산이 매우 빠듯하면 **Arty A7**로 베어메탈만 먼저 시작 → 이후 상위 보드로 이전

> 권장 전략: **Nexys Video로 전체 파이프라인을 한 번 성공**시킨 뒤, 필요 시 VCU118로 확장.

---

## 4. 하드웨어/소프트웨어 구성 개념도

```
[호스트 PC]                                 [FPGA 보드]
  ├─ Chipyard (Chisel/Scala)                 ┌───────────────────────────────┐
  │    └─ Config 작성 → Verilog 생성         │  Rocket Core (RV64)           │
  ├─ Vivado                                  │     │ RoCC                   │
  │    └─ 합성/배치배선 → Bitstream ──JTAG──▶ │  Gemmini (시스톨릭 어레이)     │
  ├─ riscv-gnu-toolchain                     │   SP(scratchpad)/ACC(BRAM)    │
  │    └─ 프로그램/C 런타임 크로스컴파일      │     │ DMA                    │
  ├─ OpenSBI (M-mode 펌웨어)                 │  System Bus (128bit)          │
  ├─ Linux 커널 + Buildroot rootfs           │  L2 cache / DDR 컨트롤러      │
  │    └─ fw_payload.elf 패키징              │  UART-TSI / (SD카드)          │
  ├─ FireMarshal (이미지 빌드)               └───────────────────────────────┘
  └─ uart_tsi (ELF를 DDR에 로드) ──UART──────▶
```

### 4.1 부팅 흐름 (RISC-V, 4계층)
1. FPGA 전원 ON → **Boot ROM**(0x1000_0000) 실행 → DTB 주소 로드 후 **WFI**(인터럽트 대기)
2. 호스트가 **UART-TSI**로 `fw_payload.elf`를 DDR에 기록 → **CLINT MSIP**에 1 기록(소프트웨어 인터럽트)
3. CPU가 WFI에서 깨어나 DDR(0x8000_0000)로 점프 → **OpenSBI(M-mode)** 초기화
4. OpenSBI가 `mret`으로 **Linux(S-mode)** 시작 → initramfs 압축 해제 → `/init` → **BusyBox 셸(U-mode)**
5. 콘솔 IO는 **hvc0(SBI 가상 콘솔) → ecall → OpenSBI → HTIF(tohost/fromhost)** 경로로 호스트와 통신

> 핵심 함정: Nexys Video 등은 UART가 UART-TSI에 점유되어 리눅스 콘솔이 `console=hvc0` 이어야 한다.
> 커널 `CONFIG_HVC_RISCV_SBI=y`, `CONFIG_SERIAL_EARLYCON_RISCV_SBI=y` 필요.

---

## 5. 단계별 개발 로드맵

### Phase 0 — 환경 구축 (1~3일)
- OS: Linux 또는 **Windows + WSL2** (Vivado는 Windows, 소프트웨어 빌드는 WSL2 분리 운영이 편함)
- 설치 항목:
  - Chipyard (반드시 `env.sh` source), conda 환경
  - Scala/Chisel/FIRRTL (Chipyard가 자동 관리)
  - Verilator (오픈소스 시뮬레이터) 또는 VCS
  - Vivado (FPGA 합성, Windows 측)
  - riscv-gnu-toolchain (elf-gcc + linux-gcc)
  - FireMarshal (리눅스 이미지 빌드)
  - OpenSBI (Chipyard 내장)
- 검증: `hello` 예제를 Verilator로 시뮬레이션 성공시키기

### Phase 1 — Rocket Core 시뮬레이션 (2~4일)
- 목표: 시스톨릭 어레이 없는 순수 Rocket Core에서 Hello World 실행
- 핵심: `make -C sims/verilator CONFIG=RocketConfig`
- 이해: RoCC 없는 기본 SoC, UART/HTIF 콘솔 IO 동작 확인

### Phase 2 — FPGA 비트스트림 합성 (3~7일, 보드별 상이)
- 목표: 기본 Rocket SoC를 FPGA에 올려 동작(LED, UART 출력) 확인
- Nexys Video 예: `make -C fpga SUB_PROJECT=nexysvideo CONFIG=RocketNexysVideoConfig bitstream`
- 필요 시 커스텀 **XDC 핀 제약** 작성(보드 매뉴얼 기준: UART TX/RX, DDR, 클럭, 리셋)
- 산출물: `.bit` 비트스트림 → Vivado Hardware Manager로 플래시

### Phase 3 — 리눅스 부팅 (1~2주)
- 목표: FPGA 위 Rocket Core에서 인터랙티브 리눅스 셸까지
- 작업:
  1. OpenSBI + Linux 커널 + Buildroot rootfs를 **fw_payload.elf**로 패키징
  2. 커널 콘솔을 `hvc0`로 설정(SBI 가상 콘솔)
  3. `uart_tsi`로 ELF를 DDR에 로드, CPU 리셋 후 부팅
  4. (선택) UART 속도 상향(115200 → 921600)으로 로딩 시간 단축
  5. (선택) **SD카드 지원** 추가(SPI 주변장치)하면 파일 전송이 매우 편리
- 검증: 로그인/셸 프롬프트, `ls`, `cat` 등 동작

### Phase 4 — Gemmini 통합 및 리눅스 재부팅 (1~2주)
- 목표: Gemmini가 붙은 SoC를 FPGA에 올리고 리눅스에서 커스텀 명령어 사용
- 작업:
  1. **Config 작성**: `WithSmallGemmini` (보드 리소스에 맞춘 파라미터) + `WithSystemBusWidth(128)` (Gemmini는 넓은 버스 필요)
  2. 비트스트림 재합성 (Gemmini 추가로 합성 시간 1~2시간 소요)
  3. **권한 활성화(필수)**:
     - OpenSBI에서 `mstatus.XS`를 Non-zero로 설정(M-mode)
     - 리눅스 커널 `CONFIG_RISCV_ROCC=y` → `sstatus.XS = Initial`
     - 둘 중 하나라도 빠지면 유저 공간에서 **SIGILL**(Illegal Instruction)
- Gemmini Config 예시(Nexys Video / Artix-7, 8×8):
```scala
class WithSmallGemmini extends Config((site, here, up) => {
  case BuildRoCC => up(BuildRoCC) ++ Seq(
    (p: Parameters) => {
      implicit val q = p
      val gemmini = LazyModule(new Gemmini(GemminiConfigs.defaultConfig.copy(
        meshRows    = 8,                        // 8x8 array (default 16x16)
        meshColumns = 8,
        sp_capacity  = CapacityInKilobytes(32), // Scratchpad 32KB
        acc_capacity = CapacityInKilobytes(16), // Accumulator 16KB
        has_training_convs = false,             // 리소스 절약
        has_max_pool       = false,
        dataflow = Dataflow.WS,
        ld_queue_length = 4,
        st_queue_length = 2,
        ex_queue_length = 4,
        acc_read_full_width = false,
        ex_read_from_acc    = false,
        ex_write_to_spad    = false
      )))
      gemmini
    }
  )
})

class GemminiNexysVideoConfig extends Config(
  new WithSmallGemmini ++
  new WithNexysVideoTweaksFastUART ++
  new chipyard.config.WithBroadcastManager ++
  new chipyard.config.WithSystemBusWidth(128) ++ // Gemmini 필수
  new chipyard.RocketConfig)
```

### Phase 5 — 행렬곱 / 컨볼루션 실행 (1주)
- 목표: Gemmini로 순수 행렬곱(GEMM)과 컨볼루션 실행
- 소프트웨어 API:
  - `tiled_matmul_auto(M, N, K, A, B, ...)` — 타일링/DMA/스케줄링 자동 처리
  - `gemmini_fence()` — 가속기 완료 대기
- 검증: `gemmini-rocc-tests` 테스트 스위트를 시뮬레이터와 FPGA 양쪽에서 실행해 결과 일치 확인
- 프로파일링 지표 확인: Matmul / Conv / Im2col / Res-add / Pooling cycles

### Phase 6 — 실제 DNN 워크로드: ResNet & LLM (2~4주)
- 목표: ResNet-50, MobileNet, (이어서) BERT/소형 LLM 추론
- 경로:
  1. `gemmini-rocc-tests/imagenet/resnet50` 등 예제 실행
  2. **ONNX Runtime(Gemmini backend, onnxruntime-riscv)** 로 임의 ONNX 모델 추론
     - GEMM/Conv/Pooling을 Gemmini로 매핑, int8 양자화(post-training quantization)
  3. 대형 워크로드는 **FireSim**로 실행(Verilator로는 수일 걸리는 것을 수 분대로 단축)
- 주의: MobileNet 계열 depthwise conv는 시스톨릭 어레이에 비효율적 → 스피드업 낮음
- 데이터 전송: 리눅스에서 프로그램 실행 시 파일 전송 수단(SD카드 또는 initramfs 포함) 사전 준비

### Phase 7 — 프로파일링 & 최적화 (지속)
- Gemmini 성능 카운터로 병목 분석
- 튜닝 축:
  - SA 크기 (8×8 ↔ 16×16 ↔ 32×32): 성능 vs 면적/전력(2배 시 면적 ~3.3배, 전력 ~2.7배)
  - Scratchpad/Accumulator 용량 (컨볼루션은 큰 SP에 유리)
  - 데이터플로우 (WS/OS)
  - im2col 하드웨어 포함 여부 (대형 GEMM에서만 ~1.1배 이득)
  - 버스 폭 / DMA 파라미터
  - 호스트 CPU (Rocket ↔ BOOM)
- 목표: **성능-면적(PPA) 최적점** 탐색 (일반적으로 8×8 또는 16×16이 최적)

---

## 6. 핵심 명령어 모음 (참고)

```bash
# 환경
source ~/chipyard/env.sh

# 시뮬레이션 (Rocket)
cd sims/verilator && make CONFIG=RocketConfig

# 시뮬레이션 (Rocket + Gemmini)
cd sims/verilator && make CONFIG=GemminiRocketConfig

# Verilog 생성만 (빠른 Config 검증)
make -C fpga SUB_PROJECT=nexysvideo CONFIG=GemminiNexysVideoConfig verilog

# 비트스트림 합성 (Vivado 필요, 1~2시간)
make -C fpga SUB_PROJECT=nexysvideo CONFIG=GemminiNexysVideoConfig bitstream

# Gemmini 테스트 (Spike 기능 시뮬)
spike --extension=gemmini pk software/gemmini-rocc-tests/build/imagenet/resnet50

# FPGA 로딩 (UART-TSI)
uart_tsi +tty=/dev/ttyUSB0 +baudrate=921600 fw_payload.elf
```

---

## 7. 리스크 & 체크포인트

| 리스크 | 설명 | 대응 |
|---|---|---|
| BRAM 부족 | Gemmini SP/ACC가 BRAM 전량 소모 | SA/용량 축소(8×8, 32KB/16KB) |
| LUT 부족 | SA 2배 확대 시 면적 3.3배 | 16×16 이상은 고급 FPGA(VCU118) |
| 합성 시간 | Gemmini 추가 시 1~2시간 | Config 사전 `verilog` 검증 |
| 리눅스 콘솔 안 보임 | UART가 TSI에 점유 | `console=hvc0` + SBI 드라이버 |
| 유저공간 SIGILL | RoCC 권한 미설정 | OpenSBI `mstatus.XS` + `CONFIG_RISCV_ROCC` |
| 느린 로딩 | 27MB 이미지를 저속 UART 전송 | FastUART(921600) 또는 SD카드 |
| 성능 과대기대 | "수천 배"는 조건부 수치 | baseline 명확화, FireSim 측정 |
| 대형 워크로드 | Verilator로는 수일 소요 | FireSim 사용 |

---

## 8. 권장 진행 순서 (요약 체크리스트)

- [ ] Phase 0: Chipyard + Vivado + 툴체인 환경 구축
- [ ] Phase 1: Verilator로 Rocket Hello World
- [ ] Phase 2: 기본 Rocket SoC 비트스트림 → 보드 동작
- [ ] Phase 3: Linux 부팅(SD카드 또는 initramfs)
- [ ] Phase 4: Gemmini 통합 Config + RoCC 권한 + 재부팅
- [ ] Phase 5: GEMM/컨볼루션 테스트 통과
- [ ] Phase 6: ResNet-50 → ONNX Runtime → LLM 추론
- [ ] Phase 7: 프로파일링 & PPA 최적화

---

## 9. 참고 자료

- Chipyard: https://chipyard.readthedocs.io/ (Gemmini 문서: `/Generators/Gemmini.html`, Boot Process 문서)
- Gemmini GitHub: https://github.com/ucb-bar/gemmini
- Gemmini 논문(DAC 2021): "Gemmini: Enabling Systematic Deep-Learning Architecture Evaluation via Full-Stack Integration"
- Gemmini 최초 논문(arXiv 1911.09925): https://arxiv.org/pdf/1911.09925
- ONNX Runtime Gemmini Backend: EECS-2021-37 (Berkeley)
- Chipyard RISC-V/FPGA 튜토리얼(실전 예제, Nexys Video 기준): https://mikutyan4.github.io/chipyard-linux-nexys/
- Linux on VCU118: https://ucb-bar.gitbook.io/chipyard/example-projects/linux-running-on-vcu118-fpga
- FireSim: https://fires.im/
- FPGA-Rocket-Chip 단계별 가이드(Nexys4DDR): https://github.com/cnrv/fpga-rocket-chip
- Gemmini ResNet-50 FPGA 실전기(Luffca): https://www.luffca.com/2022/06/dnn-accelerator-gemmini-part2/

---

### 부록 A. 용어 정리
- **GEMM**: General Matrix Multiply, 행렬곱. AI 연산의 핵심 기본 블록.
- **시스톨릭 어레이**: 데이터가 PE 사이를 물결처럼 흐르며 병렬 연산하는 구조.
- **im2col**: 2D 컨볼루션을 행렬곱 형태로 펼치는 변환.
- **RoCC**: Rocket Custom Coprocessor, 커스텀 가속기 부착 인터페이스.
- **TSI**: Tethered Serial Interface, 호스트가 FPGA 메모리를 원격 읽기/쓰기하는 프로토콜.
- **HTIF**: Host-Target Interface, tohost/fromhost 주소로 콘솔 IO 전달.
- **SBI/OpenSBI**: M-mode 펌웨어가 S-mode(리눅스)에 제공하는 서비스 인터페이스.
- **DTB**: Device Tree Blob, 하드웨어 구성을 기술한 데이터.
- **PPA**: Performance-Per-Area, 면적 대비 성능 효율 지표.

### 부록 B. 성능 수치 요약 (참고용)
| 모델 | 스피드업(원 논문, FireSim) | 비고 |
|---|---|---|
| ResNet50 | 약 2,670× (vs in-order Rocket) | im2col HW, @1GHz |
| AlexNet | 79.3 FPS | |
| SqueezeNet v1.1 | 약 1,760× | |
| BERT | 약 144× | 언어모델 |
| MobileNetV2 | 약 127× | depthwise conv 비효율 |
| ResNet-50 (초기논문) | 약 70× | 캐시 최적화 CPU 대비 |
```
