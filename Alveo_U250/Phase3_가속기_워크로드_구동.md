# Phase 3 — 가속기 워크로드 구동

> 목표: FireSim에서 Gemmini 가속기로 GEMM/컨볼루션, ResNet, (BERT/소형) LLM 워크로드를 실행한다.

---

## 0. 요약 체크리스트

- [ ] Gemmini 테스트(GEMM/Conv) 워크로드 실행
- [ ] ResNet-50 워크로드 실행
- [ ] ONNX/LLM 워크로드 시도
- [ ] 워크로드 JSON 구성 이해

---

## 1. FireSim 워크로드 개념

FireSim은 **워크로드 JSON**으로 타깃에서 무엇을 실행할지 정의합니다.

- **bare-metal 워크로드**: 단일 바이너리 실행 (`*.json`)
- **Linux 워크로드**: FireMarshal 이미지로 부팅 후 프로그램 실행 (`linux-uniform.json` 등)

Gemmini DNN은 대개 **리눅스 사용자 공간**에서 실행하여 end-to-end 성능을 측정합니다(논문 방식).

---

## 2. Gemmini 테스트 워크로드

### 2.1 소형 GEMM/Conv (빠른 검증)

FireMarshal로 Gemmini 테스트를 포함한 루트fs를 만들거나,
이미 `gemmini-rocc-tests`가 포함된 이미지를 사용합니다.

```bash
# FireMarshal 이미지에 테스트 포함 (예)
cd ~/firesim/software/firemarshal
# gemmini 테스트 바이너리를 overlay/에 추가 후
./marshal -v build <workload>.json
```

### 2.2 워크로드 실행

```bash
firesim runworkload -r deploy/config_runtime.yaml
```

`config_runtime.yaml`의 `workload.workload_name`을 사용할 JSON으로 지정:

```yaml
workload:
    workload_name: gemmini-matmul.json
    terminate_on_completion: true
```

---

## 3. ResNet-50 워크로드

Gemmini는 `gemmini-rocc-tests/imagenet/resnet50`를 제공합니다.

```yaml
workload:
    workload_name: resnet50-linux.json
    terminate_on_completion: true
```

예상 콘솔 출력(참고):
```text
Prediction: 75 (score: 45)
...
Total cycles: 1358733049 (100%)
Conv cycles:    818013564 (60%)
Matmul cycles:  508263409 (37%)
Res add cycles:  32258198  (2%)
PASS
```

> **FireSim은 사이클 정확**하므로 위 사이클 수가 실제 성능 지표가 됩니다.

---

## 4. ONNX / LLM 워크로드

### 4.1 ONNX Runtime 백엔드

Gemmini용 ONNX Runtime 포트를 사용해 임의 ONNX 모델 추론:

```yaml
workload:
    workload_name: onnx-resnet50.json
```

콘솔:
```text
Element count 1000. Top 5 classes:
0.361813 Rottweiler
Done! Inference took 495827001 cycles
```

### 4.2 LLM (BERT/소형 트랜스포머)

- 대부분 **큰 GEMM** → Gemmini에 유리.
- 어텐션 softmax/layernorm은 CPU 처리 → 병목 모니터링.
- KV 캐시/메모리 대역폭: FireSim FASED DDR 모델로 정확히 반영(U250은 77GB/s).

```yaml
workload:
    workload_name: bert-base.json
    terminate_on_completion: true
```

> FireSim은 AWS F1/EC2 또는 온프레미스 Alveo에서 대형 워크로드를 수 분~수십 분에 실행.

---

## 5. 워크로드 JSON 구조(요약)

```json
{
  "benchmark_name": "resnet50",
  "common_bootbinary": "...",
  "common_rootfs": "...",
  "jobs": [
    {
      "jobname": "resnet50",
      "simulation_config": { "clock_rate_hz": 3200000000 },
      "outputs": null,
      "workload": "path/to/run.sh"
    }
  ]
}
```

- `common_bootbinary`: 부팅 바이너리(예: `fw_payload.elf`)
- `common_rootfs`: 루트fs 이미지
- `jobs[].workload`: 실행 스크립트/명령
- `clock_rate_hz`: 성능 환산 기준 클럭(예: 3.2GHz)

> **성능 수치(FPS/스피드업)는 `clock_rate_hz` 기준으로 환산**되므로, 실제 FPGA 주파수와 구분해야 합니다.

---

## 6. 완료 기준

- [ ] GEMM/Conv 워크로드 PASS
- [ ] ResNet-50 워크로드 실행 및 prediction 출력
- [ ] (선택) ONNX/LLM 워크로드 실행
- [ ] 각 워크로드 사이클/성능 로그 확보

→ 다음: [Phase 4 — 성능측정/프로파일링](Phase4_성능측정_프로파일링.md)

---

## 7. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| 워크로드 즉시 종료 | JSON/경로 오류 | `workload_name`, `workload` 스크립트 확인 |
| 정확도 낮음 | 양자화/전처리 | int8 캘리브레이션, 입력 정규화 |
| SIGILL | RoCC 권한 | 리눅스/OpenSBI RoCC 설정(ZCU102 Phase 4와 동일 이슈) |
| 메모리 부족 | 모델+데이터 | 배치/타일 축소, DDR 채널 증설 |
| 매우 느림 | FPGA freq 낮음 | `fpga_frequency` 상향 |
