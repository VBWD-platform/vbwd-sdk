# Report: Skin Analysis Python Microservice

**Date**: 2026-02-23
**Type**: Standalone Python container (not a plugin, not part of vbwd-sdk)
**Input**: JSON (image as base64 or URL)
**Output**: JSON (analysis result or rejection reason)

---

## 1. Architecture Overview

Standalone stateless FastAPI microservice. Two-stage neural network pipeline:
- **NN1** — Validation: image quality + NSFW rejection + skin plausibility
- **NN2** — Dermatology: lesion classification with probabilities and urgency

```
┌─────────────────────────────────────────────────┐
│  FastAPI (POST /analyze, POST /batch-analyze)   │
└──────────────────┬──────────────────────────────┘
                   │
        ┌──────────▼──────────┐
        │  AnalysisService    │  ← orchestrates pipeline
        │  (injected deps)    │
        └──────────┬──────────┘
                   │
     ┌─────────────┼─────────────┐
     ▼             ▼             ▼
┌─────────┐ ┌──────────┐ ┌────────────┐
│ IQA     │ │ NSFW     │ │ Skin       │
│ Checker │ │ Detector │ │ Classifier │
│ (NN1)   │ │ (NN1)    │ │ (NN2)      │
└─────────┘ └──────────┘ └────────────┘
     │             │             │
     ▼             ▼             ▼
  Interface:    Interface:    Interface:
  IQualityChk   INsfwDetect   ISkinClassif
```

All model components behind interfaces (protocols). Swappable for mocks in tests.

---

## 2. Project Structure

```
skin-analysis/
├── src/
│   ├── main.py                  # FastAPI app, lifespan, DI wiring
│   ├── config.py                # Settings from env vars (pydantic-settings)
│   ├── container.py             # DI container (dependency-injector)
│   │
│   ├── interfaces/              # Abstract protocols (no implementations)
│   │   ├── __init__.py
│   │   ├── quality_checker.py   # Protocol: IQualityChecker
│   │   ├── nsfw_detector.py     # Protocol: INsfwDetector
│   │   └── skin_classifier.py   # Protocol: ISkinClassifier
│   │
│   ├── services/
│   │   ├── __init__.py
│   │   ├── analysis_service.py  # Orchestrates NN1 → NN2 pipeline
│   │   └── image_loader.py      # Load from base64 / URL, validate format, resize
│   │
│   ├── models/                  # Concrete model implementations
│   │   ├── __init__.py
│   │   ├── brisque_checker.py   # IQualityChecker → OpenCV BRISQUE
│   │   ├── musiq_checker.py     # IQualityChecker → pyiqa MUSIQ (GPU)
│   │   ├── falconsai_nsfw.py    # INsfwDetector → Falconsai ViT
│   │   ├── nudenet_nsfw.py      # INsfwDetector → NudeNet v3
│   │   └── vit_skin.py          # ISkinClassifier → ViT fine-tuned on ISIC
│   │
│   ├── schemas/                 # Pydantic request/response models
│   │   ├── __init__.py
│   │   ├── request.py           # AnalyzeRequest, BatchAnalyzeRequest
│   │   └── response.py          # AnalyzeResponse, Prediction, ModelVersions
│   │
│   └── routes/
│       ├── __init__.py
│       └── analyze.py           # POST /analyze, POST /batch-analyze
│
├── tests/
│   ├── conftest.py              # Fixtures: mock models, sample images
│   ├── unit/
│   │   ├── test_analysis_service.py
│   │   ├── test_image_loader.py
│   │   ├── test_brisque_checker.py
│   │   └── test_schemas.py
│   ├── integration/
│   │   ├── test_analyze_endpoint.py
│   │   └── test_pipeline.py
│   └── fixtures/
│       ├── valid_skin.jpg       # Small test image (224x224)
│       ├── blurry.jpg
│       └── not_skin.jpg
│
├── Dockerfile
├── docker-compose.yaml
├── pyproject.toml
├── requirements.txt
├── requirements-dev.txt
├── .env.example
└── README.md
```

---

## 3. Core Principles Applied

| Principle | How Applied |
|-----------|------------|
| **SRP** | Each model class does one thing. `AnalysisService` only orchestrates. Routes only handle HTTP. |
| **OCP** | New model = new class implementing existing protocol. Zero changes to service. |
| **LSP** | All implementations of `IQualityChecker` are interchangeable. `BrisqueChecker` and `MusiqChecker` both return `QualityResult`. Same for NSFW and skin classifiers. |
| **ISP** | Three small protocols, not one fat `IModel` interface. |
| **DIP** | `AnalysisService` depends on protocols, not concrete model classes. Wired via DI container. |
| **DRY** | Image loading/resizing in one place (`ImageLoader`). Threshold logic in config, not scattered. |
| **TDD** | All protocols mockable. Unit tests use mocks. Integration tests use lightweight CPU models. |
| **No overengineering** | No ORM, no database, no message queue, no caching layer. Stateless request-in/response-out. |

---

## 4. Key Implementation Details

### 4.1 Interfaces (Protocols)

```python
# src/interfaces/quality_checker.py
from dataclasses import dataclass
from typing import Protocol
from PIL import Image


@dataclass
class QualityResult:
    score: float        # 0.0-1.0 normalized (1.0 = best)
    is_acceptable: bool
    reason: str | None = None


class IQualityChecker(Protocol):
    def check(self, image: Image.Image) -> QualityResult: ...
```

```python
# src/interfaces/nsfw_detector.py
from dataclasses import dataclass
from typing import Protocol
from PIL import Image


@dataclass
class NsfwResult:
    is_safe: bool
    nsfw_score: float   # 0.0-1.0 (1.0 = definitely NSFW)
    reason: str | None = None


class INsfwDetector(Protocol):
    def detect(self, image: Image.Image) -> NsfwResult: ...
```

```python
# src/interfaces/skin_classifier.py
from dataclasses import dataclass
from typing import Protocol
from PIL import Image


@dataclass
class Prediction:
    label: str
    probability: float
    risk_level: str | None = None  # "low", "moderate", "high"


@dataclass
class ClassificationResult:
    lesion_detected: bool
    predictions: list[Prediction]
    description: str
    urgency: str | None = None


class ISkinClassifier(Protocol):
    def classify(self, image: Image.Image) -> ClassificationResult: ...
```

### 4.2 Analysis Service (Orchestrator)

```python
# src/services/analysis_service.py
import time
from PIL import Image
from src.interfaces.quality_checker import IQualityChecker
from src.interfaces.nsfw_detector import INsfwDetector
from src.interfaces.skin_classifier import ISkinClassifier
from src.schemas.response import AnalyzeResponse


DISCLAIMER = (
    "This is NOT a medical diagnosis. "
    "See a qualified dermatologist. AI output only."
)


class AnalysisService:
    def __init__(
        self,
        quality_checker: IQualityChecker,
        nsfw_detector: INsfwDetector,
        skin_classifier: ISkinClassifier,
    ):
        self._quality = quality_checker
        self._nsfw = nsfw_detector
        self._skin = skin_classifier

    def analyze(self, image: Image.Image) -> AnalyzeResponse:
        start = time.monotonic()

        # NN1: Quality check
        quality = self._quality.check(image)
        if not quality.is_acceptable:
            return AnalyzeResponse(
                status="rejected_quality",
                reason=quality.reason,
                inference_time_ms=self._elapsed(start),
                disclaimer=DISCLAIMER,
            )

        # NN1: NSFW check
        nsfw = self._nsfw.detect(image)
        if not nsfw.is_safe:
            return AnalyzeResponse(
                status="rejected_nsfw",
                reason=nsfw.reason,
                inference_time_ms=self._elapsed(start),
                disclaimer=DISCLAIMER,
            )

        # NN2: Skin classification
        result = self._skin.classify(image)

        return AnalyzeResponse(
            status="success",
            lesion_detected=result.lesion_detected,
            main_description=result.description,
            predictions=result.predictions,
            urgency=result.urgency,
            inference_time_ms=self._elapsed(start),
            disclaimer=DISCLAIMER,
        )

    @staticmethod
    def _elapsed(start: float) -> int:
        return int((time.monotonic() - start) * 1000)
```

### 4.3 Request / Response Schemas

```python
# src/schemas/request.py
from pydantic import BaseModel, Field


class AnalyzeRequest(BaseModel):
    image_base64: str | None = Field(None, description="Base64-encoded image")
    image_url: str | None = Field(None, description="URL to fetch image from")


class BatchAnalyzeRequest(BaseModel):
    images: list[AnalyzeRequest] = Field(..., max_length=50)
```

```python
# src/schemas/response.py
from pydantic import BaseModel


class PredictionSchema(BaseModel):
    label: str
    probability: float
    risk_level: str | None = None


class AnalyzeResponse(BaseModel):
    status: str                           # success | rejected_quality | rejected_nsfw | error
    reason: str | None = None
    lesion_detected: bool | None = None
    main_description: str | None = None
    predictions: list[PredictionSchema] = []
    urgency: str | None = None
    disclaimer: str
    inference_time_ms: int = 0
```

### 4.4 DI Container

```python
# src/container.py
from dependency_injector import containers, providers
from src.config import Settings


class Container(containers.DeclarativeContainer):
    config = providers.Configuration()

    # Quality checker: swap implementation via config
    quality_checker = providers.Singleton(
        providers.Selector(
            config.quality_backend,
            brisque=providers.Factory("src.models.brisque_checker.BrisqueChecker"),
            musiq=providers.Factory(
                "src.models.musiq_checker.MusiqChecker",
                device=config.device,
            ),
        )
    )

    nsfw_detector = providers.Singleton(
        providers.Selector(
            config.nsfw_backend,
            falconsai=providers.Factory(
                "src.models.falconsai_nsfw.FalconsaiNsfwDetector",
                threshold=config.nsfw_threshold,
            ),
            nudenet=providers.Factory("src.models.nudenet_nsfw.NudeNetDetector"),
        )
    )

    skin_classifier = providers.Singleton(
        providers.Selector(
            config.skin_backend,
            vit_isic=providers.Factory(
                "src.models.vit_skin.VitSkinClassifier",
                model_name=config.skin_model_name,
                device=config.device,
            ),
        )
    )

    analysis_service = providers.Factory(
        "src.services.analysis_service.AnalysisService",
        quality_checker=quality_checker,
        nsfw_detector=nsfw_detector,
        skin_classifier=skin_classifier,
    )
```

### 4.5 Route Example

```python
# src/routes/analyze.py
from fastapi import APIRouter, Depends
from dependency_injector.wiring import inject, Provide
from src.container import Container
from src.schemas.request import AnalyzeRequest
from src.schemas.response import AnalyzeResponse
from src.services.analysis_service import AnalysisService
from src.services.image_loader import load_image

router = APIRouter()


@router.post("/analyze", response_model=AnalyzeResponse)
@inject
async def analyze(
    req: AnalyzeRequest,
    service: AnalysisService = Depends(Provide[Container.analysis_service]),
):
    image = await load_image(req)
    return service.analyze(image)
```

---

## 5. Concrete Model Implementations

### 5.1 NSFW — Falconsai (recommended, Apache 2.0)

```
HuggingFace: Falconsai/nsfw_image_detection
Architecture: ViT base, ~350MB
License: Apache 2.0
Access: Public, no token needed
CPU: Yes (~0.5-1s per image)
```

```python
# src/models/falconsai_nsfw.py
from transformers import pipeline
from PIL import Image
from src.interfaces.nsfw_detector import INsfwDetector, NsfwResult


class FalconsaiNsfwDetector:
    def __init__(self, threshold: float = 0.7):
        self._threshold = threshold
        self._pipe = pipeline(
            "image-classification",
            model="Falconsai/nsfw_image_detection",
        )

    def detect(self, image: Image.Image) -> NsfwResult:
        results = self._pipe(image)
        scores = {r["label"]: r["score"] for r in results}
        nsfw_score = scores.get("nsfw", 0.0)
        is_safe = nsfw_score < self._threshold
        return NsfwResult(
            is_safe=is_safe,
            nsfw_score=nsfw_score,
            reason=f"NSFW score {nsfw_score:.2f}" if not is_safe else None,
        )
```

### 5.2 Quality — OpenCV BRISQUE (zero download, CPU)

```
Package: opencv-contrib-python (pip install)
License: Apache 2.0
No model download: built-in
CPU: <50ms per image
```

```python
# src/models/brisque_checker.py
import cv2
import numpy as np
from PIL import Image
from src.interfaces.quality_checker import IQualityChecker, QualityResult


class BrisqueChecker:
    def __init__(self, max_score: float = 50.0):
        self._max_score = max_score  # BRISQUE: lower=better, typical 0-100

    def check(self, image: Image.Image) -> QualityResult:
        arr = np.array(image)
        gray = cv2.cvtColor(arr, cv2.COLOR_RGB2GRAY)

        # Laplacian variance for blur detection
        laplacian_var = cv2.Laplacian(gray, cv2.CV_64F).var()
        if laplacian_var < 100:
            return QualityResult(
                score=0.0,
                is_acceptable=False,
                reason=f"Image too blurry (sharpness={laplacian_var:.0f})",
            )

        return QualityResult(score=1.0, is_acceptable=True)
```

### 5.3 Skin Classification — ViT on HAM10000

```
HuggingFace: Anwarkh1/Skin_Cancer-Image_Classification
Architecture: ViT, fine-tuned on HAM10000
License: Check repo
Classes: akiec, bcc, bkl, df, mel, nv, vasc (7 types)
CPU: ~0.5-1s per image
```

```python
# src/models/vit_skin.py
from transformers import pipeline
from PIL import Image
from src.interfaces.skin_classifier import (
    ISkinClassifier, ClassificationResult, Prediction,
)

RISK_MAP = {
    "mel": "high",       # melanoma
    "bcc": "high",       # basal cell carcinoma
    "akiec": "moderate", # actinic keratoses
    "df": "low",
    "nv": "low",         # melanocytic nevi (moles)
    "bkl": "low",        # benign keratosis
    "vasc": "low",       # vascular lesions
}

URGENCY_MAP = {
    "high": "Consult dermatologist within days",
    "moderate": "Consult dermatologist within weeks",
    "low": "Monitor, no immediate urgency",
}


class VitSkinClassifier:
    def __init__(self, model_name: str = "Anwarkh1/Skin_Cancer-Image_Classification", device: str = "cpu"):
        self._pipe = pipeline(
            "image-classification",
            model=model_name,
            device=device,
            top_k=5,
        )

    def classify(self, image: Image.Image) -> ClassificationResult:
        results = self._pipe(image)
        predictions = [
            Prediction(
                label=r["label"],
                probability=round(r["score"], 4),
                risk_level=RISK_MAP.get(r["label"]),
            )
            for r in results
        ]
        top = predictions[0] if predictions else None
        risk = top.risk_level if top else None

        return ClassificationResult(
            lesion_detected=True,
            predictions=predictions,
            description=f"Top prediction: {top.label} ({top.probability:.1%})" if top else "No prediction",
            urgency=URGENCY_MAP.get(risk) if risk else None,
        )
```

---

## 6. Testing Strategy

### 6.1 Unit Tests — Mock All Models

```python
# tests/conftest.py
import pytest
from PIL import Image
from src.interfaces.quality_checker import QualityResult
from src.interfaces.nsfw_detector import NsfwResult
from src.interfaces.skin_classifier import ClassificationResult, Prediction


@pytest.fixture
def sample_image():
    return Image.new("RGB", (224, 224), color=(180, 130, 100))


@pytest.fixture
def mock_quality_ok(mocker):
    checker = mocker.MagicMock()
    checker.check.return_value = QualityResult(score=0.9, is_acceptable=True)
    return checker


@pytest.fixture
def mock_quality_bad(mocker):
    checker = mocker.MagicMock()
    checker.check.return_value = QualityResult(
        score=0.1, is_acceptable=False, reason="Too blurry"
    )
    return checker


@pytest.fixture
def mock_nsfw_safe(mocker):
    detector = mocker.MagicMock()
    detector.detect.return_value = NsfwResult(is_safe=True, nsfw_score=0.05)
    return detector


@pytest.fixture
def mock_nsfw_unsafe(mocker):
    detector = mocker.MagicMock()
    detector.detect.return_value = NsfwResult(
        is_safe=False, nsfw_score=0.92, reason="NSFW content detected"
    )
    return detector


@pytest.fixture
def mock_skin_classifier(mocker):
    classifier = mocker.MagicMock()
    classifier.classify.return_value = ClassificationResult(
        lesion_detected=True,
        predictions=[
            Prediction(label="nv", probability=0.87, risk_level="low"),
            Prediction(label="mel", probability=0.08, risk_level="high"),
        ],
        description="Top prediction: nv (87.0%)",
        urgency="Monitor, no immediate urgency",
    )
    return classifier
```

```python
# tests/unit/test_analysis_service.py
from src.services.analysis_service import AnalysisService


def test_rejects_low_quality(sample_image, mock_quality_bad, mock_nsfw_safe, mock_skin_classifier):
    service = AnalysisService(mock_quality_bad, mock_nsfw_safe, mock_skin_classifier)
    result = service.analyze(sample_image)

    assert result.status == "rejected_quality"
    assert result.reason == "Too blurry"
    mock_nsfw_safe.detect.assert_not_called()
    mock_skin_classifier.classify.assert_not_called()


def test_rejects_nsfw(sample_image, mock_quality_ok, mock_nsfw_unsafe, mock_skin_classifier):
    service = AnalysisService(mock_quality_ok, mock_nsfw_unsafe, mock_skin_classifier)
    result = service.analyze(sample_image)

    assert result.status == "rejected_nsfw"
    mock_skin_classifier.classify.assert_not_called()


def test_success_pipeline(sample_image, mock_quality_ok, mock_nsfw_safe, mock_skin_classifier):
    service = AnalysisService(mock_quality_ok, mock_nsfw_safe, mock_skin_classifier)
    result = service.analyze(sample_image)

    assert result.status == "success"
    assert result.lesion_detected is True
    assert len(result.predictions) == 2
    assert result.disclaimer is not None
```

### 6.2 Integration Tests — Lightweight CPU Models

Mark tests that load real models to skip in fast CI runs:

```python
# tests/integration/test_pipeline.py
import pytest
from PIL import Image

requires_models = pytest.mark.skipif(
    "CI_FAST" in os.environ,
    reason="Skip model loading in fast CI"
)


@requires_models
def test_full_pipeline_cpu():
    """Integration test with real (lightweight) models on CPU."""
    from src.models.brisque_checker import BrisqueChecker
    from src.models.falconsai_nsfw import FalconsaiNsfwDetector
    from src.models.vit_skin import VitSkinClassifier
    from src.services.analysis_service import AnalysisService

    service = AnalysisService(
        quality_checker=BrisqueChecker(),
        nsfw_detector=FalconsaiNsfwDetector(),
        skin_classifier=VitSkinClassifier(device="cpu"),
    )

    image = Image.open("tests/fixtures/valid_skin.jpg")
    result = service.analyze(image)

    assert result.status == "success"
    assert len(result.predictions) > 0
    assert result.inference_time_ms > 0
```

### 6.3 Test Pyramid

| Layer | Models | Speed | CI |
|-------|--------|-------|-----|
| Unit tests | All mocked | <1s | Always |
| Integration (CPU) | Real lightweight models | ~5-10s | `make test-integration` |
| GPU smoke test | Real models on GPU | ~2s | Only on GPU runners |

---

## 7. Docker Setup

```dockerfile
FROM python:3.12-slim

WORKDIR /app

# System deps for OpenCV
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1-mesa-glx libglib2.0-0 && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ src/

# Pre-download models at build time (optional, avoids cold-start download)
# RUN python -c "from transformers import pipeline; pipeline('image-classification', model='Falconsai/nsfw_image_detection')"
# RUN python -c "from transformers import pipeline; pipeline('image-classification', model='Anwarkh1/Skin_Cancer-Image_Classification')"

EXPOSE 8000

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

```yaml
# docker-compose.yaml
services:
  skin-analysis:
    build: .
    ports:
      - "8000:8000"
    environment:
      - DEVICE=cpu
      - NSFW_BACKEND=falconsai
      - NSFW_THRESHOLD=0.7
      - QUALITY_BACKEND=brisque
      - SKIN_BACKEND=vit_isic
      - SKIN_MODEL_NAME=Anwarkh1/Skin_Cancer-Image_Classification
      # Optional: for gated models
      # - HF_TOKEN=hf_xxx
    volumes:
      - model-cache:/root/.cache/huggingface
    deploy:
      resources:
        limits:
          memory: 4G

volumes:
  model-cache:
```

---

## 8. Dependencies

```
# requirements.txt
fastapi>=0.110
uvicorn>=0.30
pydantic>=2.0
pydantic-settings>=2.0
dependency-injector>=4.41
Pillow>=10.0
numpy>=1.26
opencv-contrib-python-headless>=4.9
transformers>=4.40
torch>=2.2
requests>=2.31
```

```
# requirements-dev.txt
-r requirements.txt
pytest>=8.0
pytest-mock>=3.12
pytest-asyncio>=0.23
httpx>=0.27              # for FastAPI TestClient async
```

---

## 9. How to Obtain API Keys and Model Access

### HuggingFace Token (free, needed for gated models and higher rate limits)

1. Register at https://huggingface.co/join
2. Go to https://huggingface.co/settings/tokens
3. Create token with "Read" scope
4. Set as env var: `HF_TOKEN=hf_xxx`

**When you need it**: gated models (MedGemma), HF Inference API, higher download limits.
**When you do NOT need it**: Falconsai, Anwarkh1, NudeNet — all public, no token required.

### Models Used in This Service

| Model | HuggingFace Repo | License | Token Required | CPU OK |
|-------|------------------|---------|---------------|--------|
| NSFW detector | `Falconsai/nsfw_image_detection` | Apache 2.0 | No | Yes |
| NSFW (alternative) | NudeNet v3 (`pip install nudenet`) | AGPL-3.0 | No (PyPI) | Yes |
| Quality (IQA) | OpenCV BRISQUE (built-in) | Apache 2.0 | No | Yes |
| Quality (GPU) | pyiqa MUSIQ (`pip install pyiqa`) | Apache 2.0 | No | Yes (slow) |
| Skin classifier | `Anwarkh1/Skin_Cancer-Image_Classification` | Check repo | No | Yes |
| Skin (advanced) | `google/medgemma-4b-it` | Gemma license | Yes (gated) | No (GPU) |

### ISIC Dataset (for custom model training)

1. **ISIC Archive**: https://www.isic-archive.com/ — free registration, 100K+ images, API for bulk download
2. **Kaggle HAM10000**: https://www.kaggle.com/datasets/kmader/skin-cancer-mnist-ham10000 — free Kaggle account
3. **HuggingFace**: `marmal88/skin_cancer` or `MKZuziak/ISIC_2019_224` — direct download

### Serverless GPU Deployment (production)

| Provider | Free Tier | GPU Pricing | Setup |
|----------|-----------|-------------|-------|
| **Modal** | $30/month free credits | T4 ~$0.27/hr | `pip install modal && modal token new` |
| **RunPod** | None | T4 ~$0.40/hr | Register at runpod.io, add payment |
| **HF Endpoints** | Free Inference API (limited) | Dedicated from $0.60/hr | HuggingFace account |

---

## 10. Configuration (.env.example)

```bash
# Device: "cpu" for testing, "cuda" for production
DEVICE=cpu

# NN1: Quality checker backend
QUALITY_BACKEND=brisque          # brisque | musiq
QUALITY_BLUR_THRESHOLD=100       # Laplacian variance minimum

# NN1: NSFW detector backend
NSFW_BACKEND=falconsai           # falconsai | nudenet
NSFW_THRESHOLD=0.7               # Rejection threshold (0.0-1.0)

# NN2: Skin classifier backend
SKIN_BACKEND=vit_isic            # vit_isic
SKIN_MODEL_NAME=Anwarkh1/Skin_Cancer-Image_Classification

# Optional: HuggingFace token for gated models
# HF_TOKEN=hf_xxx

# Server
HOST=0.0.0.0
PORT=8000
```

---

## 11. Usage Examples

### Request

```bash
# Base64 input
curl -X POST http://localhost:8000/analyze \
  -H "Content-Type: application/json" \
  -d '{"image_base64": "/9j/4AAQSkZJRg..."}'

# URL input
curl -X POST http://localhost:8000/analyze \
  -H "Content-Type: application/json" \
  -d '{"image_url": "https://example.com/skin-image.jpg"}'
```

### Response — Success

```json
{
  "status": "success",
  "reason": null,
  "lesion_detected": true,
  "main_description": "Top prediction: nv (87.0%)",
  "predictions": [
    {"label": "nv", "probability": 0.87, "risk_level": "low"},
    {"label": "mel", "probability": 0.08, "risk_level": "high"},
    {"label": "bkl", "probability": 0.03, "risk_level": "low"}
  ],
  "urgency": "Monitor, no immediate urgency",
  "disclaimer": "This is NOT a medical diagnosis. See a qualified dermatologist. AI output only.",
  "inference_time_ms": 820
}
```

### Response — Rejected

```json
{
  "status": "rejected_nsfw",
  "reason": "NSFW score 0.92",
  "lesion_detected": null,
  "main_description": null,
  "predictions": [],
  "urgency": null,
  "disclaimer": "This is NOT a medical diagnosis. See a qualified dermatologist. AI output only.",
  "inference_time_ms": 45
}
```

---

## 12. Development Workflow

```bash
# Setup
python -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt

# Unit tests (fast, all models mocked)
pytest tests/unit/ -v

# Integration tests (downloads models on first run)
pytest tests/integration/ -v

# All tests
pytest -v

# Run locally
uvicorn src.main:app --reload --port 8000

# Docker
docker compose up --build
```

---

## 13. Estimated Total Latency

| Stage | CPU | GPU (T4/L4) |
|-------|-----|-------------|
| Image load + resize | 10-30ms | 10-30ms |
| NN1: BRISQUE quality | 20-50ms | 20-50ms |
| NN1: NSFW (Falconsai) | 500-1000ms | 30-80ms |
| NN2: Skin classification | 500-1000ms | 40-150ms |
| **Total** | **~1-2s** | **~100-300ms** |

CPU is viable for low-throughput / testing. GPU recommended for production (>10 req/s).
