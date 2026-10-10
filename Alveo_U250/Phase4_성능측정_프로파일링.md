# Phase 4 — 성능측정 & 프로파일링

> 목표: FireSim(사이클 정확)로 Gemmini의 성능을 정확히 측정하고,
> TracerV/성능 카운터/설계공간 탐색(DSE)으로 병목을 분석·최적화한다.

---

## 0. 요약 체크리스트

- [ ] 성능 카운터 수집 (Conv/Matmul/Im2col 분해)
- [ ] TracerV로 타임라인 트레이스 수집
- [ ] 기준(baseline) 명확화 (Rocket vs CPU vs GPU)
- [ ] DSE(SA/SP·ACC/dataflow/im2col) 실험
- [ ] PPA 비교표 작성 및 최적 Config 확정

---

## 1. FireSim이 주는 정확성

- FireSim은 **사이클 정확** → 시뮬레이터 사이클 수가 실제와 일치.
- FASED DDR 모델 → 메모리 타이밍까지 반영.
- **논문의 스피드업 수치는 이 환경 기준** → 재현성 높음.

### ⚠️ 성능 환산 주의
- 워크로드 JSON의 `clock_rate_hz`(예: 3.2GHz)로 FPS/스피드업을 환산.
- **FPGA 실주파수(예: 100MHz)**와는 다름. 보고 시 어떤 클럭 기준인지 명시.

---

## 2. 성능 카운터

Gemmini 프로파일 출력(예: ResNet-50):

```text
Total cycles:  1358733049 (100%)
Matmul cycles:  508263409 (37%)
Im2col cycles:          0 (0%)
Conv cycles:    818013564 (60%)
Pooling cycles:         0 (0%)
Res add cycles:  32258198 (2%)
Other cycles:      197878 (0%)
PASS
```

해석:
- **Conv/Matmul 비중↑** → 가속 정상
- **Im2col이 CPU(0 아닌 큰 값)** → `has_im2col=true` 검토
- **ResAdd/Other↑** → 매핑 비효율

---

## 3. TracerV (타임라인 트레이스)

FireSim는 TracerV로 이벤트를 트레이스해 **시간 축 병목**을 볼 수 있습니다.

```yaml
# config_runtime.yaml
workload:
    workload_name: resnet50-linux.json
    tracer:
        enable: true
        # tracer 노드/트리거 설정
```

트레이스 뷰어(GUI)로 로드하면:
- 가속기 사용 구간 vs CPU(비매핑) 구간 vs 메모리 대기 구간 식별
- im2col/레이아웃 변환 오버헤드 위치 파악

---

## 4. 기준(baseline) 명확화

공정한 비교를 위해 반드시 명시:

| baseline | 의미 | 비고 |
|---|---|---|
| in-order Rocket | 논문의 주 기준 | 스피드업 수치가 큼 |
| BOOM (OoO) | 더 강한 호스트 | 스피드업 상대적으로 작음 |
| 캐시 최적화 CPU | 초기논문 기준 (ResNet50 ~70×) | "진짜" CPU 대비 |
| GPU/서버 CPU | 실무 기준 | FPGA 단독 대비 열세 가능 |

> "수천 배"는 **약한 in-order Rocket 기준**임을 항상 병기.

---

## 5. 설계공간 탐색(DSE)

| 파라미터 | 옵션 | 트레이드오프 |
|---|---|---|
| `meshRows×meshColumns` | 8/16/32 | 2배↑ → 면적 ≈3.3×, 전력 ≈2.7× |
| `sp_capacity` | 64/128/256KB | 재사용↑, BRAM 소모 |
| `acc_capacity` | 32/64KB | 누산 여유 |
| `dataflow` | WS/OS | 소형=WS, 대형=OS |
| `has_im2col` | T/F | 대형 GEMM 이득(~1.1×) |
| `fpga_frequency` | 100~ | 높을수록 빠르나 타이밍 위험 |

### 권장 순서
1. 16×16 + 256/64 + im2col + WS (baseline)
2. 8×8 vs 16×16 vs 32×32 (PPA)
3. im2col on/off (대형 Conv)
4. WS vs OS (GEMM 크기별)

각 실험 = **새 레시피 + 비트스트림 빌드**(수 시간). 사전 계획 필요.

---

## 6. 리소스/전력 확인

```bash
# results-build/<...>/ 아래 Vivado 리포트
# util.rpt, timing.rpt, power.rpt
```

체크:
- LUT/DSP/URAM 사용률 (U250 여유 확인)
- Timing WNS ≥ 0
- 전력 ≤ 215W 예산

---

## 7. 결과 기록 템플릿

| Config | SA | SP/ACC | im2col | dataflow | freq | Cycles | LUT% | DSP% | WNS | 비고 |
|---|---|---|---|---|---|---|---|---|---|---|
| baseline | 16 | 256/64 | Y | WS | 100 | | | | | |
| small | 8 | 64/32 | N | WS | | | | | | |
| wide | 32 | 256/64 | Y | OS | | | | | | |

---

## 8. 완료 기준

- [ ] 성능 카운터 + TracerV 수집
- [ ] baseline 명확화 및 스피드업 산출
- [ ] 최소 3개 Config DSE
- [ ] PPA 표 + 최적 Config 확정

---

## 9. 확장 아이디어

- 커스텀 연산자 추가(RoCC로 새 가속기)
- BOOM 호스트로 전환해 CPU 병목 감소
- 4/8bit·sparse Gemmini 탐색
- AWS F1 / 대규모 FireSim 클러스터로 멀티노드 평가
- Hammer(ASIC) 플로우로 tapeout-ready RTL 생성

---

## 10. 참고

- FireSim 문서: https://docs.fires.im/
- Gemmini 프로파일/카운터: https://github.com/ucb-bar/gemmini
- Gemmini 원논문(DAC'21) — FireSim 기반 스피드업 수치의 출처
