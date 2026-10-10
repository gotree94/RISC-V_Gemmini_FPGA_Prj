# ZCU102 XDC 제약 파일 안내 (Phase 2)

이 디렉터리에 ZCU102 보드용 XDC(핀 제약) 파일을 배치합니다.

## 1. 왜 필요한가
Chisel이 생성한 Verilog의 최상위 IO(클럭, 리셋, UART, LED 등)를
ZCU102의 실제 FPGA 핀에 매핑하고, 클럭/타이밍 제약을 정의합니다.

## 2. 참고 기준 문서
- **ZCU102 Board User Guide (UG1182)** — 핀/전압/커넥터
- Vivado 보드파일 마스터 XDC
  (`<Vivado>/data/boards/board_files/xilinx.com_zcu102_part0_<ver>/...`)
- 커뮤니티 포크 / Chipyard ZCU106 `fpga-shells`의 XDC

## 3. 필수 제약 항목 (템플릿)
```tcl
# ---- 클럭 ----
## 예: PL 클럭 입력 핀 (ZCU102 실제 핀명으로 교체)
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS18} [get_ports sys_clk]
create_clock -period 10.000 -name sys_clk [get_ports sys_clk]   # 100 MHz

# ---- 리셋 ----
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS18} [get_ports sys_rst]

# ---- UART (PS MIO 사용 시 PL XDC 불필요) ----
## PL UART를 노출하는 경우에만:
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS18} [get_ports uart_tx]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS18} [get_ports uart_rx]

# ---- LED (디버그) ----
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS18} [get_ports {led[*]}]
```

> ⚠️ **PACKAGE_PIN 번호와 IOSTANDARD(1.8V 등)는 반드시 UG1182 / 마스터 XDC에서 확인**하세요.
> 잘못된 전압 지정은 보드/FPGA를 손상시킬 수 있습니다.

## 4. 보드 파트
```
part     : xczu9eg-ffvb1156-2-e
board    : xilinx.com:zcu102:part0:3.4   # Vivado 버전에 따라 다름
```

## 5. 배치 위치 (포팅 시)
Chipyard `fpga-shells` 구조에 맞춰 보드별 리소스 디렉터리에 두고,
Vivado TCL(`env.tcl` 등)의 board/part switch에 `zcu102` 케이스를 추가합니다.
