# Kria KV260 XDC 제약 파일 안내 (Phase 2)

이 디렉터리에 Kria(K26 SOM + 캐리어) 보드용 XDC(핀 제약) 파일을 배치합니다.

## 1. 왜 필요한가
Chisel이 생성한 Verilog의 최상위 IO(클럭, 리셋, UART, LED 등)를
Kria SOM/캐리어의 실제 FPGA 핀에 매핑하고, 클럭/타이밍 제약을 정의합니다.

> ⚠️ Kria는 **SOM + 캐리어 카드** 구조라 핀맵이 **Vivado 보드파일(XPFM/board file)** 에
> 대부분 정의돼 있습니다. 따라서 **보드파일 제약을 우선 사용**하고,
> PL UART/LED 등 추가 IO만 작성하는 것을 권장합니다.

## 2. 참고 기준 문서
- **Kria KV260 / K26 SOM 문서**(DS987, UG1085 TRM, KV260 하드웨어 아키텍처)
- Vivado 보드파일 / Vitis Kria 플랫폼(XPFM)
- 캐리어 카드(KV260/KR260) 핀아웃/커넥터 문서

## 3. 필수 제약 항목 (템플릿)
```tcl
# ---- PL 클럭 (캐리어/PS가 공급하는 PL clock 포트 사용) ----
create_clock -period 10.000 -name pl_clk0 [get_ports pl_clk0]   # 100 MHz 예시
# KV260 플랫폼은 통상 100/200/300(400)MHz PL 클럭 제공 → 보드파일 제약 우선

# ---- 리셋 ----
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS18} [get_ports sys_rst]

# ---- UART (PS UART 미노출 캐리어면 PL UART를 노출) ----
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS18} [get_ports uart_tx]
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS18} [get_ports uart_rx]

# ---- LED (디버그) ----
# set_property -dict {PACKAGE_PIN <PIN> IOSTANDARD LVCMOS18} [get_ports {led[*]}]
```

> ⚠️ **PACKAGE_PIN 번호와 IOSTANDARD(1.8V 등)는 반드시 Kria 문서 / 보드파일에서 확인**하세요.
> 잘못된 전압 지정은 보드/FPGA를 손상시킬 수 있습니다.

## 4. 보드 파트 (예시)
```
part  : xck26-sfvc784-2LV-c         # K26 SOM (정확한 값은 설치본에서 확인)
board : xilinx.com:k26:<ver>        # 또는 KV260/KR260 캐리어 보드파일
```

## 5. 배치 위치 (포팅 시)
Chipyard `fpga-shells` 구조에 맞춰 보드별 리소스 디렉터리에 두고,
Vivado TCL(`env.tcl` 등)의 board/part switch에 `kria`(또는 `k26`) 케이스를 추가합니다.
