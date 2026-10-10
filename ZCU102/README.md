# ZCU102 기반 RISC-V + Gemmini 프로젝트

> 대상 보드: **Xilinx Zynq UltraScale+ MPSoC ZCU102** (XCZU9EG-FFVB1156-2-e)
> 목표: PL(Programmable Logic)에 Rocket Chip(RISC-V) + Gemmini(행렬곱/컨볼루션 가속기) SoC를 구현하고,
> PS(Processing System, ARM)를 메모리/DDR/부팅 서비스 계층으로 사용하여 리눅스 부팅 및 AI 추론 가속을 수행.

---

## ⚠️ 0. 반드시 먼저 읽을 것 — ZCU102 지원 현황

**업스트림 Chipyard는 ZCU102를 공식 지원하지 않습니다.**
공식 지원 보드는 `Nexys Video`, `VCU118`, `ZCU106`, `Arty A7` 입니다. (툴 소스에 `zcu102` 서브프로젝트가 없음)

따라서 다음 세 가지 경로 중 하나를 택해야 합니다.

| 경로 | 방법 | 난이도 | 권장도 |
|---|---|---|---|
| **(A) 커뮤니티 포크 사용** | `github.com/rocketchip-zcu102/chipyard` (branch `zcu102`) | 낮음 | ⭐⭐⭐ (입문 권장) |
| **(B) ZCU106 지원을 ZCU102로 포팅** | Chipyard의 `fpga` + `fpga-shells`의 ZCU106 Config/XDC를 ZCU102 파트/핀맵으로 수정 | 중~높음 | ⭐⭐ (학습 목적) |
| **(C) 자체 Harness/XDC 작성** | `chipyard.fpga.zcu106` 를 복제해 `zcu102` 패키지 신설 | 높음 | ⭐ |

> 이 문서는 **(A) 포크 기반**을 기본 시나리오로 하고, **(B) 포팅에 필요한 실코드**도 함께 제공합니다.
> 향후 업스트림에 ZCU102가 정식 편입되면 (A)/(B)는 단순화될 수 있습니다.

---

## 1. 보드 하드웨어 특성 (왜 Zynq MPSoC인가)

ZCU102는 **PS(하드 ARM) + PL(FPGA 패브릭)** 구조의 이기종 SoC입니다.

### 1.1 주요 리소스

| 항목 | 사양 |
|---|---|
| 디바이스 | XCZU9EG-FFVB1156-2-e |
| PS | ARM Cortex-A53 x4 (최대 1.5GHz) + Cortex-R5F x2 |
| PL 로직 | 시스템 로직셀 ~600K / CLB LUT ~274,080 / FF ~548,160 |
| BRAM | 36Kb 블록 x 912 (~32.1 Mb) |
| DSP48E2 | ~2,520 슬라이스 |
| 메모리 | DDR4 SODIMM 4GB (**PS 연결**) |
| 부팅 | SD 카드, QSPI32, JTAG |
| 확장 | FMC HPC 커넥터, PCIe, SATA, Ethernet, USB, DisplayPort |

### 1.2 ⚠️ 핵심 아키텍처 포인트: DDR은 PS에 연결됨

ZCU102의 DDR4는 **PS(ARM)의 DDR 컨트롤러**에 붙어 있습니다 (VCU118처럼 PL에 독립 MIG가 있는 구조가 아님).
따라서 RISC-V(PL)가 메모리에 접근하려면 **PS의 AXI HP(High Performance) 포트를 통해 DDR에 접근**합니다.

```
[RISC-V SoC (PL)]  ──AXI──▶ [PS AXI HP 포트] ──▶ [PS DDR 컨트롤러] ──▶ [DDR4]
        ▲                                     │
        │                                     └── PS(ARM)이 FSBL/서빙 프로그램 실행
     RoCC│
   [Gemmini]
```

결과적으로 Zynq 계열 표준 흐름은 다음과 같습니다.
1. **PS(ARM)가 FSBL로 부팅** → DDR 초기화, PL 비트스트림 로드
2. PS 위의 **서빙 프로그램(fesvr-zynq 유사)** 이 RISC-V 바이너리/커널 이미지를 DDR에 기록
3. PL의 **RISC-V 코어가 DDR을 실행 메모리로 사용**하여 동작
4. (선택) 리눅스/베어메탈이 PS UART/SD/Ethernet을 통해 IO

> 즉 Gemmini/Rocket SoC는 "메모리를 PS에 위탁"하는 형태로 배치됩니다.

---

## 2. 디렉토리 구조

```
RISC-V_Gemmini_FPGA_Prj/
├── README.md                         # 최상위 프로젝트 개요
└── ZCU102/
    ├── README.md                     # (이 문서) 보드 개요 + 지원현황 + 목차
    ├── Phase0_환경구축.md
    ├── Phase1_RocketCore_시뮬레이션.md
    ├── Phase2_ZCU102_비트스트림_합성.md
    ├── Phase3_리눅스_부팅.md
    ├── Phase4_Gemmini_통합.md
    ├── Phase5_행렬곱_컨볼루션.md
    ├── Phase6_ResNet_LLM.md
    ├── Phase7_프로파일링_최적화.md
    └── code/
        ├── setup_chipyard.sh              # Phase 0: Chipyard 설치 스크립트
        ├── build_zcu102.sh                # Phase 2: 비트스트림 빌드 스크립트
        ├── ZCU102Configs.scala            # Phase 2: Rocket ZCU102 Config
        ├── GemminiZCU102Configs.scala     # Phase 4: Rocket+Gemmini ZCU102 Config
        ├── opensbi_rocc.patch             # Phase 4: OpenSBI RoCC 권한 패치
        └── xdc/
            └── README.md                  # Phase 2: XDC 제약 파일 안내
```

---

## 3. Phase 로드맵 (순차 진행)

| Phase | 제목 | 산출물 | 예상 기간 |
|---|---|---|---|
| [Phase 0](Phase0_환경구축.md) | 환경 구축 | Chipyard+툴체인+Vivado 동작 | 1~3일 |
| [Phase 1](Phase1_RocketCore_시뮬레이션.md) | Rocket Core 시뮬레이션 | Verilator Hello World | 2~4일 |
| [Phase 2](Phase2_ZCU102_비트스트림_합성.md) | ZCU102 비트스트림 합성 | `.bit` + `boot.bin` | 3~7일 |
| [Phase 3](Phase3_리눅스_부팅.md) | 리눅스 부팅 | 인터랙티브 셸 | 1~2주 |
| [Phase 4](Phase4_Gemmini_통합.md) | Gemmini 통합 | Gemmini 동작 확인 | 1~2주 |
| [Phase 5](Phase5_행렬곱_컨볼루션.md) | 행렬곱/컨볼루션 | GEMM/Conv 테스트 통과 | 1주 |
| [Phase 6](Phase6_ResNet_LLM.md) | ResNet/LLM 추론 | ONNX/ResNet 실행 | 2~4주 |
| [Phase 7](Phase7_프로파일링_최적화.md) | 프로파일링/최적화 | PPA 최적 Config | 지속 |

---

## 4. ZCU102에서 기대 가능한 Gemmini 구성

ZU9EG는 ZU7EV(ZCU104)보다 LUT가 약 19% 많고 BRAM도 충분하여 Gemmini 구성 선택 폭이 넓습니다.

| SA 크기 | ZU9EG 적합성 | 비고 |
|---|---|---|
| **8×8** | 매우 여유 | SP 64~256KB, ACC 32~64KB 가능. 최고 PPA |
| **16×16** | 가능 (권장 균형점) | LUT/BRAM 여유. ResNet류에 최적 효율 |
| **32×32** | 어려움 | 면적 ~3.3배 폭증. 타이밍/배선 압박 |

> 기본 목표: **16×16 SA + SP 256KB + ACC 64KB + im2col HW + WS 데이터플로우**.

---

## 5. 참고 자료

- Chipyard FPGA 프로토타이핑 일반: https://chipyard.readthedocs.io/en/stable/Prototyping/General.html
- ZCU102 커뮤니티 포크: https://github.com/rocketchip-zcu102/chipyard
- ZCU102 Rocket 포팅(구버전 참고): https://github.com/li3tuo4/rc-fpga-zcu
- seL4 Rocketchip on ZCU102(DornerWorks): https://docs.sel4.systems/Hardware/rocketchip-zcu102.html
- Gemmini: https://github.com/ucb-bar/gemmini
