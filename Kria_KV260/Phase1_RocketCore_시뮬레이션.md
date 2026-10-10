# Phase 1 — Rocket Core 시뮬레이션 (Kria KV260)

> 목표: FPGA/가속기 없이, 순수 Rocket Core(RISC-V) SoC를 Verilator로 시뮬레이션하여
> "Hello World"를 실행하고 부팅/IO 흐름을 이해한다.

> 시뮬레이션은 **보드와 무관**하므로 절차는 [ZCU102 Phase 1](../ZCU102/Phase1_RocketCore_시뮬레이션.md)와 동일합니다.
> Kria에서 달라지는 것은 Phase 2의 FPGA Config뿐입니다.

---

## 0. 요약 체크리스트

- [ ] `RocketConfig` Verilog 생성
- [ ] Verilator 시뮬레이터 빌드
- [ ] 베어메탈 Hello World 실행
- [ ] 콘솔 IO(HTIF) 동작 확인
- [ ] 부팅/IO 흐름 이해

---

## 1. 왜 시뮬레이션부터 하는가

- FPGA 합성은 1회 30분~2시간 → **로직 오류를 시뮬레이션에서 먼저 제거**.
- Verilator는 사이클 정확 시뮬레이터로, 커스텀 Config/가속기 통합 검증의 표준.
- 여기서 통과한 Config가 Phase 2 Kria FPGA Config의 기반이 된다.

---

## 2. Verilog 생성 및 시뮬레이터 빌드

```bash
cd $CHIPYARD_DIR
source env.sh
cd sims/verilator

make verilog CONFIG=RocketConfig            # Chisel → Verilog
make CONFIG=RocketConfig -j$(nproc)         # Verilator 빌드
```

산출물: `simulator-chipyard-RocketConfig`

- `ChipTop` : SoC 본체 (CPU + 버스 + 메모리 인터페이스)
- `TestHarness`: 시뮬레이션 하네스 (DRAM 모델 + FESVR)

---

## 3. Hello World 실행

```bash
./simulator-chipyard-RocketConfig \
  $CHIPYARD_DIR/tests/build/hello.riscv
```

성공 시 `Hello, World!` 출력 후 종료됩니다.

> 시뮬레이터는 FESVR의 `tohost`/`fromhost`로 콘솔 IO를 중계하고,
> 종료 신호(`tohost`)로 시뮬레이션이 끝납니다.

---

## 4. 부팅/IO 흐름 (이 단계에서 체득)

```
전원 ON → BootROM → WFI 대기
  → FESVR가 ELF를 DRAM에 기록 (TSI)
  → CLINT MSIP 소프트웨어 인터럽트 → CPU 깨어남
  → DRAM(0x8000_0000) 점프 → 프로그램 실행
  → tohost/fromhost 콘솔 IO → 종료
```

- **베어메탈**: 여기서 끝.
- **리눅스**: Phase 3에서 OpenSBI(2차 부트로더)로 확장.

---

## 5. 자주 쓰는 실행 옵션

| 옵션 | 설명 |
|---|---|
| `+verbose` | 상세 로그 |
| `+max-cycles=N` | 최대 사이클 제한 |
| `+dramsim` | DRAM 시뮬레이터 사용(설정 시) |

---

## 6. 완료 기준

- [ ] `make verilog CONFIG=RocketConfig` 성공
- [ ] 시뮬레이터 빌드 성공
- [ ] Hello World 실행 및 종료 확인

→ 다음: [Phase 2 — Kria 비트스트림 합성](Phase2_Kria_비트스트림_합성.md)
