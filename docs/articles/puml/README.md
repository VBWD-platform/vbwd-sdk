# PlantUML Visualizations for Quantum LLM Research

This directory contains PlantUML diagrams visualizing the key concepts from the quantum LLM research papers and the input script.

## Diagram Overview

### 1. Uncertainty Principle (`01-uncertainty-principle.puml`)
**Visualizes:** ΔH × ΔS ≥ ℏ/2 relationship

**Key Elements:**
- Temperature parameter control
- Entropy (ΔH) vs Semantic Spread (ΔS) trade-off
- Comparison with Heisenberg uncertainty principle
- Low/high temperature behavior

**Supports:** Paper 1 - Main theoretical result

### 2. Wave Function Collapse (`02-wave-function-collapse.puml`)
**Visualizes:** Measurement-induced collapse in token generation

**Key Elements:**
- Superposition state before sampling
- Measurement event (Born rule)
- Collapsed state after selection
- Temperature as decoherence control
- State diagram showing irreversibility

**Supports:** Paper 2 - Section on Wave Function Collapse

### 3. Path Integrals (`03-path-integral.puml`)
**Visualizes:** Feynman path integral formulation of text generation

**Key Elements:**
- All possible generation paths
- Action calculation: S[path] = log P(path)
- Path amplitude summation
- Quantum interference (constructive/destructive)
- Classical beam search approximation
- Quantum advantage in parallel evaluation

**Supports:** Paper 2 - Section on Feynman Path Integrals

### 4. Entanglement and Attention (`04-entanglement-attention.puml`)
**Visualizes:** Quantum entanglement in attention mechanisms

**Key Elements:**
- Product states (no entanglement)
- Attention mechanism as entanglement generator
- Entangled states post-attention
- Bell inequality testing
- Entanglement measures (von Neumann entropy, concurrence)
- Quantum vs classical correlations

**Supports:** Paper 2 - Section on Entanglement

### 5. Quantum-Classical Mapping (`05-quantum-classical-mapping.puml`)
**Visualizes:** Complete correspondence between quantum mechanics, classical LLMs, and quantum hardware

**Key Elements:**
- Three-way comparison:
  - Quantum Mechanics (theory)
  - Classical LLMs (analogy)
  - Quantum Hardware (literal implementation)
- Mappings for each quantum concept
- Color-coded relationships (analogy vs literal)
- Quantum advantage summary

**Supports:** Both papers - Unified framework

### 6. Software Architecture (`06-software-architecture.puml`)
**Visualizes:** Python package structure and class relationships

**Key Elements:**
- Full package hierarchy
- Class diagrams with methods
- Dependencies between components
- Core modules:
  - metrics (uncertainty, entropy, spread)
  - simulations (quantum effects)
  - experiments (runners, comparators)
  - analysis (statistics)
  - visualization (plots)
  - reporting (HTML/PDF)

**Supports:** Implementation (Sprint planning)

### 7. Experiment Workflow (`07-experiment-workflow.puml`)
**Visualizes:** Complete experimental procedure

**Key Elements:**
- Setup and configuration
- Four main experiments (parallel execution)
- Analysis pipeline
- Report generation
- Data flow and artifacts
- Success/failure conditions

**Supports:** Implementation - Sprint 5 & 6

### 8. Quantum Circuit (`08-quantum-circuit.puml`)
**Visualizes:** Actual quantum circuit for token generation on quantum hardware

**Key Elements:**
- Qubit register layout
- Circuit stages:
  1. Initialization (Hadamard gates)
  2. Context encoding (amplitude encoding)
  3. Quantum attention (entangling gates)
  4. Feedforward (parametrized circuits)
  5. Measurement (Born rule)
- Classical-quantum comparison
- Hardware requirements

**Supports:** Paper 2 - Quantum Hardware Implementation section

## Viewing the Diagrams

### Online (Recommended)
Use PlantUML online editor:
1. Go to http://www.plantuml.com/plantuml/
2. Copy-paste diagram content
3. View rendered image

### VSCode
Install PlantUML extension:
```bash
code --install-extension jebbs.plantuml
```

Then use `Alt+D` to preview diagrams.

### Command Line
Install PlantUML:
```bash
# macOS
brew install plantuml

# Linux
sudo apt-get install plantuml
```

Render diagrams:
```bash
# Single diagram
plantuml 01-uncertainty-principle.puml

# All diagrams
plantuml *.puml

# Generate PNG
plantuml -tpng *.puml

# Generate SVG (vector, recommended for papers)
plantuml -tsvg *.puml
```

## Exporting for Publications

### High-Resolution PNG
```bash
plantuml -tpng -DPLANTUML_LIMIT_SIZE=16384 *.puml
```

### Vector SVG (Best for Papers)
```bash
plantuml -tsvg *.puml
```

### PDF (via SVG)
```bash
# Render to SVG first
plantuml -tsvg diagram.puml

# Convert SVG to PDF using Inkscape
inkscape diagram.svg --export-pdf=diagram.pdf
```

## Integration with Papers

### Paper 1: Uncertainty Principle Paper
**Primary Diagrams:**
- `01-uncertainty-principle.puml` - Main figure
- `05-quantum-classical-mapping.puml` - Conceptual framework
- `07-experiment-workflow.puml` - Validation methodology

**Suggested Placement:**
- Figure 1: Uncertainty principle trade-off
- Figure 2: Quantum-classical correspondence (uncertainty section)
- Appendix: Experimental validation workflow

### Paper 2: Quantum Effects Paper
**Primary Diagrams:**
- `02-wave-function-collapse.puml` - Section 6 figure
- `03-path-integral.puml` - Section 4 figure
- `04-entanglement-attention.puml` - Section 5 figure
- `05-quantum-classical-mapping.puml` - Section 8 (unification)
- `08-quantum-circuit.puml` - Section 7 (hardware implementation)

**Suggested Placement:**
- Figure 1: Quantum-classical mapping (introduction)
- Figure 2: Wave function collapse process
- Figure 3: Path integral summation
- Figure 4: Entanglement in attention
- Figure 5: Quantum circuit architecture
- Appendix: Software architecture

## Customization

All diagrams use PlantUML syntax and can be customized:

### Change Theme
```plantuml
!theme plain          ' Default
!theme blueprint      ' Blueprint style
!theme cerulean       ' Blue theme
!theme superhero      ' Dark theme
```

### Change Colors
```plantuml
skinparam backgroundColor #FFFEF0
skinparam rectangleBackgroundColor lightblue
skinparam rectangleBorderColor blue
```

### Adjust Layout
```plantuml
left to right direction  ' Horizontal layout
top to bottom direction  ' Vertical layout (default)
```

## Diagram Dependencies

```
Input Script (quantum-llm-talks-script.md)
    ↓
Conceptual Framework
    ↓
    ├── 01-uncertainty-principle.puml
    ├── 02-wave-function-collapse.puml
    ├── 03-path-integral.puml
    ├── 04-entanglement-attention.puml
    └── 05-quantum-classical-mapping.puml
    ↓
Implementation
    ↓
    ├── 06-software-architecture.puml
    ├── 07-experiment-workflow.puml
    └── 08-quantum-circuit.puml
    ↓
Research Papers + Code
```

## Related Files

- **Research Papers:** `../todo/scientific-article.md`, `../todo/quantum-effects-llms.md`
- **Input Script:** `../quantum-llm-talks-script.md`
- **Sprint Plans:** `../todo/sprints/*.md`
- **Implementation:** (Future) `quantum-llm-experiments/` package

## Generating All Figures Script

```bash
#!/bin/bash
# generate_all_figures.sh

echo "Generating PNG figures..."
plantuml -tpng *.puml

echo "Generating SVG figures..."
plantuml -tsvg *.puml

echo "Creating figures directory..."
mkdir -p ../figures

echo "Copying to figures directory..."
cp *.png ../figures/
cp *.svg ../figures/

echo "Done! Figures saved to ../figures/"
```

## License

BSL 1.1 (Business Source Licence) - Same as research papers

---

**Last Updated:** December 27, 2025
