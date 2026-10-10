# Phase 0 — 개발 환경 구축 (Kria KV260)

> 목표: Chipyard + RISC-V 툴체인 + Vivado + 시뮬레이터 + (Kria용) 부팅 이미지 도구를 설치하고,
> 최소 예제를 빌드할 수 있는 상태까지 만든다.

> 공통 절차는 [ZCU102 Phase 0](../ZCU102/Phase0_환경구축.md)와 거의 동일합니다.
> 이 문서는 **Kria 특이사항** 중심으로 정리합니다.

---

## 0. 요약 체크리스트

- [ ] 호스트 OS 준비 (Ubuntu 22.04 LTS 권장)
- [ ] 필수 패키지 + Conda 설치
- [ ] Chipyard 클론 (업스트림 main → Kria 포팅용)
- [ ] RISC-V 툴체인 빌드 (`riscv-tools`)
- [ ] Conda 환경 + `env.sh`
- [ ] **Vivado 2022.2** 설치 + **Kria/K26 보드파일** 확인
- [ ] Verilator 설치
- [ ] Vitis(또는 `bootgen`/`xsct`) 준비 (Phase 2 부팅 이미지용)
- [ ] 스모크 테스트 (Verilog 생성)

---

## 1. 호스트 환경

| 항목 | 최소 | 권장 |
|---|---|---|
| OS | Ubuntu 20.04 | **Ubuntu 22.04 LTS** |
| CPU/RAM | 8코어 / 32GB | 16코어 이상 / 64GB |
| 디스크 | 150GB | **300GB+ SSD** |

> **WSL2 주의**: 소프트웨어 빌드/시뮬레이션은 WSL2 가능하나,
> **Vivado 합성/JTAG는 Linux 네이티브 또는 Windows Vivado**를 권장.
> Kria는 USB/JTAG 또는 SD카드 부팅이라 USB 패스스루 문제를 피하는 편이 낫다.

### 1.1 필수 패키지

```bash
sudo apt-get update
sudo apt-get install -y \
  autoconf automake autotools-dev curl libmpc-dev libmpfr-dev libgmp-dev \
  gawk build-essential bison flex texinfo gperf libtool patchutils bc \
  zlib1g-dev libexpat-dev git wget python3 python3-pip python3-dev \
  device-tree-compiler libusb-1.0-0-dev default-jre
```

---

## 2. Conda 설치

```bash
cd ~
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda3
eval "$($HOME/miniconda3/bin/conda shell.bash hook)"
conda init
```

---

## 3. Chipyard 클론 (Kria는 업스트림 기반 + 포팅)

Kria/K26은 커뮤니티 포크가 사실상 없으므로 **업스트림 Chipyard를 기반으로 ZCU106을 Kria로 포팅**합니다.

```bash
cd ~
git clone https://github.com/ucb-bar/chipyard.git
cd chipyard
git checkout main
./scripts/init-submodules-no-riscv-tools.sh
export CHIPYARD_DIR=~/chipyard
```

> `code/KriaConfigs.scala`, `code/GemminiKriaConfigs.scala`가 포팅 골격입니다.
> Phase 2에서 `fpga`/`fpga-shells`에 `kria`(또는 `k26`) 서브프로젝트를 신설합니다.

---

## 4. RISC-V 툴체인 빌드

```bash
cd $CHIPYARD_DIR
./scripts/build-toolchains.sh riscv-tools   # 30분~2시간
```

완료 확인: `$RISCV/bin/riscv64-unknown-elf-gcc`, `riscv64-unknown-linux-gnu-gcc`.

---

## 5. Conda 환경 + env.sh

```bash
cd $CHIPYARD_DIR
conda env create -f conda-reqs/conda-reqs.conda-lock.yml   # 또는 chipyard.yaml
conda activate chipyard
source env.sh
```

모든 빌드 전 `source env.sh` 습관화.

---

## 6. Vivado 설치 (Kria 합성용)

| 항목 | 권장 |
|---|---|
| 버전 | **Vivado 2022.2** (Kria/K26 보드파일, `bootgen` 포함) |
| 에디션 | K26은 대형 디바이스 → **WebPACK 불가**, ML Standard/Enterprise 필요 |
| 보드파일 | `xilinx.com:k26:...`(Kria K26 SOM) 또는 `kv260`/`kr260` 캐리어 보드파일 체크 |

```bash
source /tools/Xilinx/Vivado/2022.2/settings64.sh
which vivado bootgen
```

> Kria 보드파일은 Vivado Board Store에서 설치하거나 Vitis Kria 플랫폼(XPFM)에 포함됩니다.
> 보드파트 예: `xck26-sfvc784-2LV-c` (K26 SOM). 캐리어별 파트명은 설치본에서 확인.

---

## 7. Verilator 설치

```bash
conda install -c conda-forge verilator
verilator --version
```

---

## 8. 부팅 이미지 도구 준비 (Phase 2)

Zynq MPSoC 부팅 이미지(`BOOT.BIN`) 생성에 `bootgen`, PS 초기화/서빙에 Vitis(`xsct`)를 사용합니다.

```bash
# Vivado/Vitis에 포함된 bootgen, xsct 확인
which bootgen xsct
```

> Kria의 FSBL/PMUFW는 **Kria BSP** 기준으로 빌드하는 것이 안전합니다(Vitis Kria 플랫폼 사용).

---

## 9. 스모크 테스트

```bash
cd $CHIPYARD_DIR && source env.sh
cd sims/verilator
make verilog CONFIG=RocketConfig     # Chisel→Verilog
make CONFIG=RocketConfig             # 시뮬레이터 빌드
```

---

## 10. 자동화 스크립트

`code/setup_chipyard.sh`에 위 과정을 묶었습니다(경로/버전 수정 후 사용).

```bash
bash code/setup_chipyard.sh upstream
```

---

## 11. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| Kria 보드파일 없음 | 보드 미설치 | Vivado Board Store / Vitis Kria 플랫폼 설치 |
| `sbt` OOM | JVM 힙 부족 | `export SBT_OPTS="-Xmx8G"` |
| 툴체인 not found | env.sh 미source | `source env.sh` |
| Verilator 버전 불일치 | conda 버전 | `conda-reqs` 기준 버전 확인 |
| bootgen 없음 | Vitis 미설치 | Vivado/Vitis 설치 시 포함 확인 |

---

## 12. 완료 기준 (DoD)

- [ ] `riscv64-unknown-elf-gcc --version` 정상
- [ ] `vivado -version` + Kria/K26 보드 선택 가능
- [ ] `bootgen -help` 동작
- [ ] `make verilog CONFIG=RocketConfig` 성공

→ 다음: [Phase 1 — Rocket Core 시뮬레이션](Phase1_RocketCore_시뮬레이션.md)
