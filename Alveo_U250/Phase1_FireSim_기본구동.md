# Phase 1 — FireSim 기본 구동

> 목표: 사전 빌드된(또는 기본 레시피로 빌드한) 비트스트림을 Alveo U250에 올리고,
> 단일코어 Rocket 대상 시뮬레이션을 실행하여 워크로드를 동작시킨다.

---

## 0. 요약 체크리스트

- [ ] FireSim 환경 로드 (`source sourceme-manager.sh`)
- [ ] `config_build.yaml`에 빌드 대상 지정
- [ ] 비트스트림 빌드 (`firesim buildbitstream`)
- [ ] `config_hwdb.yaml`에 FPGA 이미지 등록
- [ ] `config_runtime.yaml`에 실행 대상 지정
- [ ] 워크로드 실행 (`firesim runworkload`)
- [ ] 결과 확인 (`results-workload/`)

---

## 1. FireSim 구성 파일 3종

FireSim은 `deploy/` 아래 3개 YAML로 빌드/실행을 제어합니다.

| 파일 | 역할 |
|---|---|
| `config_build.yaml` | **무엇을 FPGA에 굽나** (하드웨어 설계) |
| `config_hwdb.yaml` | **빌드된 비트스트림 목록** (HWDB) |
| `config_runtime.yaml` | **무엇을 얼마나 돌리나** (워크로드 + 파라미터) |

이 저장소 `code/`에 예시 파일을 두었습니다.

---

## 2. 빌드 대상 지정 (`config_build.yaml`)

기본 대상은 단일코어 Rocket (Gemmini 없음) — 파이프라인 검증용입니다.

```yaml
build_farm:
    base_recipe: build-farm-recipes/externally_provisioned.yaml
    recipe_arg_overrides:
        build_farm_hosts:
            - "localhost"        # 로컬 빌드

builds_to_run:
    - alveo_u250_firesim_rocket_singlecore_no_nic

builds_to_run_with_priority: []
```

레시피 정의(`sims/firesim-staging/sample_config_build_recipes.yaml`)에서 해당 항목:

```yaml
alveo_u250_firesim_rocket_singlecore_no_nic:
    DESIGN: FireSim
    TARGET_CONFIG: FireSimRocketConfig
    PLATFORM_CONFIG: WithAutoILA            # (또는 기본)
    platform_config_args:
        fpga_frequency: 100
        ...
    deploy_strategy: no_nic
    TARGET_PROJECT_MAKEFRAG: firesim/sample_project/Makefrag
    bit_builder_recipe: bit-builder-recipes/xilinx_alveo_u250.yaml
    # ...
```

`bit_builder_recipe`가 `xilinx_alveo_u250`을 가리키는지 확인합니다.

---

## 3. 비트스트림 빌드

```bash
cd ~/firesim
source sourceme-manager.sh
source /tools/Xilinx/Vivado/2021.1/settings64.sh

firesim buildbitstream -r deploy/config_build.yaml
```

- Chisel RTL → Vivado 합성/배치배선 → `.bit` 생성.
- **소요: 수 시간** (대형 설계). 로그 경로가 출력됩니다.
- 산출물: `deploy/results-build/<...>/` 아래 `*.bit`, `.tar.gz` 등.

---

## 4. HWDB 등록 (`config_hwdb.yaml`)

빌드 완료 시 `firesim buildbitstream`가 **HWDB에 붙여넣을 항목**(`bitstream_tar` 경로)을 출력합니다.

```yaml
firesim_rocket_singlecore_no_nic_alveo_u250:
    bitstream_tar: deploy/results-build/<...>/<...>.tar.gz
    deploy_manager: XilinxAlveoU250InstanceDeployManager
```

---

## 5. 실행 대상 지정 (`config_runtime.yaml`)

```yaml
run_farm:
    base_recipe: run-farm-recipes/externally_provisioned.yaml
    recipe_arg_overrides:
        run_farm_hosts_to_use:
            - localhost: 1

default_hw_config: firesim_rocket_singlecore_no_nic_alveo_u250

workload:
    workload_name: linux-uniform.json      # 또는 baremetal json
    terminate_on_completion: true

    # (선택) 모델/트레이스
    # tracer: ...
```

- `default_hw_config`는 HWDB의 키와 일치해야 합니다.
- `default_platform`(일부 버전) → `XilinxAlveoU250InstanceDeployManager`.

---

## 6. 워크로드 실행

```bash
firesim runworkload -r deploy/config_runtime.yaml
```

진행 상황은 별도 터미널에서:
```bash
firesim infrasetup
firesim runinfra
# 또는 runworkload가 내부적으로 호출
```

콘솔(Target-side) 출력은 로그로 저장됩니다:
```bash
cat deploy/logs/<...>/...
```

---

## 7. 결과 확인

```bash
ls deploy/results-workload/
# <run>/<job>/... 에 출력 로그 저장
```

- 리눅스 부팅 로그, 프로그램 stdout, (설정 시) TracerV 트레이스 등.

---

## 8. 완료 기준

- [ ] `firesim buildbitstream` 성공 (bitstream 생성)
- [ ] HWDB 등록 성공
- [ ] `lspci`/`xbmgmt`에서 카드 정상
- [ ] `firesim runworkload` 성공, Rocket 시뮬 콘솔 로그 확인

→ 다음: [Phase 2 — 커스텀 비트스트림 (Rocket+Gemmini)](Phase2_커스텀비트스트림_Rocket_Gemmini.md)

---

## 9. 트러블슈팅

| 증상 | 원인 | 해결 |
|---|---|---|
| `buildbitstream` 실패 | Vivado 버전/BSP | 2021.1 + au250 BSP 확인 |
| PCIe link down | 비트스트림/셸 | PCIe 셸 복구 스크립트 |
| 시뮬 시작 안 함 | HWDB/런타임 불일치 | 키 이름 일치, deploy_manager 확인 |
| 워크로드 즉시 종료 | workload json 오류 | `terminate_on_completion`, 로그 확인 |
| 매우 느림 | FPGA freq 낮음 | `fpga_frequency` 상향(타이밍 여유 시) |
