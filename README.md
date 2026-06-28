<!-- PROJECT LOGO -->
<br />
<div align="center">
  <picture>
    <img alt="Random Knights, XYZ — day/night themed header." src="https://github.com/random-knights/.github/raw/main/assets/ruok-earth.png">
  </picture>
<h3 align="center" style="color:#ff4124">Random Knights, XYZ</h3>
  <p align="center">
    rand0m.ai & randomly.engineering
    <br />
    <a href="https://github.com/random-knights/.github/blob/main/READMORE"><strong>Explore the docs »</strong></a>
    <br />
    <br />
    <a href="https://github.com/random-knights/xyz">View Demo</a>
    ·
    <a href="https://github.com/random-knights/123/issues">Report Bug</a>
    ·
    <a href="https://github.com/random-knights/123/issues">Request Feature</a>
  </p>
</div>

# xyz-earth

> Earth intelligence layer for [rand0m.ai](https://rand0m.ai)

Research, governance, and data for the living globe — how real environmental signals become animated, scored, and browsable planetary-health layers.

<div align="center">

[![rand0m earth2d — 2D wind globe preview](preview/earth2d-wind-globe.svg)](preview/earth2d-wind-globe.html)

<sub><b>2D globe (<code>earth2d</code>) — wind layer.</b> Static preview · <a href="preview/earth2d-wind-globe.html"><b>open the interactive mock »</b></a> (drag to rotate). Illustrative wind field — not live data.</sub>

</div>

---

## The living globe

rand0m shows Earth's health in real time. Wind flows over continents, sea-surface temperatures shift from the 1991–2020 baseline, wildfire hotspots pulse in 24-hour windows. Everything you see is:

- **Sourced** from open scientific datasets (NOAA, NASA, CAMS, GLAD, and more)
- **Aggregated** — no individual tracking, ever
- **Governed** — a named spec and community review before any layer enters the catalog

This repository is the public home for research, data-sourcing questions, methodology discussion, and layer requests.

---

## Earth Health Score — v0.6

The globe surfaces a **Planet Health Score** — a single number per region and globally that blends nine Earth-system domains. It is an estimate, not a certified assessment. Every signal carries a confidence label.

### Nine domains

| Domain | What it measures | Primary source |
| --- | --- | --- |
| **Land** | Tree-cover health, forest loss rate | GLAD Hansen / VCF5KYR |
| **Fire** | Active hotspot burden, 24 h window | NASA FIRMS |
| **Atmosphere** | Air-quality burden, AQI-weighted | CAMS |
| **Ocean temperature** | SST anomaly vs 1991–2020 WMO baseline | NOAA OISST / Open-Meteo Marine |
| **Ocean acidification** | pH trend stress signal | _(open for proposals — see Discussions)_ |
| **Cryosphere** | Sea-ice extent and anomaly | _(expanding — see Discussions)_ |
| **Biodiversity** | Species pressure and habitat integrity proxy | GBIF _(direct signal preferred — see Discussions)_ |
| **Conservation** | Protected-area coverage signal | IUCN / WDPA |
| **Anthroposphere** | Human-pressure index (gHM-grounded; ratified v0.6) | Global Human Modification index |

### Planetary-boundaries grounding

Domains are anchored against **planetary boundary thresholds** (Rockström et al.) — the limits beyond which Earth systems risk crossing into qualitatively different states. Signals within a domain are averaged; each domain contributes once to the global score. Normalizers are locked at ratification (anchored), not floating with observed data ranges.

### Anthroposphere — what changed in v0.6

The human-pressure domain is now grounded on the **Global Human Modification (gHM)** index — a peer-reviewed geospatial synthesis of infrastructure, agriculture, and urban footprint — replacing the provisional representative grid used in earlier versions.

---

## How a layer is born

```
Public scientific source (open license)
  → scheduled fetch / refresh job
  → governed, aggregated, identity-free data object
  → globe layer or score domain
```

No individual tracking, callsigns, vessel names, or precise sensitive locations enter the pipeline at any stage. Identity suppression is a named, independently testable function — not a display-time filter.

---

## Join the research

[**Discussions →**](../../discussions)

- 🌍 **How we score Earth's health** — v0.6 methodology, 9 domains, planetary-boundaries grounding
- 📡 **What data we need** — layer requests, source candidates, license questions
- 🌱 **AIEDS v1** — the open AI Energy Disclosure Standard powering the AI footprint chip

---

## License

Methodology and governance text: **CC BY 4.0**  
Code (where present): see file headers  
Source data: each layer carries the license of its upstream scientific provider
