# Phase 5 — 행렬곱 / 컨볼루션 실행 (Kria KV260)

> 목표: Gemmini API를 사용하여 GEMM(행렬곱)과 컨볼루션을 실행하고,
> 시뮬레이터와 FPGA 양쪽에서 결과가 일치함을 검증한다.

> 공통 절차는 [ZCU102 Phase 5](../ZCU102/Phase5_행렬곱_컨볼루션.md)와 동일합니다.
> Kria 특이사항: **HW SA 크기가 작으므로(4×4/8×8) `DIM`과 타일링 정합**이 더 중요.

---

## 0. 요약 체크리스트

- [ ] `gemmini.h` API 이해 (`tiled_matmul_auto` 등)
- [ ] `gemmini-rocc-tests` 빌드 (**`DIM`을 Kria SA 크기와 일치**)
- [ ] Spike(기능)에서 테스트 통과
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
- `tiled_matmul_auto(M, N, K, A, B, C, ...)` — 타일링/DMA/스케줄 자동
- `tiled_conv_auto(...)` — 컨볼루션 (im2col HW 유무에 따라 경로 상이)
- `gemmini_fence()` — 가속기 완료 대기

---

## 2. 테스트 스위트 빌드 (DIM 주의)

```bash
cd $CHIPYARD_DIR && source env.sh
cd generators/gemmini/software/gemmini-rocc-tests
./build.sh
```

> ⚠️ **`libgemmini`의 `DIM`은 Kria HW의 SA(예: 4 또는 8)와 반드시 일치**해야 합니다.
> HW가 4×4면 `DIM=4`, 8×8이면 `DIM=8`로 빌드합니다.
> (ZCU102의 16×16용 바이너리를 그대로 쓰면 오동작/성능 저하)

산출물: `build/` 아래 `matmul_*`, `conv_*`, `mlps/`, `imagenet/` 등.

---

## 3. 시뮬레이터 실행 (기능 검증)

```bash
# 기능 (Spike)
spike --extension=gemmini pk build/matmul_8x8

# 사이클 정확 (Verilator, 소형만)
cd $CHIPYARD_DIR/sims/verilator
make CONFIG=GemminiKriaConfig -j$(nproc)
./simulator-chipyard-GemminiKriaConfig <test.riscv>
```

> Verilator는 대형 워크로드에 매우 느림 → 소형 위주. 대형은 FPGA/FireSim.

---

## 4. FPGA에서 실행

### 4.1 베어메탈
`GemminiKriaConfig` 비트스트림으로 PL 구성 후, 베어메탈 ELF를 DDR에 적재 실행.

### 4.2 리눅스 사용자 공간
Phase 3 이미지에 테스트 바이너리를 포함(initramfs)하거나 SD 카드로 복사.

```bash
# 리눅스 부팅 후
./matmul_8x8
```

> ⚠️ 리눅스 실행은 Phase 4의 RoCC 권한 설정이 선행돼야 함(SIGILL 방지).

---

## 5. 결과 확인 및 프로파일

```text
Total cycles: ...
Matmul cycles: ... (NN%)
Conv cycles:   ... (NN%)
Im2col cycles: ... (NN%)
PASS
```

읽는 법:
- **Conv/Matmul 비중**이 높으면 가속이 잘 됨.
- **Im2col이 CPU에서(큰 값)** → im2col HW 도입 검토.
- Kria는 SA가 작아 **큰 GEMM에서 효율이 ZCU102(16×16)보다 낮음**을 유의.

---

## 6. 컨볼루션 최적화 포인트

- 컨볼루션은 **GEMM(im2col) 변환** 시 시스톨릭 어레이에서 가장 효율적.
- GEMM 타일이 **SA 차원과 같을 때** 최고 효율 (Kria 4×4/8×8 기준).
- 작은 GEMM엔 WS, 큰 GEMM엔 OS.
- im2col HW는 **대형 GEMM에서만** 이득; Kria는 리소스가 빠듯해 off도 고려.
- 2×2 미만 GEMM엔 가속기 비권장.

---

## 7. 완료 기준

- [ ] `gemmini-rocc-tests` 빌드 (DIM 일치)
- [ ] Spike 기능 통과
- [ ] FPGA에서 동일 테스트 PASS
- [ ] 프로파일 카운터 출력 확인

→ 다음: [Phase 6 — ResNet/LLM 추론](Phase6_ResNet_LLM.md)

---

## 8. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| `DIM` 불일치 | libgemmini DIM ≠ Kria SA | DIM(4/8) 맞춰 재빌드 |
| SIGILL | RoCC 권한 | Phase 4 재확인 |
| 결과 오류 | DMA/타일 설정 | `tiled_matmul_auto` 파라미터, 주소 정렬 |
| 극도로 느림 | Verilator 대형 워크로드 | Spike(기능)/FPGA(성능) |
| Conv 느림 | im2col CPU 처리 | `has_im2col=true`, GEMM 크기 정렬 |
