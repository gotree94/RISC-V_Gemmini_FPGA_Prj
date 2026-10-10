# Kria KV260 기반 RISC-V + Gemmini 프로젝트

> 대상 보드: **AMD/Xilinx Kria KV260 Vision AI Starter Kit** (SOM: K26, XCK26, Zynq UltraScale+ MPSoC)
> 목표: PL(Programmable Logic)에 Rocket Chip(RISC-V) + Gemmini(행렬곱/컨볼루션 가속기) SoC를 구현하고,
> PS(Processing System, ARM Cortex-A53)를 메모리/DDR/부팅 서비스 계층으로 사용하여 리눅스 부팅 및 AI 추론 가속 수행.
> 작성일: 2026-10-10

---

## ⚠️ 0. 반드시 먼저 읽을 것 — Kria 지원 현황과 리소스 경고

**(1) 업스트림 Chipyard는 Kria/K26을 공식 지원하지 않습니다.**
공식 지원 보드는 `Nexys Video`, `VCU118`, `ZCU106`, `Arty A7` 입니다.
→ **ZCU106(Zynq UltraScale+) 지원을 Kria로 포팅**하는 방식으로 진행합니다.

**(2) Kria K26은 ZCU102/ZCU104보다 PL 리소스가 작습니다.** → Gemmini는 "소형"이 현실적입니다.

| 항목 | Kria K26 | ZCU102 (ZU9EG) | 비교 |
|---|---|---|---|
| CLB LUT | **117,120** | 274,080 | Kria ≈ 43% |
| BRAM(36Kb) | **144** | 912 | Kria ≈ 16% ⚠️ |
| URAM(288Kb) | **64** | 0 | Kria 우위 (SP/ACC에 활용) |
| DSP | 1,248 | 2,520 | Kria ≈ 50% |
| PS | A53×4 + R5F×2 | A53×4 + R5F×2 | 동일 |
| DDR | 4GB DDR4 (non-ECC) | 4GB DDR4 | 유사 |

> **BRAM이 144개뿐**이라는 점이 결정적 병목이다. 8×8 Gemmini는 ZU7EV(230K LUT)에서도 ~90K LUT를 쓰므로
> Kria에서는 **8×8도 빠듯**하다. → **URAM을 SP/ACC에 쓰고, SP 용량을 줄이는 전략**이 필수.
>
> 리소스가 부족하면 **[ZCU102](../ZCU102/README.md)** 또는 ZCU104로 이전을 권장한다.

---

## 1. 보드 하드웨어 특성 (왜 Zynq MPSoC인가)

Kria SOM은 **PS(하드 ARM) + PL(FPGA 패브릭)** 구조의 이기종 SoC입니다.

### 1.1 주요 리소스 (K26)

| 항목 | 사양 |
|---|---|
| 디바이스 | XCK26 (Zynq UltraScale+ MPSoC, D784 패키지) |
| PS | ARM Cortex-A53 ×4 (최대 1.5GHz) + Cortex-R5F ×2 |
| PL 로직 | 시스템 로직셀 256K / CLB LUT 117,120 / FF 234,240 |
| BRAM | 36Kb 블록 × 144 (약 5.2 Mb) |
| URAM | 288Kb 블록 × 64 (약 18 Mb) ← **SP/ACC 대안** |
| DSP48E2 | 1,248 |
| 메모리 | DDR4 4GB (64-bit, non-ECC) + 16GB eMMC |
| 부팅 | QSPI32, SD 카드 |
| 확장 | Pmod, Raspberry Pi 커넥터(MIPI), USB3, DisplayPort, 1GbE(캐리어 카드별) |

> **캐리어 카드**: KV260(비전 AI용) / KR260(로보틱스용, 이더넷·Pmod 많음).
> PL 로직은 동일(K26 SOM)하므로 이 문서는 둘 다에 적용된다.

### 1.2 ⚠️ 핵심 아키텍처 포인트: DDR은 PS에 연결됨

ZCU102와 동일하게, **Kria의 DDR4는 PS(ARM)의 DDR 컨트롤러**에 붙어 있습니다.
따라서 RISC-V(PL)가 메모리에 접근하려면 **PS의 AXI HP(High Performance) 포트를 경유**합니다.

```
[FPGA 패브릭(PL)]  ──AXI──▶ [PS AXI HP 포트] ──▶ [PS DDR 컨트롤러] ──▶ [DDR4]
    RISC-V SoC                      ▲
        │ RoCC                      └── PS(ARM)이 FSBL/서빙 프로그램 실행
    [Gemmini]
```

표준 Zynq 흐름:
1. **PS(ARM)가 FSBL 부팅** → DDR 초기화, PL 비트스트림 로드
2. PS 위 **서빙 프로그램(fesvr-zynq 유사)** 이 RISC-V 바이너리/커널 이미지를 DDR에 기록
3. PL의 **RISC-V 코어가 DDR을 실행 메모리로 사용**
4. (선택) PS UART/USD/Ethernet으로 IO

---

## 2. 디렉토리 구조

```
RISC-V_Gemmini_FPGA_Prj/
├── README.md
├── 보드_선정_가이드.md
└── Kria_KV260/
    ├── README.md                     # (이 문서) 보드 개요 + 지원현황 + 리소스 예산 + 목차
    ├── Phase0_환경구축.md
    ├── Phase1_RocketCore_시뮬레이션.md
    ├── Phase2_Kria_비트스트림_합성.md
    ├── Phase3_리눅스_부팅.md
    ├── Phase4_Gemmini_통합.md
    ├── Phase5_행렬곱_컨볼루션.md
    ├── Phase6_ResNet_LLM.md
    ├── Phase7_프로파일링_최적화.md
    └── code/
        ├── setup_chipyard.sh
        ├── build_kria.sh
        ├── KriaConfigs.scala
        ├── GemminiKriaConfigs.scala
        ├── opensbi_rocc.patch
        └── xdc/
            └── README.md
```

---

## 3. Phase 로드맵 (순차 진행)

| Phase | 제목 | 산출물 | 예상 기간 |
|---|---|---|---|
| [Phase 0](Phase0_환경구축.md) | 환경 구축 | Chipyard+툴체인+Vivado 2022.2 동작 | 1~3일 |
| [Phase 1](Phase1_RocketCore_시뮬레이션.md) | Rocket Core 시뮬레이션 | Verilator Hello World | 2~4일 |
| [Phase 2](Phase2_Kria_비트스트림_합성.md) | Kria 비트스트림 합성 | `.bit` + `BOOT.BIN` | 3~10일 |
| [Phase 3](Phase3_리눅스_부팅.md) | 리눅스 부팅 | 인터랙티브 셸 | 1~2주 |
| [Phase 4](Phase4_Gemmini_통합.md) | Gemmini 통합 | Gemmini 동작 확인 | 1~2주 |
| [Phase 5](Phase5_행렬곱_컨볼루션.md) | 행렬곱/컨볼루션 | GEMM/Conv 테스트 통과 | 1주 |
| [Phase 6](Phase6_ResNet_LLM.md) | ResNet/LLM 추론 | ONNX/ResNet 실행 | 2~4주 |
| [Phase 7](Phase7_프로파일링_최적화.md) | 프로파일링/최적화 | PPA 최적 Config | 지속 |

> ZCU102 대비 차이점: (a) SUB_PROJECT가 없어 포팅량 多, (b) BRAM 부족 → URAM 활용 설계.

---

## 4. Kria에서 기대 가능한 Gemmini 구성 (리소스 예산)

K26의 BRAM(144)이 작아 **URAM 활용 + SP 축소**가 핵심입니다.

| SA 크기 | K26 적합성 | 권장 SP/ACC | 비고 |
|---|---|---|---|
| **4×4** | 여유 | SP 16~32KB(URAM) / ACC 8~16KB | **가장 안전한 시작점** |
| **8×8** | 빠듯(도전) | SP 32KB(URAM) / ACC 16KB | Rocket 포함 시 LUT 초과 위험 |
| **16×16** | 거의 불가 | — | LUT/배선 압박, 이전 권장 |

권장 시작 Config:
- **1차 목표**: `4×4 SA + SP 32KB + ACC 16KB + WS + im2col` (반드시 성공시킨다)
- **2차 목표**: 8×8로 SA 확대 시도 → 리소스 초과 시 SP/기능 축소
- **기능 Off 권장**: `has_training_convs=false`, `has_max_pool=false`(필요 시 최소화)
- **SP/ACC를 URAM에 매핑**하면 BRAM 압박을 덜 수 있다(Gemmini 옵션/수정 필요).

---

## 5. ZCU102 문서와의 관계

Kria는 Zynq UltraScale+ 계열이므로 **ZCU102 문서의 절차 대부분을 재사용**합니다.
각 Phase 문서는 공통 부분을 `[→ ZCU102 PhaseN]`으로 참조하고, **Kria 특이사항만** 상세히 다룹니다.

| 주제 | Kria 특이점 |
|---|---|
| PS 부팅 | FSBL/PMUFW/BL31은 **Kria BSP(Vitis) 기준**으로 생성 |
| PS↔PL AXI | HP 포트 폭(128bit), 주소맵 동일 계열 |
| 클럭 | 캐리어 카드의 PL 클럭 소스 사용 (KV260: 100/200/300MHz 제공) |
| 리소스 | BRAM 부족 → URAM 활용, SA/SP 축소 |
| Vivado | **2022.2 권장**, Kria 보드파일/`xilinx.com:k26:*` 설치 |

---

## 6. 참고 자료

- Chipyard FPGA 프로토타이핑 일반: https://chipyard.readthedocs.io/en/stable/Prototyping/General.html
- Kria KV260 문서(하드웨어 아키텍처/리소스): https://xilinx.github.io/kria-apps-docs/kv260/2022.1/build/html/docs/
- Kria SOM 제품 브리프: https://www.xilinx.com/publications/product-briefs/xilinx-kv260-product-brief.pdf
- Kria K26 SOM Data Sheet(DS987) / Zynq MPSoC TRM(UG1085)
- Gemmini: https://github.com/ucb-bar/gemmini
- (대조) ZCU102/106 포팅: ../ZCU102/README.md
