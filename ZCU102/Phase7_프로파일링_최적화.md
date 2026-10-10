# Phase 7 — 프로파일링 & 최적화

> 목표: Gemmini 성능 카운터로 병목을 식별하고, 하드웨어/소프트웨어 파라미터를 탐색(DSE)하여
> 성능-면적(PPA) 최적점을 찾는다.

---

## 0. 요약 체크리스트

- [ ] Gemmini 성능 카운터 활성화/수집
- [ ] 병목 유형 식별 (연산 vs 메모리 vs CPU 오버헤드)
- [ ] 파라미터 탐색(SA 크기/SP·ACC/데이터플로우/im2col)
- [ ] PPA 비교표 작성
- [ ] 최적 Config 확정

---

## 1. 성능 카운터 활성화

Gemmini는 사이클 단위 프로파일 카운터를 제공합니다. 빌드 시 프로파일 모드 활성화:

```bash
# 테스트 빌드 시 프로파일 매크로 활성화 (버전에 따라 상이)
# 예: -DPROFILE 또는 gemmini 프로파일 헤더 설정
```

카운터 예:
- `gemmini_profile_dump()` — 총 사이클, Matmul/Conv/Im2col/Pooling/ResAdd/Other 분해

수집 후 분석:
```
Total / Matmul / Conv / Im2col / ResAdd / Pooling / Other
```
- **연산 집약(Conv/Matmul 높음)** → 정상 가속
- **Im2col/Other 높음** → CPU 오버헤드/비효율 매핑
- **메모리 대기 증가** → 스크래치패드/타일링 개선

---

## 2. 병목 분류 (진단 트리)

```
성능 저하
 ├─ 연산(Conv/Matmul) 비중 낮음?
 │    ├─ im2col이 CPU에 있음 → has_im2col=true
 │    └─ GEMM 크기 ≪ SA → 타일링/문제 크기 조정
 ├─ 메모리 대기?
 │    ├─ SP/ACC 용량 부족 → 재사용 저하 → 용량↑
 │    └─ DDR 대역폭(PS 경유) 한계 → 데이터 재사용↑, 타일↑
 ├─ CPU 오버헤드(ResAdd/Other)?
 │    └─ 매핑 가능 연산을 가속기로 이관
 └─ 데이터플로우 부적합?
      └─ 작은 GEMM=WS / 큰 GEMM=OS
```

---

## 3. 파라미터 탐색(DSE)

각 축을 변화시키며 성능과 리소스를 측정합니다.

| 파라미터 | 옵션 | 트레이드오프 |
|---|---|---|
| `meshRows × meshColumns` | 8×8 / 16×16 / 32×32 | 2배↑ 시 면적 ≈3.3배, 전력 ≈2.7배 |
| `sp_capacity` | 64 / 128 / 256 KB | 클수록 데이터 재사용↑, BRAM 소모 |
| `acc_capacity` | 32 / 64 KB | 누산 여유 |
| `dataflow` | WS / OS | 소형=WS, 대형=OS |
| `has_im2col` | true/false | 대형 GEMM엔 이득(~1.1×), 면적 소폭↑ |
| 호스트 CPU | Rocket / BOOM | im2col CPU 처리 시 BOOM 유리 |

### 3.1 권장 탐색 순서
1. 16×16 + SP256/ACC64 + im2col=true + WS → 기준점(baseline)
2. SA 8×8 vs 16×16 비교 (PPA)
3. im2col on/off 비교 (대형 Conv 대상)
4. 데이터플로우 WS vs OS (GEMM 크기별)

---

## 4. PPA(성능-면적) 비교

각 Config에서:
- 성능: 대상 워크로드 실행 사이클 (또는 FPS)
- 면적: Vivado 합성 리포트의 LUT/BRAM/DSP/FF 사용률
- 전력: Vivado power report (선택)

`PPA = 성능 ÷ 면적(LUT 등)`

> 문헌 경향: **8×8 SA가 최고 PPA**, 16×16이 성능/효율 균형점.
> ZU9EG처럼 여유 있는 FPGA에서는 16×16이 실용적 최적점인 경우가 많음.

---

## 5. 리소스 사용량 확인 (Vivado)

합성 후 리포트:
```bash
# Vivado에서 열기
open_run impl_1
report_utilization -file util.rpt
report_timing_summary -file timing.rpt
report_power -file power.rpt
```

또는 `fpga/generated-src/<LONG_NAME>/obj/`의 리포트 파일 확인.

체크:
- BRAM 사용률 (Gemmini SP/ACC가 지배) → 90% 넘으면 위험
- LUT 사용률 → SA 확대 시 급증
- Timing WNS ≥ 0 (met)

---

## 6. 소프트웨어 최적화 팁

- **타일 크기**를 SP에 맞춰 최대화 (데이터 재사용↑)
- NCHW→NHWC 변환 같은 **shuffle 연산 최소화**
- **operator fusion** (Conv+ReLU+MaxPool 등) 활용
- 배치 크기/시퀀스 길이를 DRAM 용량·대역폭에 맞춤
- LLM: KV 캐시를 SP/캐시에 상주시켜 재사용

---

## 7. 결과 기록 템플릿

| Config | SA | SP/ACC | im2col | dataflow | Cycles | FPS | LUT% | BRAM% | DSP% | PPA |
|---|---|---|---|---|---|---|---|---|---|---|
| baseline | 16 | 256/64 | Y | WS | | | | | | |
| small | 8 | 64/32 | N | WS | | | | | | |
| wide | 32 | 256/64 | Y | OS | | | | | | |

---

## 8. 완료 기준

- [ ] 성능 카운터 수집 및 병목 식별
- [ ] 최소 3개 Config DSE 완료
- [ ] PPA 비교표 작성
- [ ] 최종 Config 확정 및 문서화

---

## 9. 참고: 스피드업 기준의 명확화

"수천 배"는 대개 **약한 in-order Rocket CPU + FireSim 측정** 기준입니다.
보고 시 반드시 명시:
- 기준(baseline)이 무엇인가 (Rocket / BOOM / 서버 CPU / GPU)
- 측정 환경 (FPGA 실측 / FireSim / 시뮬레이터)
- 워크로드 (모델, 배치, 정밀도)

이를 명확히 해야 성능 수치가 공정하게 해석됩니다.

---

## 10. 다음 단계 (확장 아이디어)

- **FireSim** 기반 대규모 성능 평가 파이프라인 구축
- 커스텀 연산자 추가 (RoCC로 새 가속기 부착)
- BOOM 호스트로 전환하여 오버헤드 감소
- 양자화 정밀도(4/8bit) 및 sparse 지원 탐색
- ASIC(Hammer) 플로우로 tapeout-ready RTL 생성
