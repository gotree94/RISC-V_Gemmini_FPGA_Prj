# Phase 0 — 환경 구축 (Alveo U250 + FireSim)

> 목표: 호스트 서버 + Alveo U250 + XDMA 드라이버 + Vivado 2021.1 + FireSim을 구성하여
> 사전 빌드 비트스트림을 실행할 수 있는 상태까지 만든다.

---

## 0. 요약 체크리스트

- [ ] 호스트 서버 요구사항 충족 (PCIe Gen3 x16, RAM/디스크)
- [ ] Vivado 2021.1 설치 (⚠️ U250/U280은 2021.1 필수)
- [ ] au250 보드 지원 패키지(BSP) 설치
- [ ] XDMA 커널 드라이버 빌드/설치
- [ ] Chipyard + FireSim 클론/설정
- [ ] FireSim 초기 빌드 (`buildsetup`)
- [ ] FPGA 인식 확인 (`lspci`, `xbutil`/`xbmgmt`)

---

## 1. 호스트 서버 요구사항

| 항목 | 최소 | 권장 |
|---|---|---|
| OS | Ubuntu 20.04 | Ubuntu 22.04 LTS |
| PCIe | Gen3 x16 (전용 슬롯) | Gen3/Gen4 x16, BAR 공간 충분 |
| RAM | 64 GB | 128 GB+ (대형 DNN 시뮬) |
| 디스크 | 300 GB | 1 TB+ SSD (Vivado + 빌드 산출물) |
| CPU | 16코어 | 32코어+ (합성/시뮬레이터 빌드) |
| GPU | 불필요 | (선택) 시각화 |

전원: Alveo U250은 **AUX 150W PCIe 전원 케이블**이 반드시 필요합니다.

---

## 2. Vivado 2021.1 설치

⚠️ **Alveo U250/U280 FireSim 빌드는 Vivado 2021.1이 필요**합니다.

```bash
# 설치 후
source /tools/Xilinx/Vivado/2021.1/settings64.sh
vivado -version   # 2021.1 확인
```

> ZCU102(Phase 2)에서 2022.2를 썼다면, Alveo용은 **별도로 2021.1**을 설치해 두는 것이 안전합니다.

---

## 3. au250 보드 지원 패키지(BSP) 설치

open-nic-shell의 보드 파일을 Vivado BoardStore에 배치합니다.

```bash
# au250 BSP 다운로드 (open-nic-shell repo의 board_files/Xilinx/au250)
git clone https://github.com/Xilinx/open-nic-shell.git /tmp/open-nic-shell

# Vivado 2021.1 BoardStore 경로로 복사
VIVADO_BOARDS=/tools/Xilinx/Vivado/2021.1/data/xhub/boards/XilinxBoardStore/boards/Xilinx
mkdir -p "${VIVADO_BOARDS}"
cp -r /tmp/open-nic-shell/board_files/Xilinx/au250 "${VIVADO_BOARDS}/"
```

---

## 4. XDMA 커널 드라이버

FireSim은 XDMA로 FPGA와 통신합니다. 호스트 커널 버전에 맞는 XDMA 드라이버를 빌드합니다.

```bash
# FireSim은 XDMA 커널 모듈 빌드를 안내함 (드라이버 소스 포함)
# 커널 헤더 필요
sudo apt-get install -y linux-headers-$(uname -r) build-essential

# 드라이버 디렉터리로 이동 후 (FireSim 문서의 XDMA-template 참고)
make -j$(nproc)
sudo make install
sudo modprobe xdma
lsmod | grep xdma
```

> 커널 업데이트 시 드라이버를 재빌드해야 합니다.

---

## 5. Chipyard + FireSim 설치

FireSim은 Chipyard를 서브모듈로 사용합니다.

```bash
cd ~
git clone https://github.com/firesim/firesim.git
cd firesim
git submodule update --init --recursive
```

FireSim 초기 설정:

```bash
cd firesim
./build-setup.sh fast            # 권장: fast 모드
# 필요 시 옵션:
#   --skip-validate
#   --library
source sourceme-manager.sh       # 환경 로드
```

이 과정에서 Chipyard, conda 환경, 시뮬레이터(Verilator) 등이 구성됩니다.

> 자동화 스크립트: `code/setup_firesim_u250.sh` (경로/버전 수정 후 사용)

---

## 6. FPGA 인식 확인

```bash
# PCIe 장치 인식
lspci -d 10ee:
#   예: 10ee:5000 ... (Alveo)

# 관리 도구 (xrt/xbmgmt) 설치되어 있다면
sudo xbmgmt examine          # 또는
sudo xbutil examine
```

> XRT(Xilinx Runtime)는 XDMA 설치/점검에 유용합니다. FireSim 문서의 요구 버전을 확인하세요.

---

## 7. 완료 기준

- [ ] `vivado -version` = 2021.1
- [ ] `modprobe xdma` 성공, `lspci`에 Alveo 표시
- [ ] `./build-setup.sh fast` 성공
- [ ] `source sourceme-manager.sh` 정상 동작
- [ ] `firesim --version` (또는 `firesim -h`) 동작

→ 다음: [Phase 1 — FireSim 기본 구동](Phase1_FireSim_기본구동.md)

---

## 8. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| `lspci`에 카드 없음 | BAR/슬롯/전원 | 슬롯 재장착, AUX 전원 확인, BIOS Above4G/ResizableBAR |
| XDMA 빌드 실패 | 커널 헤더 없음 | `linux-headers-$(uname -r)` 설치 |
| Vivado 버전 경고 | 2021.1 아님 | U250/U280은 2021.1 필수 |
| BoardStore 인식 안 됨 | BSP 미배치 | au250 디렉터리 위치 확인 |
| PCIe link down | 잘못된 플래시 | PCIe 셸 복구 스크립트 사용 |
