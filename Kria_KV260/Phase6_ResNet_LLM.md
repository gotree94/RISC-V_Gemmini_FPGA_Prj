# Phase 6 — ResNet / LLM 추론 (Kria KV260)

> 목표: Gemmini 가속기로 실제 DNN 워크로드(ResNet-50 등 이미지 분류, BERT/소형 LLM)를 실행하고
> 성능을 측정한다.

> 공통 내용은 [ZCU102 Phase 6](../ZCU102/Phase6_ResNet_LLM.md) 참고.
> Kria 특이사항: **SA가 작고(4×4/8×8) DDR 대역폭이 PS 경유**라 성능 상한이 낮다.

---

## 0. 요약 체크리스트

- [ ] `gemmini-rocc-tests/imagenet` ResNet-50 실행 (DIM 일치)
- [ ] ONNX Runtime Gemmini 백엔드로 모델 추론
- [ ] int8 양자화 파이프라인 이해
- [ ] LLM(소형 트랜스포머) 추론 시도
- [ ] 대형 워크로드는 FireSim으로 성능 측정

---

## 1. 실행 경로 2가지

| 경로 | 대상 | 특징 |
|---|---|---|
| **(A) gemmini-rocc-tests** | ResNet50, MobileNet | Gemmini 제공 예제 |
| **(B) ONNX Runtime backend** | 임의 ONNX 모델 | `onnxruntime-riscv`, 배포 모델 |

---

## 2. (A) ResNet-50 / MobileNet 실행

```bash
ls $CHIPYARD_DIR/generators/gemmini/software/gemmini-rocc-tests/build/imagenet/
# 리눅스 부팅 후
./resnet50-linux
```

예상 출력(참고):
```text
Total cycles: ...
Conv cycles:   ... (60%)
Matmul cycles: ... (37%)
PASS
```

> ⚠️ Kria는 SA가 작아 ResNet-50 같은 대형 Conv-on-GEMM에서 **ZCU102(16×16)보다 사이클이 크게** 나옵니다.
> 정확한 성능 수치는 FireSim/FPGA 실측으로 기록하세요.

---

## 3. (B) ONNX Runtime Gemmini 백엔드

```bash
./ort_test -m resnet50_opt_quant.onnx \
           -i images/xxx.jpg \
           -p <provider> -x <설정>
```

### 3.1 양자화 주의
- Gemmini int8 구성 → **int8 양자화 모델 필수**.
- NCHW↔NHWC 변환 비용 발생 가능 → 프로파일에 `Transpose`/`QuantizeLinear` 비중 확인.

---

## 4. LLM (BERT / 소형 트랜스포머)

Gemmini 원논문 기준 **BERT ≈ 144× (vs in-order Rocket)**. LLM은 큰 GEMM 위주라 Gemmini에 유리하나,
**Kria는 (a) SA가 작고 (b) DDR이 PS 경유**라 메모리 대역폭이 상한을 결정합니다.

전략:
1. 소형 트랜스포머의 **행렬곱 레이어**를 `tiled_matmul_auto`로 매핑
2. softmax/layernorm은 CPU(비매핑) → 병목 모니터링
3. KV 캐시/대역폭 병목 주의 (PS 경유 DDR은 순수 PL MIG 대비 느림)

> ⚠️ Kria 4GB DDR4도 PS AXI 경유이므로, LLM처럼 메모리 집약적 워크로드는
> **대역폭이 성능 상한**을 결정할 수 있습니다. 필요 시 Alveo U250(FireSim)로 측정.

---

## 5. 대형 워크로드 = FireSim

Verilator로 ResNet50/LLM은 수일 소요. **FireSim**(FPGA 가속 사이클 정확 시뮬레이션)을 쓰면
수 분~수십 분대로 단축되고 정확한 성능 측정이 가능합니다.

```bash
# 개념 (FireSim 설치/클러스터 필요)
firesim buildbitstream
firesim runworkload
```

> FireSim은 별도 흐름(VCU118/Alveo 기반)이며, [`Alveo_U250/`](../Alveo_U250/README.md) 문서 참고.

---

## 6. 기대 성능 감각 (참고)

| 모델 | 원논문 스피드업 (vs in-order Rocket, FireSim) |
|---|---|
| ResNet50 | 약 2,670× |
| AlexNet | 79.3 FPS |
| SqueezeNet v1.1 | 약 1,760× |
| BERT | 약 144× |
| MobileNetV2 | 약 127× (depthwise conv 비효율) |

> 위 수치는 **큰 SA(16×16+) + PL MIG 환경** 기준입니다. **Kria 소형 SA + PS DDR에서는 더 낮습니다.**
> 보고 시 baseline/측정환경/워크로드를 반드시 명시.

---

## 7. 완료 기준

- [ ] ResNet-50 FPGA 실행 PASS
- [ ] ONNX 모델 추론 성공 (top-k 확인)
- [ ] (선택) 소형 LLM 레이어 가속
- [ ] 성능 수치 기록 (FPS, cycles)

→ 다음: [Phase 7 — 프로파일링/최적화](Phase7_프로파일링_최적화.md)

---

## 8. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| 정확도 낮음 | 양자화/전처리 | 캘리브레이션, 입력 정규화 |
| 메모리 부족 | 모델+데이터 > 4GB | 배치 축소, 타일 조정 |
| Transpose 병목 | 레이아웃 변환 | NHWC 정렬, fused op |
| 느린 추론 | 소형 SA + PS DDR 대역폭 | 타일 재사용↑, FireSim 측정 |
| Verilator 중단 | 사이클 과다 | FireSim/FPGA 사용 |
