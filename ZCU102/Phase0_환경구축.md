# Phase 0 — 개발 환경 구축

> 목표: Chipyard + RISC-V 툴체인 + Vivado + 시뮬레이터 + 소프트웨어 스택 빌드 도구를 설치하고,
> 최소 예제를 빌드할 수 있는 상태까지 만든다.

---

## 0. 요약 체크리스트

- [ ] 호스트 OS 준비 (Ubuntu 22.04 LTS 권장)
- [ ] 필수 패키지 설치 (build-essential, git, python3, ...)
- [ ] Conda(Mini/Anaconda) 설치
- [ ] Chipyard 클론 + 서브모듈 초기화
- [ ] RISC-V 툴체인 빌드 (`riscv-tools`)
- [ ] Conda 환경 생성 + `env.sh` source
- [ ] Vivado 설치 (2022.2 권장, ZCU102 보드파일 포함)
- [ ] Verilator 설치
- [ ] FireMarshal 준비 (Phase 3용)
- [ ] 스모크 테스트 (Chipyard 예제 Verilog 생성)

---

## 1. 호스트 환경

### 1.1 OS / 하드웨어 요구사항

| 항목 | 최소 | 권장 |
|---|---|---|
| OS | Ubuntu 20.04 | **Ubuntu 22.04 LTS** |
| CPU/RAM | 8코어 / 32GB | 16코어 이상 / 64GB |
| 디스크 | 150GB | **300GB+ SSD** (툴체인+Vivado+빌드 산출물) |

> **WSL2 주의**: 소프트웨어 빌드/시뮬레이션은 WSL2에서 가능하나,
> **Vivado 합성은 Linux 네이티브 또는 Windows 쪽 Vivado** 사용을 권장합니다.
> (USB JTAG, 케이블 드라이버, 성능 문제) 듀얼 운영이 가장 실용적입니다.

### 1.2 필수 패키지 설치

```bash
sudo apt-get update
sudo apt-get install -y \
  autoconf automake autotools-dev curl libmpc-dev libmpfr-dev libgmp-dev \
  gawk build-essential bison flex texinfo gperf libtool patchutils bc \
  zlib1g-dev libexpat-dev git wget python3 python3-pip python3-dev \
  device-tree-compiler libusb-1.0-0-dev default-jre
```

`default-jre`는 Scala/sbt 실행에 필요합니다.

---

## 2. Conda 설치

Chipyard는 conda 환경(`conda-reqs`)으로 툴 버전을 고정합니다.

```bash
cd ~
wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
bash Miniconda3-latest-Linux-x86_64.sh -b -p $HOME/miniconda3
eval "$($HOME/miniconda3/bin/conda shell.bash hook)"
conda init
```

> Shell 재시작 후 `conda`가 잡히는지 확인: `conda --version`

---

## 3. Chipyard 획득 (ZCU102 경로 선택)

### 경로 (A) 커뮤니티 ZCU102 포크 — **권장(입문)**

```bash
cd ~
git clone https://github.com/rocketchip-zcu102/chipyard.git
cd chipyard
git checkout zcu102
git submodule update --init --recursive   # (포크 README의 지시 우선)
```

### 경로 (B) 업스트림 Chipyard + ZCU106 기반 ZCU102 포팅

```bash
cd ~
git clone https://github.com/ucb-bar/chipyard.git
cd chipyard
git checkout main

# 서브모듈 초기화 (툴체인 제외)
./scripts/init-submodules-no-riscv-tools.sh
```

> (B)를 택하면 Phase 2에서 `fpga-shells`의 ZCU106 Config/XDC를 ZCU102로 복제·수정합니다.
> 이 저장소의 `code/ZCU102Configs.scala`, `code/GemminiZCU102Configs.scala`를 사용합니다.

### 공통

```bash
export CHIPYARD_DIR=~/chipyard
cd $CHIPYARD_DIR
```

---

## 4. RISC-V 툴체인 빌드

소프트웨어(베어메탈/리눅스) 크로스컴파일용입니다. **빌드에 30분~2시간** 소요됩니다.

```bash
cd $CHIPYARD_DIR
./scripts/build-toolchains.sh riscv-tools   # elf-gcc + linux-gcc 포함
```

> `build-toolchains.sh` 인자에 따라 elf/linux 툴체인이 결정됩니다.
> 최소 elf만 필요하면 `./scripts/build-toolchains.sh --skip-gcc` 등 옵션을 확인하세요.
> 완료 후 `$RISCV/bin/riscv64-unknown-elf-gcc`, `riscv64-unknown-linux-gnu-gcc` 존재 확인.

산출물 경로: `$CHIPYARD_DIR/../riscv-tools` (또는 `$RISCV`)

---

## 5. Conda 환경 + env.sh

```bash
cd $CHIPYARD_DIR
# conda 환경 파일은 Chipyard 버전에 따라 위치가 다를 수 있음
conda env create -f conda-reqs/conda-reqs.conda-lock.yml    # 새 버전
# 또는: conda env create -f conda-reqs/chipyard.yaml        # 구버전

conda activate chipyard
source env.sh
```

`env.sh`가 `$RISCV`, `$PATH`, `LD_LIBRARY_PATH` 등을 설정합니다.
**모든 빌드 명령 전에 `source env.sh`를 습관화**하세요.

> `.bashrc`에 넣지 말고 세션마다 명시적으로 source하는 것을 권장(환경 오염 방지).

---

## 6. Vivado 설치 (ZCU102 합성용)

| 항목 | 권장 |
|---|---|
| 버전 | **Vivado 2022.2** (ZCU102 보드파일/`xsct` 포함, SDK 대체) |
| 에디션 | 합성 대상이 ZU9EG이므로 **무료 WebPACK 불가** (Vivado ML Standard/Enterprise 필요) |
| 보드파일 | 설치 시 `Zynq UltraScale+ MPSoC ZCU102` 체크 |

설치 후 환경:

```bash
source /tools/Xilinx/Vivado/2022.2/settings64.sh   # 경로는 설치 위치에 맞게
which vivado
```

> ZCU102 보드파일 미포함 시: Vivado → Board Store 에서 `xilinx.com:zcu102:part0` 추가.
> 합성 시 사용 보드파트: `xilinx.com:zcu102:part0:3.4` (버전은 설치본에 따라 다름), 파트: `xczu9eg-ffvb1156-2-e`.

---

## 7. Verilator 설치 (RTL 시뮬레이션)

```bash
# Chipyard conda 환경에 포함되거나, 별도 설치
conda install -c conda-forge verilator    # 권장
verilator --version
```

Chipyard는 `sims/verilator`에서 사용합니다.

---

## 8. FireMarshal 준비 (Phase 3에서 사용)

Chipyard에 서브모듈로 포함됩니다.

```bash
cd $CHIPYARD_DIR/software/firemarshal
./init-submodules.sh
```

---

## 9. 스모크 테스트

환경이 제대로 구성됐는지 최소 검증합니다.

```bash
cd $CHIPYARD_DIR
source env.sh

# 1) Chisel → Verilog 생성 (시뮬레이션용)
cd sims/verilator
make verilog CONFIG=RocketConfig
# 성공 시 generated-src/ 아래 ChipTop.sv 등 생성

# 2) 시뮬레이터 빌드 (시간 소요)
make CONFIG=RocketConfig
```

빌드가 끝나면 `simulator-chipyard-RocketConfig` 실행 파일이 생성됩니다. (실행은 Phase 1)

---

## 10. 자동화 스크립트

`code/setup_chipyard.sh`에 위 과정을 묶어 두었습니다. 경로/버전을 환경에 맞게 수정 후 사용하세요.

```bash
bash code/setup_chipyard.sh
```

---

## 11. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| `sbt` OOM | JVM 힙 부족 | `export SBT_OPTS="-Xmx8G"` (Chipyard 기본값 확인) |
| `riscv64-unknown-elf-gcc: not found` | env.sh 미source | `source env.sh` |
| conda create 실패 | lockfile/버전 불일치 | Chipyard 버전에 맞는 `conda-reqs/*` 사용 |
| Verilator 빌드 실패 | 버전 불일치 | Chipyard가 요구하는 Verilator 버전 확인(`conda-reqs`) |
| Vivado 보드 없음 | 보드파일 미설치 | Board Store에서 zcu102 추가 |
| `git submodule` 실패 | 네트워크/프록시 | 프록시 설정, 재시도 |

---

## 12. 완료 기준 (Definition of Done)

- [ ] `riscv64-unknown-elf-gcc --version` 정상
- [ ] `vivado -version` 정상 + ZCU102 보드 선택 가능
- [ ] `make verilog CONFIG=RocketConfig` 성공
- [ ] `make CONFIG=RocketConfig`로 시뮬레이터 빌드 성공

→ 다음: [Phase 1 — Rocket Core 시뮬레이션](Phase1_RocketCore_시뮬레이션.md)
