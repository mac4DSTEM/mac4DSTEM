# direction_check.py app — the app's stride-3 map (known-variants baseline and guarded)

Python objects on the dumped labels, to compare line by line with the probe's own --object-table (count, median = sorted[n // 2], area fraction):

| class | source | objects | median len (px) | area frac |
|---|---|---|---|---|
| θ′ edge-on | truth | 74 | 1.00 | 0.0143 |
| θ′ edge-on | baseline | 101 | 1.00 | 0.0219 |
| θ′ edge-on | guarded | 85 | 2.00 | 0.0181 |
| θ′ face-on | truth | 3 | 22.23 | 0.0332 |
| θ′ face-on | baseline | 70 | 1.00 | 0.0372 |
| θ′ face-on | guarded | 54 | 1.00 | 0.0365 |
| T1 | truth | 37 | 23.14 | 0.2174 |
| T1 | baseline | 62 | 8.61 | 0.2183 |
| T1 | guarded | 48 | 13.37 | 0.2175 |

Per-position error of each variant (count(label != truth) / 29241):

- app baseline: 1.81 %
- app baseline · P/9: 1.57 %
- app baseline · H/9: 1.62 %
- app guarded: 1.45 %
- app guarded · P/9: 1.31 %
- app guarded · H/9: 1.38 %

## The app's map at stride 3, raw and with the truth's convention on the grid

### θ′ edge-on

| source | objects | edge | median len (px) | IQR len (px) | area frac | split | merge | vanished | spurious |
|---|---|---|---|---|---|---|---|---|---|
| truth · stride 3 | 74 | 4 | 1.00 | 1.00–6.38 | 0.0143 | – | – | – | – |
| app baseline | 101 | 6 | 1.00 | 1.00–6.38 | 0.0219 | 6 | 18 | 0 | 49 |
| app baseline · P/9 | 101 | 6 | 1.00 | 1.00–6.38 | 0.0219 | 6 | 18 | 0 | 49 |
| app baseline · H/9 | 101 | 6 | 1.00 | 1.00–6.38 | 0.0219 | 6 | 18 | 0 | 49 |
| app guarded | 85 | 6 | 2.00 | 1.00–6.38 | 0.0181 | 8 | 15 | 0 | 21 |
| app guarded · P/9 | 85 | 6 | 2.00 | 1.00–6.38 | 0.0181 | 8 | 15 | 0 | 21 |
| app guarded · H/9 | 85 | 6 | 2.00 | 1.00–6.38 | 0.0181 | 8 | 15 | 0 | 21 |

### θ′ face-on

| source | objects | edge | median len (px) | IQR len (px) | area frac | split | merge | vanished | spurious |
|---|---|---|---|---|---|---|---|---|---|
| truth · stride 3 | 3 | 0 | 22.23 | 21.01–27.27 | 0.0332 | – | – | – | – |
| app baseline | 70 | 2 | 1.00 | 1.00–1.00 | 0.0372 | 0 | 0 | 0 | 67 |
| app baseline · P/9 | 3 | 0 | 22.85 | 21.37–27.92 | 0.0346 | 0 | 0 | 0 | 0 |
| app baseline · H/9 | 3 | 0 | 22.84 | 21.37–27.92 | 0.0346 | 0 | 0 | 0 | 0 |
| app guarded | 54 | 1 | 1.00 | 1.00–1.00 | 0.0365 | 0 | 0 | 0 | 51 |
| app guarded · P/9 | 3 | 0 | 22.82 | 21.37–27.65 | 0.0344 | 0 | 0 | 0 | 0 |
| app guarded · H/9 | 3 | 0 | 22.82 | 21.37–27.65 | 0.0345 | 0 | 0 | 0 | 0 |

### T1

| source | objects | edge | median len (px) | IQR len (px) | area frac | split | merge | vanished | spurious |
|---|---|---|---|---|---|---|---|---|---|
| truth · stride 3 | 37 | 16 | 23.14 | 11.29–42.09 | 0.2174 | – | – | – | – |
| app baseline | 62 | 17 | 8.61 | 1.00–31.20 | 0.2183 | 2 | 1 | 0 | 23 |
| app baseline · P/9 | 37 | 15 | 23.34 | 10.84–42.08 | 0.2172 | 1 | 1 | 2 | 2 |
| app baseline · H/9 | 32 | 15 | 31.20 | 13.37–44.41 | 0.2164 | 1 | 1 | 5 | 0 |
| app guarded | 48 | 17 | 13.37 | 2.00–39.99 | 0.2175 | 2 | 1 | 0 | 9 |
| app guarded · P/9 | 35 | 15 | 27.20 | 11.35–43.03 | 0.2168 | 1 | 0 | 3 | 0 |
| app guarded · H/9 | 32 | 15 | 31.20 | 13.37–44.42 | 0.2161 | 1 | 0 | 6 | 0 |

### Ratios to truth (predicted / truth): object count, median length, area fraction

| source | θ′ edge-on count | θ′ edge-on median | θ′ edge-on area | θ′ face-on count | θ′ face-on median | θ′ face-on area | T1 count | T1 median | T1 area |
|---|---|---|---|---|---|---|---|---|---|
| app baseline | 1.36 | 1.00 | 1.535 | 23.33 | 0.04 | 1.123 | 1.68 | 0.37 | 1.004 |
| app baseline · P/9 | 1.36 | 1.00 | 1.535 | 1.00 | 1.03 | 1.042 | 1.00 | 1.01 | 0.999 |
| app baseline · H/9 | 1.36 | 1.00 | 1.535 | 1.00 | 1.03 | 1.043 | 0.86 | 1.35 | 0.995 |
| app guarded | 1.15 | 2.00 | 1.269 | 18.00 | 0.04 | 1.100 | 1.30 | 0.58 | 1.000 |
| app guarded · P/9 | 1.15 | 2.00 | 1.269 | 1.00 | 1.03 | 1.038 | 0.95 | 1.18 | 0.997 |
| app guarded · H/9 | 1.15 | 2.00 | 1.269 | 1.00 | 1.03 | 1.040 | 0.86 | 1.35 | 0.994 |

