# Phase 5 — 행렬곱 / 컨볼루션 실행

> 목표: Gemmini API를 사용하여 GEMM(행렬곱)과 컨볼루션을 실행하고,
> 시뮬레이터와 FPGA 양쪽에서 결과가 일치함을 검증한다.

---

## 0. 요약 체크리스트

- [ ] `gemmini.h` API 이해 (`tiled_matmul_auto` 등)
- [ ] `gemmini-rocc-tests` 빌드
- [ ] 시뮬레이터(Spike/Verilator)에서 테스트 통과
- [ ] FPGA에서 동일 테스트 통과
- [ ] 프로파일 카운터로 사이클 확인

---

## 1. Gemmini 소프트웨어 스택

```
응용/테스트  ──▶ gemmini.h (C API) ──▶ RoCC 커스텀 명령어 ──▶ Gemmini HW
                     │
              (에뮬레이터: Spike --extension=gemmini)
```

핵심 API:
- `tiled_matmul_auto(M, N, K, A, B, C, ...)` — 타일링/DMA/스케줄 자동 처리
- `tiled_conv_auto(...)` — 컨볼루션 (im2col HW 유무에 따라 경로 상이)
- `gemmini_fence()` — 가속기 완료 대기

---

## 2. 테스트 스위트 빌드

```bash
cd $CHIPYARD_DIR
source env.sh
cd generators/gemmini/software/gemmini-rocc-tests

# 라이브러리 함수 (baremetal/linux) + 테스트 프로그램 빌드
./build.sh
```

`build/` 아래에 다수 테스트 바이너리 생성:
- `matmul_*` (GEMM)
- `conv_*` (컨볼루션)
- `tiled_*` (타일링 변형)
- `mlps/`, `imagenet/` (대형 워크로드)

> ⚠️ `libgemmini`의 `DIM` 값은 하드웨어 SA 크기와 일치해야 합니다.
> 16×16 HW면 `DIM=16`으로 빌드된 libgemmini를 사용합니다.

---

## 3. 시뮬레이터 실행 (기능 검증)

가장 빠른 검증은 Spike(기능 시뮬레이터)입니다. 성능은 안 나오지만 정확성 확인에 최적.

```bash
# 작은 행렬곱 테스트 (기능)
spike --extension=gemmini pk build/matmul_16x16

# 대형 DNN도 기능만 확인 가능
spike --extension=gemmini pk build/imagenet/resnet50-pk
```

Verilator(사이클 정확)로 성능까지 보려면:

```bash
cd $CHIPYARD_DIR/sims/verilator
make CONFIG=GemminiZCU102Config -j$(nproc)
./simulator-chipyard-GemminiZCU102Config <test.riscv>
```

> Verilator는 대형 워크로드에 매우 느리므로 소형 테스트 위주로 사용. 대형은 Phase 6의 FireSim/FPGA.

---

## 4. FPGA에서 실행

### 4.1 베어메탈 테스트

`GemminiZCU102Config` 비트스트림으로 PL 구성 후, 베어메탈 테스트 ELF를 DDR에 적재하여 실행.

```bash
# riscv 테스트를 크로스컴파일 (elf)
riscv64-unknown-elf-gcc ... -o test.riscv
# → PS 서빙 SW / JTAG로 DDR 적재 후 실행
```

### 4.2 리눅스 사용자 공간 테스트

Phase 3의 리눅스 이미지에 테스트 바이너리를 포함(initramfs)하거나 SD 카드로 복사.

```bash
# 리눅스 부팅 후
# (SD 마운트 방식이면)
# ./matmul_16x16
```

> ⚠️ 리눅스에서 실행하려면 Phase 4의 RoCC 권한 설정이 반드시 선행돼야 합니다(SIGILL 방지).

---

## 5. 결과 확인 및 프로파일

Gemmini 테스트는 종료 시 프로파일을 출력합니다(예: ResNet-50 실행 로그).

```text
Total cycles: 1358733049 (100%)
Matmul cycles:  508263409 (37%)
Im2col cycles:          0 (0%)
Conv cycles:    818013564 (60%)
Pooling cycles:         0 (0%)
Res add cycles:  32258198 (2%)
Other cycles:      197878 (0%)
PASS
```

읽는 법:
- **Conv/Matmul 비중**이 높으면 가속이 잘 되고 있는 것.
- **Im2col이 CPU에서(0이 아닌 큰 값)** 수행되면 im2col HW 도입 검토.
- **Other/Res add**가 크면 매핑 비효율 → 후속 최적화 포인트.

---

## 6. 컨볼루션 최적화 포인트 (중요)

- 컨볼루션은 **GEMM으로 변환(im2col)** 했을 때 시스톨릭 어레이에서 가장 효율적.
- GEMM 크기가 **SA 차원과 같을 때** 최고 효율 (16×16 SA ↔ 16×16 tile).
- 작은 GEMM엔 **WS**, 큰 GEMM엔 **OS** 데이터플로우가 유리.
- im2col HW는 **대형 GEMM에서만** 이득(≈1.1×); 소형에선 리소스 낭비.
- 2×2 미만 GEMM엔 가속기 사용 비권장.

---

## 7. 완료 기준

- [ ] `gemmini-rocc-tests` 빌드 성공
- [ ] Spike에서 기능 통과 (정확성)
- [ ] FPGA에서 동일 테스트 PASS
- [ ] 프로파일 카운터 출력 확인

→ 다음: [Phase 6 — ResNet/LLM 추론](Phase6_ResNet_LLM.md)

---

## 8. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| `DIM` 불일치 | libgemmini DIM ≠ HW SA | DIM 맞춰 재빌드 |
| SIGILL | RoCC 권한 | Phase 4 재확인 |
| 결과 오류 | DMA/타일 설정 | `tiled_matmul_auto` 파라미터, 주소 정렬 |
| 극도로 느림 | Verilator로 대형 워크로드 | Spike(기능)/FPGA(성능) 사용 |
| Conv 느림 | im2col CPU 처리 | `has_im2col=true`, GEMM 크기 정렬 |
