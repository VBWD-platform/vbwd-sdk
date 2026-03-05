# Sprint LF-01: LensForge SDK Core + Dermatology Context Cluster

**Date**: 2026-02-25
**Product**: LensForge Microservice (LFMS)
**Deliverable**: Python Docker container with pluggable vision-analysis SDK
**First context cluster**: Dermatology / Skin Lesion Screening

---

## Product Concept

LensForge is a **customizable Python SDK** shipped as a Docker container.
The SDK provides the two-stage NN pipeline (NN1 safety filter + NN2 domain analysis).
The customer provides `/custom/` folder with `.env` config and optional model overrides.

```
lensforge/                      # The Docker image
├── lensforge/                  # SDK package (pip-installable)
│   ├── interfaces/             # Protocols — the contract
│   ├── pipeline/               # AnalysisPipeline orchestrator
│   ├── loaders/                # ImageLoader (base64, URL, bytes)
│   ├── schemas/                # Pydantic request/response
│   ├── models/                 # Built-in model implementations
│   │   ├── quality/            # BRISQUE, MUSIQ
│   │   ├── safety/             # Falconsai NSFW, NudeNet
│   │   └── classifiers/        # ViT skin, (future: plant, pet, art)
│   ├── container.py            # DI wiring
│   └── app.py                  # FastAPI factory
│
├── custom/                     # CUSTOMER-PROVIDED (mounted or baked in)
│   ├── .env                    # API keys, model selection, thresholds
│   └── models/                 # Optional: custom fine-tuned weights
│
├── tests/
├── Dockerfile
├── Makefile
└── pyproject.toml
```

**Key idea**: `lensforge/` = SDK (we ship). `custom/` = configuration (customer provides).
Swap `.env` variables → different context cluster. No code changes.

---

## Core Requirements (apply to every step)

| Req | Rule |
|-----|------|
| **TDD** | Write test first, then implementation. Every step starts with a failing test. |
| **SOLID/SRP** | One class = one responsibility. No god objects. |
| **OCP** | New model = new class. Zero changes to existing code. |
| **LSP** | Every implementation of a protocol is fully interchangeable. `BrisqueChecker` and `MusiqChecker` both return `QualityResult` with identical semantics. |
| **ISP** | Small focused protocols: `IQualityChecker`, `INsfwDetector`, `IDomainClassifier`. Not one fat interface. |
| **DIP** | `AnalysisPipeline` depends on protocols, never on concrete classes. Wired via DI container. |
| **DRY** | Image loading in one place. Threshold logic in config only. Shared dataclasses for results. |
| **Clean code** | Meaningful names. No comments that restate the code. Type hints everywhere. |
| **No overengineering** | No ORM, no database, no message queue, no caching, no auth. Stateless in/out. |
| **Drop deprecated** | No `typing.Optional` (use `X \| None`). No `@validator` (use `@field_validator`). No `pkg_resources`. Python 3.12 syntax. |

---

## Sprint Steps

### Step 1: Project Scaffold + Makefile + Docker

**Goal**: Empty project that builds, runs, and passes `make lint`.

**Test first**:
```python
# tests/test_health.py
from httpx import AsyncClient
import pytest

@pytest.mark.asyncio
async def test_health_endpoint(client: AsyncClient):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json()["status"] == "ok"
```

**Deliverables**:
- `pyproject.toml` with all deps (fastapi, uvicorn, pydantic, pydantic-settings, dependency-injector, Pillow, numpy, opencv-contrib-python-headless, transformers, torch)
- `requirements-dev.txt` (pytest, pytest-mock, pytest-asyncio, httpx, ruff, mypy)
- `Makefile`:
  ```makefile
  .PHONY: test test-unit test-integration lint type-check run build

  test:
      pytest tests/ -v

  test-unit:
      pytest tests/unit/ -v

  test-integration:
      pytest tests/integration/ -v --timeout=60

  lint:
      ruff check lensforge/ tests/
      ruff format --check lensforge/ tests/

  type-check:
      mypy lensforge/ --strict

  run:
      uvicorn lensforge.app:create_app --factory --reload --port 8000

  build:
      docker build -t lensforge .

  pre-commit:
      make lint && make type-check && make test-unit
  ```
- `Dockerfile` (python:3.12-slim, OpenCV system deps, copy lensforge/ + custom/)
- `docker-compose.yaml` (mount `custom/` as volume, model-cache volume)
- `lensforge/app.py` with `create_app()` factory returning FastAPI instance
- `/health` endpoint
- `custom/.env.example`
- `tests/conftest.py` with `AsyncClient` fixture

**Files to create**:
- `pyproject.toml`
- `requirements-dev.txt`
- `Makefile`
- `Dockerfile`
- `docker-compose.yaml`
- `lensforge/__init__.py`
- `lensforge/app.py`
- `lensforge/config.py`
- `custom/.env.example`
- `tests/__init__.py`
- `tests/conftest.py`
- `tests/test_health.py`

---

### Step 2: Pydantic Schemas (Request + Response)

**Goal**: Strict typed contracts for API input/output. JSON in, JSON out.

**Test first**:
```python
# tests/unit/test_schemas.py
from lensforge.schemas.request import AnalyzeRequest
from lensforge.schemas.response import AnalyzeResponse, PredictionSchema
import pytest

def test_request_requires_at_least_one_source():
    with pytest.raises(ValueError):
        AnalyzeRequest()  # neither base64 nor url

def test_request_accepts_base64():
    req = AnalyzeRequest(image_base64="abc123")
    assert req.image_base64 == "abc123"

def test_request_accepts_url():
    req = AnalyzeRequest(image_url="https://example.com/img.jpg")
    assert req.image_url is not None

def test_response_success():
    resp = AnalyzeResponse(
        status="success",
        lesion_detected=True,
        predictions=[PredictionSchema(label="nv", probability=0.87, risk_level="low")],
        disclaimer="AI only",
    )
    assert resp.status == "success"
    assert len(resp.predictions) == 1

def test_response_rejection():
    resp = AnalyzeResponse(
        status="rejected_nsfw",
        reason="NSFW score 0.92",
        disclaimer="AI only",
    )
    assert resp.lesion_detected is None
    assert resp.predictions == []
```

**Deliverables**:
- `lensforge/schemas/__init__.py`
- `lensforge/schemas/request.py` — `AnalyzeRequest` (image_base64 | image_url, model validator ensures at least one), `BatchAnalyzeRequest`
- `lensforge/schemas/response.py` — `PredictionSchema`, `AnalyzeResponse`

**AnalyzeRequest**:
```python
class AnalyzeRequest(BaseModel):
    image_base64: str | None = None
    image_url: str | None = None

    @model_validator(mode="after")
    def check_at_least_one(self) -> "AnalyzeRequest":
        if not self.image_base64 and not self.image_url:
            raise ValueError("Provide image_base64 or image_url")
        return self
```

**AnalyzeResponse**:
```python
class AnalyzeResponse(BaseModel):
    status: str                          # success | rejected_quality | rejected_nsfw | error
    reason: str | None = None
    lesion_detected: bool | None = None
    main_description: str | None = None
    predictions: list[PredictionSchema] = []
    urgency: str | None = None
    disclaimer: str
    inference_time_ms: int = 0
    model_versions: dict[str, str] = {}
```

---

### Step 3: Interfaces (Protocols)

**Goal**: Define the three contracts. No implementations yet.

**Test first**:
```python
# tests/unit/test_interfaces.py
from lensforge.interfaces.quality_checker import IQualityChecker, QualityResult
from lensforge.interfaces.nsfw_detector import INsfwDetector, NsfwResult
from lensforge.interfaces.domain_classifier import IDomainClassifier, ClassificationResult, Prediction

def test_quality_result_dataclass():
    r = QualityResult(score=0.8, is_acceptable=True)
    assert r.is_acceptable is True
    assert r.reason is None

def test_nsfw_result_dataclass():
    r = NsfwResult(is_safe=False, nsfw_score=0.95, reason="Explicit content")
    assert r.is_safe is False

def test_classification_result_dataclass():
    r = ClassificationResult(
        detected=True,
        predictions=[Prediction(label="nv", probability=0.87, risk_level="low")],
        description="Mole detected",
        urgency="No urgency",
    )
    assert len(r.predictions) == 1
```

**Deliverables**:
- `lensforge/interfaces/__init__.py`
- `lensforge/interfaces/quality_checker.py` — `QualityResult` dataclass + `IQualityChecker` protocol with `check(image: Image.Image) -> QualityResult`
- `lensforge/interfaces/nsfw_detector.py` — `NsfwResult` dataclass + `INsfwDetector` protocol with `detect(image: Image.Image) -> NsfwResult`
- `lensforge/interfaces/domain_classifier.py` — `Prediction` dataclass, `ClassificationResult` dataclass, `IDomainClassifier` protocol with `classify(image: Image.Image) -> ClassificationResult`

**Note**: Named `IDomainClassifier` not `ISkinClassifier` — this is the generic SDK interface. Skin, plant, pet, art classifiers all implement this same protocol. LSP: any `IDomainClassifier` is interchangeable.

---

### Step 4: ImageLoader Service

**Goal**: Load image from base64 or URL. Validate format. Resize to max 1024x1024 preserving aspect ratio.

**Test first**:
```python
# tests/unit/test_image_loader.py
import base64
from io import BytesIO
from PIL import Image
from lensforge.loaders.image_loader import ImageLoader

def test_load_from_base64():
    img = Image.new("RGB", (100, 100), color="red")
    buf = BytesIO()
    img.save(buf, format="JPEG")
    b64 = base64.b64encode(buf.getvalue()).decode()

    loader = ImageLoader(max_size=1024)
    result = loader.load_base64(b64)
    assert result.size == (100, 100)

def test_resize_large_image():
    img = Image.new("RGB", (2048, 1536), color="blue")
    buf = BytesIO()
    img.save(buf, format="PNG")
    b64 = base64.b64encode(buf.getvalue()).decode()

    loader = ImageLoader(max_size=1024)
    result = loader.load_base64(b64)
    assert max(result.size) <= 1024
    # Aspect ratio preserved
    assert abs(result.size[0] / result.size[1] - 2048 / 1536) < 0.01

def test_rejects_invalid_format():
    loader = ImageLoader(max_size=1024)
    with pytest.raises(ValueError, match="Unsupported image format"):
        loader.load_base64(base64.b64encode(b"not an image").decode())

def test_rejects_non_rgb():
    """GIF etc. must be converted to RGB."""
    img = Image.new("L", (100, 100))  # grayscale
    buf = BytesIO()
    img.save(buf, format="PNG")
    b64 = base64.b64encode(buf.getvalue()).decode()

    loader = ImageLoader(max_size=1024)
    result = loader.load_base64(b64)
    assert result.mode == "RGB"
```

**Deliverables**:
- `lensforge/loaders/__init__.py`
- `lensforge/loaders/image_loader.py` — `ImageLoader` class:
  - `load_base64(data: str) -> Image.Image`
  - `load_url(url: str) -> Image.Image`
  - Internal: validate format (JPEG, PNG, WEBP), resize, convert to RGB
  - Accepts `max_size: int` in constructor (from config)

---

### Step 5: AnalysisPipeline (Orchestrator)

**Goal**: The core service. Runs NN1 → NN2 sequentially. Returns early on rejection. Depends only on protocols.

**Test first**:
```python
# tests/unit/test_pipeline.py
from PIL import Image
from lensforge.pipeline.analysis_pipeline import AnalysisPipeline

def test_rejects_low_quality(mock_quality_bad, mock_nsfw_safe, mock_classifier):
    pipe = AnalysisPipeline(mock_quality_bad, mock_nsfw_safe, mock_classifier)
    result = pipe.analyze(Image.new("RGB", (224, 224)))

    assert result.status == "rejected_quality"
    mock_nsfw_safe.detect.assert_not_called()
    mock_classifier.classify.assert_not_called()

def test_rejects_nsfw(mock_quality_ok, mock_nsfw_unsafe, mock_classifier):
    pipe = AnalysisPipeline(mock_quality_ok, mock_nsfw_unsafe, mock_classifier)
    result = pipe.analyze(Image.new("RGB", (224, 224)))

    assert result.status == "rejected_nsfw"
    mock_classifier.classify.assert_not_called()

def test_success_full_pipeline(mock_quality_ok, mock_nsfw_safe, mock_classifier):
    pipe = AnalysisPipeline(mock_quality_ok, mock_nsfw_safe, mock_classifier)
    result = pipe.analyze(Image.new("RGB", (224, 224)))

    assert result.status == "success"
    assert result.lesion_detected is True
    assert len(result.predictions) > 0
    assert result.disclaimer != ""
    assert result.inference_time_ms >= 0

def test_pipeline_includes_model_versions(mock_quality_ok, mock_nsfw_safe, mock_classifier):
    pipe = AnalysisPipeline(mock_quality_ok, mock_nsfw_safe, mock_classifier)
    result = pipe.analyze(Image.new("RGB", (224, 224)))
    assert "nn1_quality" in result.model_versions
    assert "nn1_safety" in result.model_versions
    assert "nn2" in result.model_versions
```

**Deliverables**:
- `lensforge/pipeline/__init__.py`
- `lensforge/pipeline/analysis_pipeline.py` — `AnalysisPipeline` class
  - Constructor: `__init__(quality: IQualityChecker, safety: INsfwDetector, classifier: IDomainClassifier)`
  - Method: `analyze(image: Image.Image) -> AnalyzeResponse`
  - Sequential: quality → safety → classify
  - Early return on rejection
  - Measures `inference_time_ms`
  - Includes `model_versions` from each component
  - Static `DISCLAIMER` string

**Mock fixtures in conftest.py** (shared across all tests):
```python
@pytest.fixture
def mock_quality_ok(mocker):
    m = mocker.MagicMock()
    m.check.return_value = QualityResult(score=0.9, is_acceptable=True)
    m.version = "mock-quality-1.0"
    return m

@pytest.fixture
def mock_quality_bad(mocker):
    m = mocker.MagicMock()
    m.check.return_value = QualityResult(score=0.1, is_acceptable=False, reason="Too blurry")
    m.version = "mock-quality-1.0"
    return m

@pytest.fixture
def mock_nsfw_safe(mocker):
    m = mocker.MagicMock()
    m.detect.return_value = NsfwResult(is_safe=True, nsfw_score=0.05)
    m.version = "mock-nsfw-1.0"
    return m

@pytest.fixture
def mock_nsfw_unsafe(mocker):
    m = mocker.MagicMock()
    m.detect.return_value = NsfwResult(is_safe=False, nsfw_score=0.92, reason="NSFW content")
    m.version = "mock-nsfw-1.0"
    return m

@pytest.fixture
def mock_classifier(mocker):
    m = mocker.MagicMock()
    m.classify.return_value = ClassificationResult(
        detected=True,
        predictions=[Prediction(label="nv", probability=0.87, risk_level="low")],
        description="Mole detected",
        urgency="No urgency",
    )
    m.version = "mock-skin-1.0"
    return m
```

---

### Step 6: Built-in Model — BRISQUE Quality Checker (NN1)

**Goal**: First concrete `IQualityChecker` implementation. OpenCV BRISQUE + Laplacian blur detection. CPU only, zero model download.

**Test first**:
```python
# tests/unit/test_brisque_checker.py
from PIL import Image, ImageFilter
from lensforge.models.quality.brisque_checker import BrisqueChecker

def test_accepts_sharp_image():
    # Create a sharp image with edges
    img = Image.new("RGB", (224, 224), color=(180, 130, 100))
    # Draw some structure so Laplacian detects edges
    from PIL import ImageDraw
    draw = ImageDraw.Draw(img)
    for i in range(0, 224, 10):
        draw.line([(i, 0), (i, 224)], fill="black", width=2)

    checker = BrisqueChecker(blur_threshold=50.0)
    result = checker.check(img)
    assert result.is_acceptable is True

def test_rejects_blurry_image():
    img = Image.new("RGB", (224, 224), color=(180, 130, 100))
    blurred = img.filter(ImageFilter.GaussianBlur(radius=20))

    checker = BrisqueChecker(blur_threshold=50.0)
    result = checker.check(blurred)
    assert result.is_acceptable is False
    assert "blurry" in result.reason.lower()

def test_checker_has_version():
    checker = BrisqueChecker()
    assert checker.version == "brisque-laplacian-1.0"
```

**Deliverables**:
- `lensforge/models/__init__.py`
- `lensforge/models/quality/__init__.py`
- `lensforge/models/quality/brisque_checker.py` — `BrisqueChecker(blur_threshold: float = 100.0)`
  - Implements `IQualityChecker`
  - Uses `cv2.Laplacian` variance for blur detection
  - `version` property for model_versions tracking
  - Constructor takes `blur_threshold` from config

---

### Step 7: Built-in Model — Falconsai NSFW Detector (NN1)

**Goal**: Concrete `INsfwDetector`. Uses `Falconsai/nsfw_image_detection` from HuggingFace. Apache 2.0, public, no token.

**Test first** (unit — mocked transformer pipeline):
```python
# tests/unit/test_falconsai_nsfw.py
from unittest.mock import MagicMock, patch
from PIL import Image

def test_safe_image():
    with patch("lensforge.models.safety.falconsai_nsfw.pipeline_factory") as mock_pf:
        mock_pipe = MagicMock()
        mock_pipe.return_value = [
            {"label": "normal", "score": 0.97},
            {"label": "nsfw", "score": 0.03},
        ]
        mock_pf.return_value = mock_pipe

        from lensforge.models.safety.falconsai_nsfw import FalconsaiNsfwDetector
        detector = FalconsaiNsfwDetector(threshold=0.7, _pipeline=mock_pipe)
        result = detector.detect(Image.new("RGB", (224, 224)))

        assert result.is_safe is True
        assert result.nsfw_score < 0.7

def test_nsfw_image():
    with patch("lensforge.models.safety.falconsai_nsfw.pipeline_factory") as mock_pf:
        mock_pipe = MagicMock()
        mock_pipe.return_value = [
            {"label": "nsfw", "score": 0.92},
            {"label": "normal", "score": 0.08},
        ]
        mock_pf.return_value = mock_pipe

        from lensforge.models.safety.falconsai_nsfw import FalconsaiNsfwDetector
        detector = FalconsaiNsfwDetector(threshold=0.7, _pipeline=mock_pipe)
        result = detector.detect(Image.new("RGB", (224, 224)))

        assert result.is_safe is False
        assert result.nsfw_score >= 0.7

def test_detector_has_version():
    detector = FalconsaiNsfwDetector.__new__(FalconsaiNsfwDetector)
    detector._threshold = 0.7
    assert "falconsai" in detector.version
```

**Deliverables**:
- `lensforge/models/safety/__init__.py`
- `lensforge/models/safety/falconsai_nsfw.py` — `FalconsaiNsfwDetector(threshold: float, _pipeline=None)`
  - Implements `INsfwDetector`
  - Lazy-loads `transformers.pipeline("image-classification", model="Falconsai/nsfw_image_detection")`
  - Accepts `_pipeline` injection for testing (no mock patching needed)
  - `version` property

**Model access**: Public. `pip install transformers`. No HuggingFace token needed.

---

### Step 8: Built-in Model — ViT Skin Classifier (NN2, Dermatology Context Cluster)

**Goal**: First concrete `IDomainClassifier`. ViT fine-tuned on HAM10000. This is the dermatology context cluster.

**Test first** (unit — mocked):
```python
# tests/unit/test_vit_skin.py
from unittest.mock import MagicMock
from PIL import Image

def test_classifies_image():
    mock_pipe = MagicMock()
    mock_pipe.return_value = [
        {"label": "nv", "score": 0.85},
        {"label": "mel", "score": 0.10},
        {"label": "bkl", "score": 0.03},
    ]

    from lensforge.models.classifiers.vit_skin import VitSkinClassifier
    classifier = VitSkinClassifier(_pipeline=mock_pipe)
    result = classifier.classify(Image.new("RGB", (224, 224)))

    assert result.detected is True
    assert result.predictions[0].label == "nv"
    assert result.predictions[0].risk_level == "low"

def test_melanoma_is_high_risk():
    mock_pipe = MagicMock()
    mock_pipe.return_value = [
        {"label": "mel", "score": 0.78},
        {"label": "nv", "score": 0.15},
    ]

    from lensforge.models.classifiers.vit_skin import VitSkinClassifier
    classifier = VitSkinClassifier(_pipeline=mock_pipe)
    result = classifier.classify(Image.new("RGB", (224, 224)))

    assert result.predictions[0].risk_level == "high"
    assert "days" in result.urgency.lower()

def test_classifier_has_version():
    classifier = VitSkinClassifier.__new__(VitSkinClassifier)
    assert "vit-skin" in classifier.version or "skin" in classifier.version
```

**Deliverables**:
- `lensforge/models/classifiers/__init__.py`
- `lensforge/models/classifiers/vit_skin.py` — `VitSkinClassifier(model_name: str, device: str, _pipeline=None)`
  - Implements `IDomainClassifier`
  - Default model: `Anwarkh1/Skin_Cancer-Image_Classification`
  - `RISK_MAP` and `URGENCY_MAP` dicts for HAM10000 classes
  - `version` property
  - `_pipeline` injection for unit tests

**Model access**: Public HuggingFace. No token needed.

**HAM10000 classes**: akiec (moderate), bcc (high), bkl (low), df (low), mel (high), nv (low), vasc (low).

---

### Step 9: DI Container + Config

**Goal**: Wire everything together via `dependency-injector`. Config reads from `custom/.env`.

**Test first**:
```python
# tests/unit/test_container.py
from lensforge.container import Container
from lensforge.pipeline.analysis_pipeline import AnalysisPipeline

def test_container_creates_pipeline():
    container = Container()
    container.config.from_dict({
        "device": "cpu",
        "quality_backend": "brisque",
        "quality_blur_threshold": 100.0,
        "nsfw_backend": "falconsai",
        "nsfw_threshold": 0.7,
        "classifier_backend": "vit_skin",
        "classifier_model_name": "Anwarkh1/Skin_Cancer-Image_Classification",
    })

    pipeline = container.analysis_pipeline()
    assert isinstance(pipeline, AnalysisPipeline)

def test_config_from_env(tmp_path, monkeypatch):
    env_file = tmp_path / ".env"
    env_file.write_text("DEVICE=cpu\nNSFW_THRESHOLD=0.8\n")

    from lensforge.config import Settings
    monkeypatch.setenv("DEVICE", "cpu")
    monkeypatch.setenv("NSFW_THRESHOLD", "0.8")

    settings = Settings()
    assert settings.device == "cpu"
    assert settings.nsfw_threshold == 0.8
```

**Deliverables**:
- `lensforge/config.py` — `Settings(BaseSettings)` reads from env:
  ```python
  class Settings(BaseSettings):
      device: str = "cpu"
      quality_backend: str = "brisque"
      quality_blur_threshold: float = 100.0
      nsfw_backend: str = "falconsai"
      nsfw_threshold: float = 0.7
      classifier_backend: str = "vit_skin"
      classifier_model_name: str = "Anwarkh1/Skin_Cancer-Image_Classification"
      host: str = "0.0.0.0"
      port: int = 8000
      hf_token: str | None = None

      model_config = SettingsConfigDict(env_file="custom/.env", extra="ignore")
  ```
- `lensforge/container.py` — `Container` wires:
  - `quality_checker` → selects by `config.quality_backend`
  - `nsfw_detector` → selects by `config.nsfw_backend`
  - `domain_classifier` → selects by `config.classifier_backend`
  - `analysis_pipeline` → factory with all three injected
  - `image_loader` → singleton with `config.max_image_size`

---

### Step 10: Route — POST /analyze

**Goal**: Full HTTP endpoint. JSON in, JSON out.

**Test first**:
```python
# tests/integration/test_analyze_endpoint.py
import base64
from io import BytesIO
from PIL import Image
import pytest
from httpx import AsyncClient

@pytest.mark.asyncio
async def test_analyze_base64(client: AsyncClient):
    img = Image.new("RGB", (224, 224), color=(180, 130, 100))
    buf = BytesIO()
    img.save(buf, format="JPEG")
    b64 = base64.b64encode(buf.getvalue()).decode()

    resp = await client.post("/analyze", json={"image_base64": b64})
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] in ("success", "rejected_quality", "rejected_nsfw")
    assert "disclaimer" in data

@pytest.mark.asyncio
async def test_analyze_no_image(client: AsyncClient):
    resp = await client.post("/analyze", json={})
    assert resp.status_code == 422  # validation error

@pytest.mark.asyncio
async def test_analyze_invalid_base64(client: AsyncClient):
    resp = await client.post("/analyze", json={"image_base64": "not-valid"})
    assert resp.status_code == 400
```

**Deliverables**:
- `lensforge/routes/__init__.py`
- `lensforge/routes/analyze.py` — `POST /analyze` route
  - Accepts `AnalyzeRequest` JSON body
  - Uses `ImageLoader` to decode
  - Calls `AnalysisPipeline.analyze()`
  - Returns `AnalyzeResponse` JSON
  - Error handling: 400 for invalid image, 422 for schema validation
- Update `lensforge/app.py` — register route, wire container on startup

---

### Step 11: Route — POST /batch-analyze

**Goal**: Process multiple images in one request.

**Test first**:
```python
# tests/integration/test_batch_endpoint.py
import base64
from io import BytesIO
from PIL import Image
import pytest
from httpx import AsyncClient

@pytest.mark.asyncio
async def test_batch_analyze(client: AsyncClient):
    img = Image.new("RGB", (100, 100), color="red")
    buf = BytesIO()
    img.save(buf, format="JPEG")
    b64 = base64.b64encode(buf.getvalue()).decode()

    resp = await client.post("/batch-analyze", json={
        "images": [
            {"image_base64": b64},
            {"image_base64": b64},
        ]
    })
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["results"]) == 2

@pytest.mark.asyncio
async def test_batch_max_50(client: AsyncClient):
    resp = await client.post("/batch-analyze", json={
        "images": [{"image_base64": "x"}] * 51
    })
    assert resp.status_code == 422
```

**Deliverables**:
- Add `POST /batch-analyze` to `lensforge/routes/analyze.py`
  - Accepts `BatchAnalyzeRequest` (max 50 images)
  - Processes sequentially (no async model inference — torch is sync)
  - Returns `{"results": [AnalyzeResponse, ...]}`
  - Each image is independent — one failure doesn't block others

---

### Step 12: custom/.env Configuration for Dermatology Cluster

**Goal**: Ship the first ready-to-use context cluster config.

**Deliverables**:
- `custom/.env.example`:
  ```bash
  # === LensForge Configuration ===
  # Context cluster: Dermatology / Skin Lesion Screening

  # Device: "cpu" for development, "cuda" for production GPU
  DEVICE=cpu

  # NN1: Image quality checker
  QUALITY_BACKEND=brisque
  QUALITY_BLUR_THRESHOLD=100

  # NN1: NSFW / safety filter
  NSFW_BACKEND=falconsai
  NSFW_THRESHOLD=0.7

  # NN2: Domain classifier (the "context cluster")
  CLASSIFIER_BACKEND=vit_skin
  CLASSIFIER_MODEL_NAME=Anwarkh1/Skin_Cancer-Image_Classification

  # Server
  HOST=0.0.0.0
  PORT=8000

  # Optional: HuggingFace token (only for gated models like MedGemma)
  # HF_TOKEN=hf_xxx
  ```
- `custom/.env` — copy of example (gitignored)
- `.gitignore` entry for `custom/.env`

---

### Step 13: Integration Test — Full Pipeline with Real CPU Models

**Goal**: End-to-end test that loads real models on CPU. Slow, skipped in fast CI.

**Test first** (this IS the test):
```python
# tests/integration/test_full_pipeline.py
import os
import base64
from io import BytesIO
from PIL import Image
import pytest

skip_in_ci = pytest.mark.skipif(
    os.getenv("CI_FAST") == "true",
    reason="Skips model download in fast CI"
)

@skip_in_ci
def test_full_dermatology_pipeline():
    """Loads real models on CPU. ~10-15s first run (downloads)."""
    from lensforge.models.quality.brisque_checker import BrisqueChecker
    from lensforge.models.safety.falconsai_nsfw import FalconsaiNsfwDetector
    from lensforge.models.classifiers.vit_skin import VitSkinClassifier
    from lensforge.pipeline.analysis_pipeline import AnalysisPipeline

    pipeline = AnalysisPipeline(
        quality=BrisqueChecker(blur_threshold=50.0),
        safety=FalconsaiNsfwDetector(threshold=0.7),
        classifier=VitSkinClassifier(device="cpu"),
    )

    # Create a test image with some structure (not pure solid color)
    img = Image.new("RGB", (224, 224), color=(180, 130, 100))
    from PIL import ImageDraw
    draw = ImageDraw.Draw(img)
    for i in range(0, 224, 8):
        draw.line([(i, 0), (i, 224)], fill=(150, 100, 80), width=2)

    result = pipeline.analyze(img)

    assert result.status in ("success", "rejected_quality")
    assert result.disclaimer != ""
    assert result.inference_time_ms > 0
    if result.status == "success":
        assert len(result.predictions) > 0
```

**Deliverables**:
- `tests/integration/test_full_pipeline.py`
- `tests/fixtures/` — add small test images (224x224 JPEG)
- Makefile target: `make test-integration`

---

### Step 14: Docker Build + Smoke Test

**Goal**: Container builds, starts, and responds to `/analyze`.

**Test** (shell script or CI step):
```bash
# tests/smoke_test.sh
#!/bin/bash
set -e

echo "Building container..."
docker compose build

echo "Starting container..."
docker compose up -d
sleep 10  # wait for model loading

echo "Testing /health..."
curl -sf http://localhost:8000/health | jq .

echo "Testing /analyze..."
IMG_B64=$(python3 -c "
import base64
from io import BytesIO
from PIL import Image
img = Image.new('RGB', (224, 224), color=(180, 130, 100))
buf = BytesIO()
img.save(buf, format='JPEG')
print(base64.b64encode(buf.getvalue()).decode())
")

curl -sf -X POST http://localhost:8000/analyze \
  -H "Content-Type: application/json" \
  -d "{\"image_base64\": \"$IMG_B64\"}" | jq .

echo "Cleaning up..."
docker compose down

echo "Smoke test passed!"
```

**Deliverables**:
- `tests/smoke_test.sh`
- Verify Dockerfile builds cleanly
- Verify container starts and `/health` + `/analyze` respond correctly
- Update Makefile: `make smoke-test`

---

## API Keys & Model Access Summary

| What | Where to Get | Cost | Required For |
|------|-------------|------|-------------|
| HuggingFace token | https://huggingface.co/settings/tokens | Free | Gated models only (MedGemma). NOT needed for Falconsai, Anwarkh1 |
| Falconsai NSFW model | Auto-downloaded by `transformers` | Free | NN1 safety filter |
| Anwarkh1 skin model | Auto-downloaded by `transformers` | Free | NN2 dermatology |
| OpenCV BRISQUE | Bundled with `opencv-contrib-python` | Free | NN1 quality |
| ISIC dataset | https://www.isic-archive.com/ | Free (registration) | Custom model training only |
| Modal (production GPU) | https://modal.com — `pip install modal && modal token new` | $30/mo free | Serverless GPU deployment |
| RunPod (production GPU) | https://runpod.io | Pay-per-use | Alternative GPU deployment |

**For testing**: All models used in this sprint are free, public, and run on CPU. No API keys required for `make test`.

---

## Free Models for Testing (CI/CD)

| Component | Test Model | Size | CPU Time | Token Needed |
|-----------|-----------|------|----------|-------------|
| NN1 Quality | OpenCV BRISQUE (built-in) | 0 MB | <50ms | No |
| NN1 NSFW | Falconsai/nsfw_image_detection | ~350 MB | ~0.5-1s | No |
| NN2 Skin | Anwarkh1/Skin_Cancer-Image_Classification | ~350 MB | ~0.5-1s | No |
| **Unit tests** | All mocked (MagicMock) | 0 MB | <1s total | No |

---

## Sprint Acceptance Criteria

- [ ] `make lint` passes (ruff check + format)
- [ ] `make type-check` passes (mypy --strict)
- [ ] `make test-unit` passes — all unit tests green, <5s total
- [ ] `make test-integration` passes — real CPU models, <30s
- [ ] `make smoke-test` passes — Docker container builds and responds
- [ ] `POST /analyze` with base64 image returns valid `AnalyzeResponse` JSON
- [ ] `POST /batch-analyze` with 2+ images returns list of results
- [ ] Swapping `custom/.env` values changes model selection without code changes
- [ ] All model components are behind protocols — no direct imports in pipeline
- [ ] Zero hardcoded thresholds — everything from config
