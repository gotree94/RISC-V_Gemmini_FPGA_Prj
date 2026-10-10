# Phase 7 — 프로파일링 & 최적화 (Kria KV260)

> 목표: Gemmini 성능 카운터로 병목을 식별하고, 하드웨어/소프트웨어 파라미터를 탐색(DSE)하여
> 성능-면적(PPA) 최적점을 찾는다.

> 공통 내용은 [ZCU102 Phase 7](../ZCU102/Phase7_프로파일링_최적화.md) 참고.
> Kria 특이사항: **BRAM이 144개뿐**이라 SP/ACC/기능의 리소스 여유가 DSE의 핵심 제약이다.

---

## 0. 요약 체크리스트

- [ ] Gemmini 성능 카운터 수집
- [ ] 병목 유형 식별 (연산 vs 메모리 vs CPU 오버헤드)
- [ ] 파라미터 탐색 (SA / SP·ACC / URAM / dataflow / im2col)
- [ ] **리소스(Vivado) 리포트와 함께** PPA 비교
- [ ] 최적 Config 확정

---

## 1. 성능 카운터

Gemmini는 `gemmini_profile_dump()` 등으로 총/Matmul/Conv/Im2col/Pooling/ResAdd/Other 사이클을 제공.

```
Total / Matmul / Conv / Im2col / ResAdd / Pooling / Other
```
- **Conv/Matmul 높음** → 정상 가속
- **Im2col/Other 높음** → CPU 오버헤드/비효율 매핑
- **메모리 대기 증가** → SP/타일링 개선

---

## 2. 병목 분류 (진단 트리)

```
성능 저하
 ├─ 연산(Conv/Matmul) 비중 낮음?
 │    ├─ im2col이 CPU에 있음 → has_im2col=true (리소스 허용 시)
 │    └─ GEMM ≪ SA → 타일/문제 크기 조정
 ├─ 메모리 대기?
 │    ├─ SP/ACC 부족 → 재사용 저하 → 용량↑(URAM)
 │    └─ PS DDR 대역폭 한계(Kria) → 데이터 재사용↑
 ├─ CPU 오버헤드(ResAdd/Other)? → 매핑 이관
 └─ 데이터플로우 부적합? → 소형=WS / 대형=OS
```

---

## 3. 파라미터 탐색(DSE) — Kria 제약 반영

| 파라미터 | Kria 권장 범위 | 트레이드오프 |
|---|---|---|
| `meshRows × meshColumns` | **4×4 → 8×8** (16×16은 초과) | 2배↑ 시 면적 ≈3.3배 |
| `sp_capacity` | 16 / 32 / 64 KB (**URAM 활용**) | 클수록 재사용↑, BRAM/URAM 소모 |
| `acc_capacity` | 8 / 16 KB | 누산 여유 |
| `dataflow` | WS / OS | 소형=WS, 대형=OS |
| `has_im2col` | true/false | 리소스 허용 시 true |
| 메모리 매핑 | BRAM / **URAM** | URAM 활용 시 BRAM 압박 완화 |

### 3.1 권장 탐색 순서
1. **4×4 + SP32/ACC16 + im2col** → 합성 성공 & 리소스 여유 확보 (기준점)
2. 8×8로 확장 → 리소스 리포트로 초과 여부 판정
3. im2col on/off 비교 (대형 Conv 대상)
4. WS vs OS (GEMM 크기별)

---

## 4. PPA(성능-면적) 비교 — 리소스 동반 기록

각 Config에서:
- 성능: 대상 워크로드 사이클 (또는 FPS)
- 면적: Vivado 합성 리포트의 LUT/BRAM/URAM/DSP/FF 사용률
- 전력: Vivado power report (선택)

`PPA = 성능 ÷ 면적(LUT 등)`

> 문헌 경향: 8×8 SA가 최고 PPA, 16×16이 성능 균형점. **Kria는 4×4~8×8 구간이 현실적.**

---

## 5. 리소스 사용량 확인 (Vivado)

```tcl
open_run impl_1
report_utilization -file util.rpt
report_timing_summary -file timing.rpt
report_power -file power.rpt
```

체크 (Kria):
- **BRAM/URAM** 사용률 → 90% 넘으면 위험
- LUT → SA 확대 시 급증 (초과 시 4×4)
- Timing WNS ≥ 0 (met)

---

## 6. 소프트웨어 최적화 팁

- 타일 크기를 SP(URAM)에 맞춰 최대화 (데이터 재사용↑)
- NCHW→NHWC 변환 같은 shuffle 최소화
- operator fusion (Conv+ReLU+MaxPool)
- 배치/시퀀스 길이를 4GB DDR·PS 대역폭에 맞춤
- LLM: KV 캐시를 SP/캐시에 상주

---

## 7. 결과 기록 템플릿

| Config | SA | SP/ACC | mem | im2col | dataflow | Cycles | FPS | LUT% | BRAM% | URAM% | PPA |
|---|---|---|---|---|---|---|---|---|---|---|---|
| baseline | 4 | 32/16 | URAM | Y | WS | | | | | | |
| 8x8 | 8 | 32/16 | URAM | Y | WS | | | | | | |
| noim2col | 8 | 64/16 | URAM | N | WS | | | | | | |

---

## 8. 완료 기준

- [ ] 성능 카운터 수집 및 병목 식별
- [ ] 최소 3개 Config DSE 완료 (리소스 리포트 포함)
- [ ] PPA 비교표 작성
- [ ] 최종 Config 확정 및 문서화

---

## 9. 스피드업 기준의 명확화 (필수)

"수천 배"는 대개 **약한 in-order Rocket + FireSim + 큰 SA** 기준입니다.
보고 시 반드시 명시:
- 기준(baseline): Rocket / BOOM / 서버 CPU / GPU
- 측정 환경: Kria FPGA 실측 / FireSim / 시뮬레이터
- 워크로드: 모델, 배치, 정밀도
- (Kria 한정) **SA 크기와 메모리 경로(PS DDR)** 를 명시

---

## 10. 다음 단계 (확장 아이디어)

- **FireSim** 기반 대규모 성능 평가 (Alveo U250 등)
- 커스텀 연산자 추가 (RoCC)
- BOOM 호스트로 전환 (오버헤드 감소) — 단, Kria 리소스 초과 유의
- 양자화 정밀도(4/8bit)·sparse 탐색
- ASIC(Hammer) 플로우로 tapeout-ready RTL
