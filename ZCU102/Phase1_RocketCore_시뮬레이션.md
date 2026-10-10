# Phase 1 — Rocket Core 시뮬레이션

> 목표: FPGA/가속기 없이, 순수 Rocket Core(RISC-V) SoC를 Verilator로 시뮬레이션하여
> "Hello World"를 실행하고 부팅/IO 흐름을 이해한다.

---

## 0. 요약 체크리스트

- [ ] `RocketConfig` Verilog 생성
- [ ] Verilator 시뮬레이터 빌드
- [ ] 베어메탈 Hello World 실행
- [ ] 콘솔 IO(HTIF) 동작 확인
- [ ] (선택) 파형 확인 / `RocketConfig` 파라미터 이해

---

## 1. 왜 시뮬레이션부터 하는가

- FPGA 합성은 1회 30분~2시간 → **로직 오류를 시뮬레이션에서 먼저 제거**하는 것이 필수.
- Verilator는 사이클 정확 시뮬레이터로, 커스텀 Config/가속기 통합 검증에 표준적으로 사용.
- 여기서 성공한 Config가 Phase 2의 FPGA Config의 기반이 된다.

---

## 2. RocketConfig 확인

시뮬레이션 예제는 Chipyard의 `RocketConfig`(단일 in-order Rocket)를 사용합니다.

```bash
cd $CHIPYARD_DIR
source env.sh
cd sims/verilator
```

`RocketConfig`는 `generators/chipyard/src/main/scala/config/RocketConfigs.scala`에 정의:

```scala
class RocketConfig extends Config(
  new freechips.rocketchip.rocket.WithNHugeCores(1) ++ // 단일 Rocket 코어
  new chipyard.config.AbstractConfig)
```

---

## 3. Verilog 생성

```bash
make verilog CONFIG=RocketConfig
```

성공 시 `generated-src/chipyard.TestHarness.RocketConfig/` 아래에
`ChipTop.sv`, `TestHarness.sv` 등이 생성됩니다.

- `ChipTop` : SoC 본체 (CPU + 버스 + 메모리 인터페이스)
- `TestHarness`: 시뮬레이션용 하네스 (DRAM 모델 + FESVR 연결)

---

## 4. 시뮬레이터 빌드

```bash
make CONFIG=RocketConfig -j$(nproc)
```

산출물: `simulator-chipyard-RocketConfig`
(Verilator C++ 컴파일이므로 수 분 소요)

---

## 5. Hello World 실행

Chipyard의 기본 예제는 `tests/`에 있습니다. 가장 간단한 방법은 다음과 같습니다.

```bash
# 예제 프로그램으로 시뮬레이터 실행 (경로는 Chipyard 버전에 맞게)
./simulator-chipyard-RocketConfig \
  $CHIPYARD_DIR/tests/build/hello.riscv
```

성공 시 터미널에 `Hello, World!` (또는 유사 메시지)가 출력됩니다.

> 시뮬레이터는 FESVR를 통해 `tohost`/`fromhost`로 콘솔 IO를 중계합니다.
> 프로그램 종료 시 `tohost`에 값이 기록되어 시뮬레이터가 종료됩니다.

### 5.1 직접 베어메탈 프로그램 작성 (선택)

Chipyard `tests/` 디렉터리에 C 예제를 추가하고 `make`로 빌드할 수 있습니다.

```bash
cd $CHIPYARD_DIR/tests
# 예: hello.c 추가 후
make
```

컴파일에는 `riscv64-unknown-elf-gcc`(Phase 0에서 설치)가 사용됩니다.

---

## 6. 시뮬레이터 실행 옵션 (자주 쓰는 것)

| 옵션 | 설명 |
|---|---|
| `+verbose` | 상세 로그 |
| `+max-cycles=N` | 최대 사이클 제한 |
| `+dramsim` | DRAM 시뮬레이터 사용(설정 시) |
| `-v out.vcd` (Verilator 옵션) | 파형 덤프 (빌드 시 `VERILATOR=verilator --trace`) |

파형이 필요하면 빌드 시 tracing 활성화 후 실행:

```bash
# 재빌드 시 tracing 플래그 (버전에 따라 상이)
make CONFIG=RocketConfig VERILATOR="verilator" -j$(nproc)
```

---

## 7. 부팅/IO 흐름 이해 (이 단계에서 체득할 것)

```
전원 ON → BootROM(0x10000 부근) → WFI 대기
  → FESVR가 ELF 세그먼트를 DRAM에 기록 (TSI)
  → CLINT MSIP에 소프트웨어 인터럽트 → CPU 깨어남
  → DRAM(0x8000_0000)로 점프 → 프로그램 실행
  → tohost/fromhost로 콘솔 IO 중계
  → 종료
```

- **베어메탈**: 여기서 끝 (프로그램이 `tohost`에 종료 신호 전송)
- **리눅스**: Phase 3에서 BBL/OpenSBI(2차 부트로더)로 확장

---

## 8. 완료 기준

- [ ] `make verilog CONFIG=RocketConfig` 성공
- [ ] 시뮬레이터 빌드 성공
- [ ] Hello World 실행 및 종료 확인

→ 다음: [Phase 2 — ZCU102 비트스트림 합성](Phase2_ZCU102_비트스트림_합성.md)
