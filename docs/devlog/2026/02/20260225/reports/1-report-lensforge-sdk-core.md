# Report: Sprint LF-01 — LensForge SDK Core + Dermatology Context Cluster

**Date**: 2026-02-25
**Sprint**: `sprint-lensforge-01-sdk-core.md`
**Status**: DONE
**Repository**: https://github.com/dantweb/lensforge

---

## Summary

Built the LensForge SDK — a context-agnostic pluggable Python AI vision microservice framework. The SDK provides a two-stage NN pipeline (NN1 safety filter + NN2 domain classification) with dynamic extension loading. First context cluster delivered: Dermatology (skin lesion screening).

## Architecture Decisions

### Context-Agnostic SDK

The SDK (`lensforge/`) contains zero model implementations. All models live in `custom/extensions/<context>/` and are loaded dynamically via dotted class paths from `custom/.env`. This follows OCP — adding a new context (plant, pet, art) requires zero SDK changes.

### Dynamic Extension Loading

Replaced `dependency-injector` Selector pattern with `importlib`-based dynamic class loading. The DI container reads dotted paths from config:

```python
# container.py
def import_class(dotted_path: str) -> type:
    module_path, class_name = dotted_path.rsplit(".", 1)
    module = importlib.import_module(module_path)
    return getattr(module, class_name)
```

Config specifies extension classes:
```env
QUALITY_CLASS=custom.extensions.dermatology.brisque_checker.BrisqueChecker
NSFW_CLASS=custom.extensions.dermatology.falconsai_nsfw.FalconsaiNsfwDetector
CLASSIFIER_CLASS=custom.extensions.dermatology.vit_skin.VitSkinClassifier
```

### Protocol-Based Interfaces (LSP)

Three protocol contracts ensure all implementations are interchangeable:
- `IQualityChecker` — `check(image) -> QualityResult`
- `INsfwDetector` — `detect(image) -> NsfwResult`
- `IDomainClassifier` — `classify(image) -> ClassificationResult`

All protocols include a `version` property for audit/reproducibility.

### Two-Stage Pipeline

```
Image → NN1: Quality Check → NN1: NSFW Filter → NN2: Domain Classifier → Response
           ✗ reject early     ✗ reject early       ✓ predictions + urgency
```

Early returns on NN1 rejection prevent wasting GPU time on NN2.

## Deliverables

### SDK Framework (`lensforge/`)

| Component | File | Purpose |
|-----------|------|---------|
| App factory | `app.py` | FastAPI with lifespan DI init |
| Config | `config.py` | pydantic-settings from `custom/.env` |
| DI Container | `container.py` | Dynamic importlib extension loading |
| Interfaces | `interfaces/` | IQualityChecker, INsfwDetector, IDomainClassifier |
| Pipeline | `pipeline/analysis_pipeline.py` | NN1→NN2 orchestration with early return |
| Image Loader | `loaders/image_loader.py` | Base64/URL, validate, resize, RGB convert |
| Routes | `routes/analyze.py` | POST /analyze, POST /batch-analyze |
| Schemas | `schemas/` | Pydantic request/response models |

### Dermatology Extension (`custom/extensions/dermatology/`)

| Component | File | Model |
|-----------|------|-------|
| NN1 Quality | `brisque_checker.py` | OpenCV Laplacian variance (CPU, no download) |
| NN1 Safety | `falconsai_nsfw.py` | Falconsai/nsfw_image_detection (HuggingFace, free) |
| NN2 Classifier | `vit_skin.py` | Anwarkh1/Skin_Cancer-Image_Classification (HAM10000) |

### Infrastructure

| File | Purpose |
|------|---------|
| `Dockerfile` | python:3.12-slim + OpenCV deps + PYTHONPATH=/app |
| `docker-compose.yaml` | Service + test profile with HF model cache volume |
| `Makefile` | Docker-based build/test/lint/format/run commands |
| `bin/pre-commit-check.sh` | Lint + unit tests in Docker (developer + CI) |
| `.github/workflows/ci.yaml` | GitHub Actions CI using pre-commit-check.sh |
| `pyproject.toml` | Dependencies, ruff config, pytest config |

### Documentation

| File | Purpose |
|------|---------|
| `README.md` | Quick start, project structure, usage |
| `docs/developer-guide.md` | Architecture, interfaces, extension guide, API reference |
| `docs/concept/` | Original LensForge concept documents |

## Test Results

**51 tests total** — all passing:

| Suite | Tests | Time |
|-------|-------|------|
| Unit: schemas | 6 | <0.1s |
| Unit: interfaces | 6 | <0.1s |
| Unit: image loader | 7 | <0.1s |
| Unit: pipeline | 7 | <0.1s |
| Unit: brisque checker | 5 | <0.1s |
| Unit: falconsai nsfw | 4 | <0.1s |
| Unit: vit skin | 5 | <0.1s |
| Unit: analyze endpoint | 5 | <0.1s |
| Unit: batch endpoint | 2 | <0.1s |
| Health endpoint | 1 | <0.1s |
| Integration (real models) | 1 | skipped in fast CI |
| **Total** | **51** | **0.42s** |

## SOLID Compliance

| Principle | How |
|-----------|-----|
| **SRP** | Each class has one job: BrisqueChecker checks quality, FalconsaiNsfwDetector detects NSFW, etc. |
| **OCP** | New context = new extension folder + .env change. Zero SDK modifications. |
| **LSP** | All implementations fully interchangeable via protocols. |
| **ISP** | Three small focused protocols, not one fat interface. |
| **DIP** | AnalysisPipeline depends on protocols, never concrete classes. Wired via DI. |

## Issues Resolved

1. **Dockerfile build**: `libgl1-mesa-glx` renamed to `libgl1` in Debian Trixie
2. **pip install**: Added `[build-system]` to pyproject.toml for setuptools
3. **PYTHONPATH**: Added `ENV PYTHONPATH=/app` so `custom/` extensions are importable
4. **dependency-injector @inject**: Replaced with `request.app.state.container` pattern
5. **Import ordering**: Fixed with ruff auto-format
6. **Pre-commit entrypoint**: Override pytest entrypoint with `--entrypoint ruff` for lint

## Sprint Deviations from Plan

| Planned | Actual | Reason |
|---------|--------|--------|
| Models in `lensforge/models/` | Models in `custom/extensions/dermatology/` | SDK must be context-agnostic per product requirement |
| `Selector` providers in DI | `importlib` dynamic loading | Supports unlimited extension classes without SDK code changes |
| `requirements-dev.txt` | `pyproject.toml [dev]` extras | Modern Python packaging standard |
| Local `make` commands | Docker-only `make` commands | Development workflow requirement |
| `make type-check` (mypy) | Deferred | Focus on runtime correctness first |

## API Models (No Keys Required)

All models used in this sprint are free, public, and run on CPU:

| Model | Source | License | Download |
|-------|--------|---------|----------|
| OpenCV BRISQUE | pip (opencv-contrib-python-headless) | Apache 2.0 | Bundled |
| Falconsai NSFW | huggingface.co/Falconsai/nsfw_image_detection | Apache 2.0 | Auto ~350MB |
| ViT Skin (HAM10000) | huggingface.co/Anwarkh1/Skin_Cancer-Image_Classification | Apache 2.0 | Auto ~350MB |
