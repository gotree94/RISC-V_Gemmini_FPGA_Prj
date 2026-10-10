# Phase 6 — ResNet / LLM 추론

> 목표: Gemmini 가속기로 실제 DNN 워크로드(ResNet-50 등 이미지 분류, BERT/소형 LLM)를 실행하고
> 성능을 측정한다.

---

## 0. 요약 체크리스트

- [ ] `gemmini-rocc-tests/imagenet` ResNet-50 실행
- [ ] ONNX Runtime Gemmini 백엔드로 모델 추론
- [ ] int8 양자화 파이프라인 이해
- [ ] LLM(BERT/소형 트랜스포머) 추론 시도
- [ ] 대형 워크로드는 FireSim으로 성능 측정

---

## 1. 실행 경로 2가지

| 경로 | 대상 | 특징 |
|---|---|---|
| **(A) gemmini-rocc-tests** | ResNet50, MobileNet 등 | Gemmini 제공 예제, 하드코딩된 네트워크 |
| **(B) ONNX Runtime backend** | 임의 ONNX 모델 | `onnxruntime-riscv`, 실제 배포 모델 |

---

## 2. (A) ResNet-50 / MobileNet 실행

### 2.1 빌드 (이미 Phase 5에서 빌드됨)
```bash
ls $CHIPYARD_DIR/generators/gemmini/software/gemmini-rocc-tests/build/imagenet/
# resnet50, resnet50-pk, mobilenet, ...
```

### 2.2 FPGA(리눅스)에서 실행
```bash
# 리눅스 부팅 후 (SD 또는 initramfs)
./resnet50-linux
```

예상 출력(참고):
```text
Prediction: 75 (score: 45)
...
Total cycles: 1358733049 (100%)
Conv cycles: 818013564 (60%)
Matmul cycles: 508263409 (37%)
PASS
```

> 예제 네트워크는 대부분 **int8 양자화** 전제입니다. HW가 int8에 맞춰졌는지 확인.

### 2.3 데이터 전송 준비
- 리눅스에서 실행하려면 바이너리/이미지 파일이 필요 → **SD 카드** 또는 initramfs 포함.
- UART-TSI는 부팅 후 콘솔로 전환되므로 파일 전송에 부적합(Phase 3 참고).

---

## 3. (B) ONNX Runtime Gemmini 백엔드

Gemmini용 ONNX Runtime 포트(`onnxruntime-riscv`)로 임의 모델을 추론합니다.

### 3.1 흐름
1. FP32 ONNX 모델 준비
2. **post-training quantization** → int8 ONNX 모델
3. `ort_test` 로 리눅스에서 추론

```bash
./ort_test -m resnet50_opt_quant.onnx \
           -i images/xxx.jpg \
           -p <provider> -x <설정>
```

예상 출력(참고):
```text
Element count 1000. Top 5 classes:
0.031456 giant schnauzer
...
0.361813 Rottweiler
Done! Inference took 495827001 cycles
```

### 3.2 양자화 주의점
- Gemmini int8 구성 → 반드시 int8 양자화 모델 필요.
- 출력 레이아웃(NCHW/NHWC) 변환 비용이 발생할 수 있음 → 프로파일에서 `Transpose`/`QuantizeLinear` 비중 확인.

---

## 4. LLM (BERT / 소형 트랜스포머)

Gemmini 원논문 기준 **BERT는 in-order Rocket 대비 약 144×** 개선.
LLM은 대부분 **큰 GEMM(행렬곱)** 으로 구성되어 Gemmini에 유리합니다.

전략:
1. 소형 GPT/트랜스포머의 **행렬곱 레이어**를 `tiled_matmul_auto`로 매핑
2. 어텐션의 softmax/layernorm은 CPU(비매핑) → 병목 모니터링
3. KV 캐시/메모리 대역폭이 병목이 될 수 있음(DDR은 PS 경유 → 대역폭 제약)

> ⚠️ ZCU102는 DDR이 **PS AXI 경유**이므로 순수 PL MIG(Virtex) 대비 메모리 대역폭이 낮습니다.
> LLM처럼 메모리 집약적인 워크로드는 대역폭이 성능 상한을 결정할 수 있습니다.

---

## 5. 대형 워크로드 = FireSim

Verilator로 ResNet50/LLM은 수일 걸립니다. **FireSim**(FPGA 가속 사이클 정확 시뮬레이션)을 사용하면
수 분~수십 분대로 단축되고, 정확한 성능 측정이 가능합니다.

- FireSim은 ASIC RTL을 FPGA에서 에뮬레이션 → 논문의 스피드업 수치가 이 환경 기준.
- FireSim은 별도 흐름(VCU118 기반 권장)이므로, 필요 시 별도 챕터로 확장.

```bash
# 개념 (FireSim 설치/클러스터 필요)
firesim buildbitstream
firesim runworkload
```

---

## 6. 기대 성능 감각 (참고)

| 모델 | 원논문 스피드업 (vs in-order Rocket, FireSim) |
|---|---|
| ResNet50 | 약 2,670× |
| AlexNet | 79.3 FPS |
| SqueezeNet v1.1 | 약 1,760× |
| BERT | 약 144× |
| MobileNetV2 | 약 127× (depthwise conv 비효율) |

> FPGA 실측은 위와 다를 수 있으며, **기준(baseline)**과 **메모리 대역폭**에 크게 좌우됩니다.

---

## 7. 완료 기준

- [ ] ResNet-50 FPGA 실행 PASS
- [ ] ONNX 모델 추론 성공 (top-k 결과 확인)
- [ ] (선택) LLM/트랜스포머 레이어 가속
- [ ] 성능 수치 기록 (FPS, cycles, 스피드업)

→ 다음: [Phase 7 — 프로파일링/최적화](Phase7_프로파일링_최적화.md)

---

## 8. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| 정확도 낮음 | 양자화/전처리 | 양자화 캘리브레이션, 입력 정규화 |
| 메모리 부족 | 모델+데이터 > DDR | 배치 축소, 타일 크기 조정 |
| Transpose 병목 | 레이아웃 변환 | NHWC 정렬, fused op |
| 느린 추론 | PS DDR 대역폭 | 타일 재사용↑, 캐시 활용 |
| Verilator 중단 | 사이클 과다 | FireSim/FPGA 사용 |
