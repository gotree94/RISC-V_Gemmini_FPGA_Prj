# Alveo U250 기반 RISC-V + Gemmini 프로젝트 (FireSim)

> 대상 보드: **AMD/Xilinx Alveo U250** (XCU250-2LFIGD2104E, Virtex UltraScale+, 4 SLR)
> 목표: FireSim을 사용하여 Rocket + Gemmini SoC(ASIC RTL)를 **사이클 정확**하게 FPGA에서 가속 시뮬레이션하고,
> ResNet/LLM 등 DNN 워크로드의 성능을 정확히 측정한다.

---

## ⚠️ 0. ZCU102와의 근본적 차이 (먼저 읽을 것)

Alveo U250은 **독립 개발 보드가 아니라 PCIe 데이터센터 가속 카드**입니다.

| 항목 | ZCU102 | **Alveo U250** |
|---|---|---|
| 형태 | 독립 보드 (PS+PL) | **PCIe 카드 (호스트 PC 종속)** |
| 하드 CPU(PS) | 있음 (ARM A53) | **없음** |
| 단독 부팅 | 가능 (SD/QSPI) | **불가** (호스트가 구동) |
| 호스트 연결 | JTAG/UART/SD | **PCIe Gen3 x16 (XDMA)** |
| 주 용도 | **FPGA 프로토타이핑** (RISC-V 실물 동작) | **FireSim FPGA 가속 시뮬레이션** |
| 리눅스 부팅 | PL의 RISC-V가 직접 부팅 | 시뮬레이션 내부에서 부팅(호스트가 구동) |
| 성능 수치 | 실측(FPGA 실주파수) | **사이클 정확 모델(논문 수치의 기준)** |

> **결론**: Alveo U250에서는 "FPGA에 RISC-V를 직접 굽는다"가 아니라,
> **FireSim으로 RTL을 FPGA에서 빠르게 돌려 성능/정확성을 측정**합니다.
> Gemmini 원논문의 "수천 배 스피드업" 수치가 바로 이 FireSim 환경에서 나온 것입니다.

---

## 1. 보드 하드웨어 스펙 (DS962 / UG1289)

| 항목 | 사양 |
|---|---|
| FPGA | XCU250-2LFIGD2104E (Virtex UltraScale+, **4 SLR**) |
| LUT | **1,728K** |
| Registers(FF) | 3,456K |
| DSP48E2 | **12,288** |
| UltraRAM | 1,280 |
| DDR4 | **64 GB** (4×16GB RDIMM, 2400 MT/s, ECC) |
| DDR 대역폭 | **77 GB/s** |
| PCIe | Gen3 x16 |
| 네트워크 | 2× QSFP28 |
| 전력 | 215W (AUX 150W 필요) |
| 폼팩터 | Full-height, full-length, dual-width |
| HBM2 | 없음 (HBM은 U280/U55C 등 상위 기종) |

### 1.1 ZCU102와 리소스 비교

| 리소스 | ZCU102 (ZU9EG) | Alveo U250 (XCU250) | 배수 |
|---|---|---|---|
| LUT | ~274K | 1,728K | ~6.3× |
| BRAM | 912 (36Kb) | (SLR별 분산, 대용량) | - |
| DSP | ~2,520 | 12,288 | ~4.9× |
| DDR | 4 GB | 64 GB | 16× |
| DDR 대역폭 | PS 경유(낮음) | **77 GB/s** | - |

> Alveo U250은 **대형 Gemmini(16×16/32×32) + 대형 DNN/LLM**을 넉넉히 수용합니다.

---

## 2. 아키텍처: FireSim 방식

```
┌─────────────────────────── 호스트 서버 (x86) ───────────────────────────┐
│  FireSim 드라이버 (C++)  ── XDMA ──▶ [Alveo U250]                        │
│  · MMIO (AXI4-Lite, 32b)  : 시뮬레이션 제어                             │
│  · DMA  (AXI4, 512b)      : 대량 데이터 이동                            │
│  · DRAM (AXI4)            : FASED DDR 메모리 모델 (64GB DDR4 실물 사용)  │
└─────────────────────────────────────────────────────────────────────────┘
                    │
        FPGA 내부: [F1Shim / Firesim top] + Golden Gate 변환된 SoC 모델
                    │
        Rocket + Gemmini(ASIC RTL) → 사이클 정확 실행 + 성능 카운터
```

- **Golden Gate**: ASIC RTL을 FPGA에서 사이클 정확하게 에뮬레이션하도록 변환.
- **FASED**: DDR 메모리 타이밍 모델링.
- **MIDAS/F1Shim**: FPGA 상단 셸(shim)로 XDMA 연결.

---

## 3. FireSim 지원 현황

- FireSim은 **Alveo U250, U280을 XDMA 기반으로 공식 지원**합니다.
- **Vivado 2021.1 필수** (다른 버전은 out-of-the-box 동작 보장 안 됨).
- 보드 지원 패키지(BSP): `au250` 을 open-nic-shell에서 받아 Vivado BoardStore에 배치.
- 플랫폼 이름: `xilinx_alveo_u250`
- Deploy Manager: `XilinxAlveoU250InstanceDeployManager`
- 기본 레시피: `alveo_u250_firesim_rocket_singlecore_no_nic`
- Bit builder recipe: `bit-builder-recipes/xilinx_alveo_u250.yaml`

> ⚠️ Alveo U250은 PCIe가 **항상 살아 있어야** 하므로, 전체 FPGA를 다시 굽는 방식이라도
> PCIe 셸 복구 스크립트가 필요합니다(플랫폼 스크립트에 포함).

---

## 4. 디렉토리 구조

```
RISC-V_Gemmini_FPGA_Prj/
├── README.md
├── ZCU102/                         # FPGA 프로토타이핑 (독립 보드)
└── Alveo_U250/                     # FireSim FPGA 가속 시뮬레이션 (PCIe 카드)
    ├── README.md                   # (이 문서)
    ├── Phase0_환경구축.md
    ├── Phase1_FireSim_기본구동.md
    ├── Phase2_커스텀비트스트림_Rocket_Gemmini.md
    ├── Phase3_가속기_워크로드_구동.md
    ├── Phase4_성능측정_프로파일링.md
    └── code/
        ├── setup_firesim_u250.sh
        ├── config_build_recipes.yaml
        ├── config_build.yaml
        ├── config_hwdb.yaml
        └── config_runtime.yaml
```

---

## 5. Phase 로드맵

| Phase | 제목 | 산출물 | 예상 기간 |
|---|---|---|---|
| [Phase 0](Phase0_환경구축.md) | 환경 구축 | 호스트+XDMA+FireSim 동작 | 2~5일 |
| [Phase 1](Phase1_FireSim_기본구동.md) | FireSim 기본 구동 | 사전빌드 비트스트림으로 시뮬 실행 | 1~3일 |
| [Phase 2](Phase2_커스텀비트스트림_Rocket_Gemmini.md) | 커스텀 비트스트림 | Rocket+Gemmini `.bit` | 3~7일 |
| [Phase 3](Phase3_가속기_워크로드_구동.md) | 가속기 워크로드 | ResNet/LLM 시뮬 | 1~2주 |
| [Phase 4](Phase4_성능측정_프로파일링.md) | 성능측정/프로파일링 | 스피드업/병목 분석 | 지속 |

---

## 6. ZCU102 vs Alveo U250 — 어떤 걸 언제 쓰나

| 목적 | 권장 |
|---|---|
| "순수 FPGA 위 RISC-V에서 리눅스가 실제로 돈다"를 증명 | **ZCU102** (실물 부팅) |
| 논문 수준의 **정확한 DNN 성능 수치** 측정 | **Alveo U250 + FireSim** |
| 대형 Gemmini(16×16 이상) + LLM 워크로드 | **Alveo U250** |
| 저비용 학습/입문 | ZCU102(또는 Nexys Video) |
| 반복 실험 자동화(CI처럼) | **Alveo U250** (호스트 스크립트로 구동) |

> 두 플랫폼은 **경쟁 관계가 아니라 상호 보완**적입니다.
> ZCU102로 "동작함"을 확인하고, Alveo U250 + FireSim로 "얼마나 빠른가"를 정확히 측정하는 조합이 이상적입니다.

---

## 7. 선행 요구사항 체크리스트

- [ ] PCIe Gen3 x16 슬롯이 있는 호스트 서버 (충분한 RAM/디스크)
- [ ] Alveo U250 카드 + AUX 전원 케이블
- [ ] Vivado 2021.1 (Alveo 빌드용)
- [ ] 호스트 Linux (Ubuntu 20.04/22.04 계열)
- [ ] Chipyard + FireSim 저장소
- [ ] (선택) 100G NIC 워크로드 시 QSFP28

---

## 8. 참고 자료

- FireSim 문서: https://docs.fires.im/
- Alveo U250 시작 가이드(FireSim): https://docs.fires.im/en/latest/Getting-Started-Guides/On-Premises-FPGA-Getting-Started/Xilinx-Alveo-U250-FPGAs.html
- FireSim 새 FPGA 추가 가이드(Alveo U250 예제): https://docs.fires.im/en/latest/Advanced-Usage/Adding-FPGAs.html
- Alveo U200/U250 데이터시트(DS962): https://docs.amd.com/r/en-US/ds962-u200-u250
- Alveo U200/U250 재구성 가이드(UG1289): https://docs.amd.com/r/en-US/ug1289-u200-u250-reconfig-accel
- open-nic-shell 보드 파일(au250 BSP): https://github.com/Xilinx/open-nic-shell
- Gemmini: https://github.com/ucb-bar/gemmini
