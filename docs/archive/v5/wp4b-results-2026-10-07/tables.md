# WP4b measurement (rule sets: baseline = ProposalRules.shipped; R1b = shipped + beside-K with the evidence guard; R2 = shipped + L/M needs net/L_D >= 3; R1b+R2)

## T-Q: DTSA-II QualSpectra (31 glass standards; SEM bulk 20-25 kV, 10 eV/ch; NOT 200 kV thin film)

#### all classes, truth = the answers file as given (includes Li, B): 31 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 241 | 130 | 111 | 236 | 53.9 % | 55.1 % |
| R1b | 187 | 130 | 57 | 236 | 69.5 % | 55.1 % |
| R2 | 150 | 122 | 28 | 236 | 81.3 % | 51.7 % |
| R1bR2 | 149 | 122 | 27 | 236 | 81.9 % | 51.7 % |

#### all classes, truth without the elements the proposer cannot reach (Li, B; none of H, He, Be, C, N occurs): 31 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 241 | 130 | 111 | 229 | 53.9 % | 56.8 % |
| R1b | 187 | 130 | 57 | 229 | 69.5 % | 56.8 % |
| R2 | 150 | 122 | 28 | 229 | 81.3 % | 53.3 % |
| R1bR2 | 149 | 122 | 27 | 229 | 81.9 % | 53.3 % |

#### class easy: 5 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 27 | 14 | 13 | 21 | 51.9 % | 66.7 % |
| R1b | 20 | 14 | 6 | 21 | 70.0 % | 66.7 % |
| R2 | 18 | 14 | 4 | 21 | 77.8 % | 66.7 % |
| R1bR2 | 18 | 14 | 4 | 21 | 77.8 % | 66.7 % |

#### class easy, reachable truth: 5 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 27 | 14 | 13 | 21 | 51.9 % | 66.7 % |
| R1b | 20 | 14 | 6 | 21 | 70.0 % | 66.7 % |
| R2 | 18 | 14 | 4 | 21 | 77.8 % | 66.7 % |
| R1bR2 | 18 | 14 | 4 | 21 | 77.8 % | 66.7 % |

#### class moderate: 6 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 45 | 22 | 23 | 25 | 48.9 % | 88.0 % |
| R1b | 34 | 22 | 12 | 25 | 64.7 % | 88.0 % |
| R2 | 27 | 22 | 5 | 25 | 81.5 % | 88.0 % |
| R1bR2 | 27 | 22 | 5 | 25 | 81.5 % | 88.0 % |

#### class moderate, reachable truth: 6 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 45 | 22 | 23 | 24 | 48.9 % | 91.7 % |
| R1b | 34 | 22 | 12 | 24 | 64.7 % | 91.7 % |
| R2 | 27 | 22 | 5 | 24 | 81.5 % | 91.7 % |
| R1bR2 | 27 | 22 | 5 | 24 | 81.5 % | 91.7 % |

#### class difficult: 13 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 108 | 61 | 47 | 113 | 56.5 % | 54.0 % |
| R1b | 83 | 61 | 22 | 113 | 73.5 % | 54.0 % |
| R2 | 69 | 59 | 10 | 113 | 85.5 % | 52.2 % |
| R1bR2 | 68 | 59 | 9 | 113 | 86.8 % | 52.2 % |

#### class difficult, reachable truth: 13 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 108 | 61 | 47 | 109 | 56.5 % | 56.0 % |
| R1b | 83 | 61 | 22 | 109 | 73.5 % | 56.0 % |
| R2 | 69 | 59 | 10 | 109 | 85.5 % | 54.1 % |
| R1bR2 | 68 | 59 | 9 | 109 | 86.8 % | 54.1 % |

#### class very difficult: 7 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 61 | 33 | 28 | 77 | 54.1 % | 42.9 % |
| R1b | 50 | 33 | 17 | 77 | 66.0 % | 42.9 % |
| R2 | 36 | 27 | 9 | 77 | 75.0 % | 35.1 % |
| R1bR2 | 36 | 27 | 9 | 77 | 75.0 % | 35.1 % |

#### class very difficult, reachable truth: 7 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 61 | 33 | 28 | 75 | 54.1 % | 44.0 % |
| R1b | 50 | 33 | 17 | 75 | 66.0 % | 44.0 % |
| R2 | 36 | 27 | 9 | 75 | 75.0 % | 36.0 % |
| R1bR2 | 36 | 27 | 9 | 75 | 75.0 % | 36.0 % |

#### Every pick a rule removed against the baseline (T-Q)
| spectrum | rule set | element | in truth | group | net/L_D | rule's reason |
|---|---|---|---|---|---|---|
| K227 (easy) | R1b | Re | false | Re_Ma | 1.25 | R1: within 1.5 FWHM of Si Kα, 1.3 × L_D ≤ 9.8 × L_D |
| K227 (easy) | R2 | Tl | false | Tl_La | 1.42 | R2: 1.4 × L_D < 3 |
| K227 (easy) | R2 | Re | false | Re_Ma | 1.25 | R2: 1.3 × L_D < 3 |
| K227 (easy) | R1bR2 | Tl | false | Tl_La | 1.42 | R2: 1.4 × L_D < 3 |
| K227 (easy) | R1bR2 | Re | false | Re_Ma | 1.25 | R1: within 1.5 FWHM of Si Kα, 1.3 × L_D ≤ 9.8 × L_D |
| K229 (easy) | R1b | Re | false | Re_Ma | 1.64 | R1: within 1.5 FWHM of Si Kα, 1.6 × L_D ≤ 19.7 × L_D |
| K229 (easy) | R1b | V | false | V_La | 1.04 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 5.7 × L_D |
| K229 (easy) | R2 | Re | false | Re_Ma | 1.64 | R2: 1.6 × L_D < 3 |
| K229 (easy) | R2 | Tl | false | Tl_La | 1.13 | R2: 1.1 × L_D < 3 |
| K229 (easy) | R2 | V | false | V_La | 1.04 | R2: 1.0 × L_D < 3 |
| K229 (easy) | R1bR2 | Re | false | Re_Ma | 1.64 | R1: within 1.5 FWHM of Si Kα, 1.6 × L_D ≤ 19.7 × L_D |
| K229 (easy) | R1bR2 | Tl | false | Tl_La | 1.13 | R2: 1.1 × L_D < 3 |
| K229 (easy) | R1bR2 | V | false | V_La | 1.04 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 5.7 × L_D |
| K411 (easy) | R1b | Te | false | Te_La | 1.99 | R1: within 1.5 FWHM of Ca Kα, 2.0 × L_D ≤ 16.1 × L_D |
| K411 (easy) | R1b | Nd | false | Nd_La | 1.16 | R1: within 1.5 FWHM of Cr Kα, 1.2 × L_D ≤ 1.2 × L_D |
| K411 (easy) | R2 | Te | false | Te_La | 1.99 | R2: 2.0 × L_D < 3 |
| K411 (easy) | R2 | Nd | false | Nd_La | 1.16 | R2: 1.2 × L_D < 3 |
| K411 (easy) | R1bR2 | Te | false | Te_La | 1.99 | R1: within 1.5 FWHM of Ca Kα, 2.0 × L_D ≤ 16.1 × L_D |
| K411 (easy) | R1bR2 | Nd | false | Nd_La | 1.16 | R1: within 1.5 FWHM of Cr Kα, 1.2 × L_D ≤ 1.2 × L_D |
| K412 (easy) | R1b | Te | false | Te_La | 1.32 | R1: within 1.5 FWHM of Ca Kα, 1.3 × L_D ≤ 54.6 × L_D |
| K412 (easy) | R2 | Te | false | Te_La | 1.32 | R2: 1.3 × L_D < 3 |
| K412 (easy) | R1bR2 | Te | false | Te_La | 1.32 | R1: within 1.5 FWHM of Ca Kα, 1.3 × L_D ≤ 54.6 × L_D |
| K496 (easy) | R1b | V | false | V_La | 1.56 | R1: within 1.5 FWHM of O Kα, 1.6 × L_D ≤ 5.4 × L_D |
| K496 (easy) | R2 | V | false | V_La | 1.56 | R2: 1.6 × L_D < 3 |
| K496 (easy) | R1bR2 | V | false | V_La | 1.56 | R1: within 1.5 FWHM of O Kα, 1.6 × L_D ≤ 5.4 × L_D |
| K1092 (moderate) | R1b | Sr | false | Sr_La | 1.64 | R1: within 1.5 FWHM of Si Kα, 1.6 × L_D ≤ 33.9 × L_D |
| K1092 (moderate) | R1b | Rb | false | Rb_La | 1.34 | R1: within 1.5 FWHM of Si Kα, 1.3 × L_D ≤ 33.9 × L_D |
| K1092 (moderate) | R1b | V | false | V_La | 1.22 | R1: within 1.5 FWHM of O Kα, 1.2 × L_D ≤ 5.9 × L_D |
| K1092 (moderate) | R2 | Rh | false | Rh_La | 1.65 | R2: 1.6 × L_D < 3 |
| K1092 (moderate) | R2 | Sr | false | Sr_La | 1.64 | R2: 1.6 × L_D < 3 |
| K1092 (moderate) | R2 | Rb | false | Rb_La | 1.34 | R2: 1.3 × L_D < 3 |
| K1092 (moderate) | R2 | V | false | V_La | 1.22 | R2: 1.2 × L_D < 3 |
| K1092 (moderate) | R1bR2 | Rh | false | Rh_La | 1.65 | R2: 1.6 × L_D < 3 |
| K1092 (moderate) | R1bR2 | Sr | false | Sr_La | 1.64 | R1: within 1.5 FWHM of Si Kα, 1.6 × L_D ≤ 33.9 × L_D |
| K1092 (moderate) | R1bR2 | Rb | false | Rb_La | 1.34 | R1: within 1.5 FWHM of Si Kα, 1.3 × L_D ≤ 33.9 × L_D |
| K1092 (moderate) | R1bR2 | V | false | V_La | 1.22 | R1: within 1.5 FWHM of O Kα, 1.2 × L_D ≤ 5.9 × L_D |
| K1236 (moderate) | R1b | Au | false | Au_La | 1.77 | R1: within 1.5 FWHM of Ge Kα, 1.8 × L_D ≤ 62.5 × L_D |
| K1236 (moderate) | R1b | V | false | V_La | 1.48 | R1: within 1.5 FWHM of O Kα, 1.5 × L_D ≤ 6.5 × L_D |
| K1236 (moderate) | R2 | Au | false | Au_La | 1.77 | R2: 1.8 × L_D < 3 |
| K1236 (moderate) | R2 | V | false | V_La | 1.48 | R2: 1.5 × L_D < 3 |
| K1236 (moderate) | R2 | Tb | false | Tb_Ma | 1.16 | R2: 1.2 × L_D < 3 |
| K1236 (moderate) | R1bR2 | Au | false | Au_La | 1.77 | R1: within 1.5 FWHM of Ge Kα, 1.8 × L_D ≤ 62.5 × L_D |
| K1236 (moderate) | R1bR2 | V | false | V_La | 1.48 | R1: within 1.5 FWHM of O Kα, 1.5 × L_D ≤ 6.5 × L_D |
| K1236 (moderate) | R1bR2 | Tb | false | Tb_Ma | 1.16 | R2: 1.2 × L_D < 3 |
| K309 (moderate) | R1b | Te | false | Te_La | 1.49 | R1: within 1.5 FWHM of Ca Kα, 1.5 × L_D ≤ 83.4 × L_D |
| K309 (moderate) | R2 | Pb | false | Pb_La | 1.67 | R2: 1.7 × L_D < 3 |
| K309 (moderate) | R2 | Te | false | Te_La | 1.49 | R2: 1.5 × L_D < 3 |
| K309 (moderate) | R2 | Pd | false | Pd_La | 1.02 | R2: 1.0 × L_D < 3 |
| K309 (moderate) | R1bR2 | Pb | false | Pb_La | 1.67 | R2: 1.7 × L_D < 3 |
| K309 (moderate) | R1bR2 | Te | false | Te_La | 1.49 | R1: within 1.5 FWHM of Ca Kα, 1.5 × L_D ≤ 83.4 × L_D |
| K309 (moderate) | R1bR2 | Pd | false | Pd_La | 1.02 | R2: 1.0 × L_D < 3 |
| K453 (moderate) | R1b | Au | false | Au_La | 1.62 | R1: within 1.5 FWHM of Ge Kα, 1.6 × L_D ≤ 43.1 × L_D |
| K453 (moderate) | R1b | V | false | V_La | 1.06 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 5.7 × L_D |
| K453 (moderate) | R2 | Au | false | Au_La | 1.62 | R2: 1.6 × L_D < 3 |
| K453 (moderate) | R2 | V | false | V_La | 1.06 | R2: 1.1 × L_D < 3 |
| K453 (moderate) | R1bR2 | Au | false | Au_La | 1.62 | R1: within 1.5 FWHM of Ge Kα, 1.6 × L_D ≤ 43.1 × L_D |
| K453 (moderate) | R1bR2 | V | false | V_La | 1.06 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 5.7 × L_D |
| K456 (moderate) | R1b | Re | false | Re_Ma | 1.79 | R1: within 1.5 FWHM of Si Kα, 1.8 × L_D ≤ 20.1 × L_D |
| K456 (moderate) | R1b | V | false | V_La | 1.10 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 6.2 × L_D |
| K456 (moderate) | R2 | Re | false | Re_Ma | 1.79 | R2: 1.8 × L_D < 3 |
| K456 (moderate) | R2 | V | false | V_La | 1.10 | R2: 1.1 × L_D < 3 |
| K456 (moderate) | R1bR2 | Re | false | Re_Ma | 1.79 | R1: within 1.5 FWHM of Si Kα, 1.8 × L_D ≤ 20.1 × L_D |
| K456 (moderate) | R1bR2 | V | false | V_La | 1.10 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 6.2 × L_D |
| K458 (moderate) | R1b | V | false | V_La | 1.32 | R1: within 1.5 FWHM of O Kα, 1.3 × L_D ≤ 5.4 × L_D |
| K458 (moderate) | R2 | Bi | false | Bi_La | 2.47 | R2: 2.5 × L_D < 3 |
| K458 (moderate) | R2 | Pt | false | Pt_La | 2.44 | R2: 2.4 × L_D < 3 |
| K458 (moderate) | R2 | V | false | V_La | 1.32 | R2: 1.3 × L_D < 3 |
| K458 (moderate) | R2 | Au | false | Au_La | 1.16 | R2: 1.2 × L_D < 3 |
| K458 (moderate) | R1bR2 | Bi | false | Bi_La | 2.47 | R2: 2.5 × L_D < 3 |
| K458 (moderate) | R1bR2 | Pt | false | Pt_La | 2.44 | R2: 2.4 × L_D < 3 |
| K458 (moderate) | R1bR2 | V | false | V_La | 1.32 | R1: within 1.5 FWHM of O Kα, 1.3 × L_D ≤ 5.4 × L_D |
| K458 (moderate) | R1bR2 | Au | false | Au_La | 1.16 | R2: 1.2 × L_D < 3 |
| K1001 (difficult) | R1b | V | false | V_La | 1.47 | R1: within 1.5 FWHM of O Kα, 1.5 × L_D ≤ 6.5 × L_D |
| K1001 (difficult) | R2 | Pb | TRUE | Pb_La | 2.80 | R2: 2.8 × L_D < 3 |
| K1001 (difficult) | R2 | V | false | V_La | 1.47 | R2: 1.5 × L_D < 3 |
| K1001 (difficult) | R1bR2 | Pb | TRUE | Pb_La | 2.80 | R2: 2.8 × L_D < 3 |
| K1001 (difficult) | R1bR2 | V | false | V_La | 1.47 | R1: within 1.5 FWHM of O Kα, 1.5 × L_D ≤ 6.5 × L_D |
| K1008 (difficult) | R1b | V | false | V_La | 1.48 | R1: within 1.5 FWHM of O Kα, 1.5 × L_D ≤ 6.5 × L_D |
| K1008 (difficult) | R1b | Te | false | Te_La | 1.23 | R1: within 1.5 FWHM of Ca Kα, 1.2 × L_D ≤ 48.6 × L_D |
| K1008 (difficult) | R2 | V | false | V_La | 1.48 | R2: 1.5 × L_D < 3 |
| K1008 (difficult) | R2 | Te | false | Te_La | 1.23 | R2: 1.2 × L_D < 3 |
| K1008 (difficult) | R1bR2 | V | false | V_La | 1.48 | R1: within 1.5 FWHM of O Kα, 1.5 × L_D ≤ 6.5 × L_D |
| K1008 (difficult) | R1bR2 | Te | false | Te_La | 1.23 | R1: within 1.5 FWHM of Ca Kα, 1.2 × L_D ≤ 48.6 × L_D |
| K1070 (difficult) | R1b | Te | false | Te_La | 1.69 | R1: within 1.5 FWHM of Ca Kα, 1.7 × L_D ≤ 40.4 × L_D |
| K1070 (difficult) | R1b | Hf | false | Hf_Ma | 1.28 | R1: within 1.5 FWHM of Si Kα, 1.3 × L_D ≤ 100.2 × L_D |
| K1070 (difficult) | R1b | V | false | V_La | 1.05 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 5.3 × L_D |
| K1070 (difficult) | R2 | Te | false | Te_La | 1.69 | R2: 1.7 × L_D < 3 |
| K1070 (difficult) | R2 | Hf | false | Hf_Ma | 1.28 | R2: 1.3 × L_D < 3 |
| K1070 (difficult) | R2 | V | false | V_La | 1.05 | R2: 1.1 × L_D < 3 |
| K1070 (difficult) | R1bR2 | Te | false | Te_La | 1.69 | R1: within 1.5 FWHM of Ca Kα, 1.7 × L_D ≤ 40.4 × L_D |
| K1070 (difficult) | R1bR2 | Hf | false | Hf_Ma | 1.28 | R1: within 1.5 FWHM of Si Kα, 1.3 × L_D ≤ 100.2 × L_D |
| K1070 (difficult) | R1bR2 | V | false | V_La | 1.05 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 5.3 × L_D |
| K1132 (difficult) | R1b | V | false | V_La | 1.51 | R1: within 1.5 FWHM of O Kα, 1.5 × L_D ≤ 6.5 × L_D |
| K1132 (difficult) | R1b | Te | false | Te_La | 1.06 | R1: within 1.5 FWHM of Ca Kα, 1.1 × L_D ≤ 42.3 × L_D |
| K1132 (difficult) | R2 | V | false | V_La | 1.51 | R2: 1.5 × L_D < 3 |
| K1132 (difficult) | R2 | Pb | false | Pb_La | 1.08 | R2: 1.1 × L_D < 3 |
| K1132 (difficult) | R2 | Te | false | Te_La | 1.06 | R2: 1.1 × L_D < 3 |
| K1132 (difficult) | R2 | Tl | false | Tl_La | 1.06 | R2: 1.1 × L_D < 3 |
| K1132 (difficult) | R1bR2 | V | false | V_La | 1.51 | R1: within 1.5 FWHM of O Kα, 1.5 × L_D ≤ 6.5 × L_D |
| K1132 (difficult) | R1bR2 | Pb | false | Pb_La | 1.08 | R2: 1.1 × L_D < 3 |
| K1132 (difficult) | R1bR2 | Te | false | Te_La | 1.06 | R1: within 1.5 FWHM of Ca Kα, 1.1 × L_D ≤ 42.3 × L_D |
| K1132 (difficult) | R1bR2 | Tl | false | Tl_La | 1.06 | R2: 1.1 × L_D < 3 |
| K1235 (difficult) | R1b | V | false | V_La | 1.44 | R1: within 1.5 FWHM of O Kα, 1.4 × L_D ≤ 6.5 × L_D |
| K1235 (difficult) | R1b | Te | false | Te_La | 1.01 | R1: within 1.5 FWHM of Ca Kα, 1.0 × L_D ≤ 61.8 × L_D |
| K1235 (difficult) | R2 | Sm | false | Sm_La | 1.49 | R2: 1.5 × L_D < 3 |
| K1235 (difficult) | R2 | V | false | V_La | 1.44 | R2: 1.4 × L_D < 3 |
| K1235 (difficult) | R2 | Te | false | Te_La | 1.01 | R2: 1.0 × L_D < 3 |
| K1235 (difficult) | R1bR2 | Sm | false | Sm_La | 1.49 | R2: 1.5 × L_D < 3 |
| K1235 (difficult) | R1bR2 | V | false | V_La | 1.44 | R1: within 1.5 FWHM of O Kα, 1.4 × L_D ≤ 6.5 × L_D |
| K1235 (difficult) | R1bR2 | Te | false | Te_La | 1.01 | R1: within 1.5 FWHM of Ca Kα, 1.0 × L_D ≤ 61.8 × L_D |
| K230 (difficult) | R1b | V | false | V_La | 1.99 | R1: within 1.5 FWHM of O Kα, 2.0 × L_D ≤ 7.1 × L_D |
| K230 (difficult) | R1b | W | false | W_Ma | 1.43 | R1: within 1.5 FWHM of Si Kα, 1.4 × L_D ≤ 9.2 × L_D |
| K230 (difficult) | R1b | Rb | false | Rb_La | 1.27 | R1: within 1.5 FWHM of Si Kα, 1.3 × L_D ≤ 9.2 × L_D |
| K230 (difficult) | R2 | V | false | V_La | 1.99 | R2: 2.0 × L_D < 3 |
| K230 (difficult) | R2 | W | false | W_Ma | 1.43 | R2: 1.4 × L_D < 3 |
| K230 (difficult) | R2 | Rb | false | Rb_La | 1.27 | R2: 1.3 × L_D < 3 |
| K230 (difficult) | R1bR2 | V | false | V_La | 1.99 | R1: within 1.5 FWHM of O Kα, 2.0 × L_D ≤ 7.1 × L_D |
| K230 (difficult) | R1bR2 | W | false | W_Ma | 1.43 | R1: within 1.5 FWHM of Si Kα, 1.4 × L_D ≤ 9.2 × L_D |
| K230 (difficult) | R1bR2 | Rb | false | Rb_La | 1.27 | R1: within 1.5 FWHM of Si Kα, 1.3 × L_D ≤ 9.2 × L_D |
| K249 (difficult) | R1b | Re | false | Re_Ma | 1.15 | R1: within 1.5 FWHM of Si Kα, 1.1 × L_D ≤ 3.1 × L_D |
| K249 (difficult) | R1b | V | false | V_La | 1.13 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 5.7 × L_D |
| K249 (difficult) | R2 | Br | false | Br_La | 2.69 | R2: 2.7 × L_D < 3 |
| K249 (difficult) | R2 | Re | false | Re_Ma | 1.15 | R2: 1.1 × L_D < 3 |
| K249 (difficult) | R2 | V | false | V_La | 1.13 | R2: 1.1 × L_D < 3 |
| K249 (difficult) | R1bR2 | Br | false | Br_La | 2.69 | R2: 2.7 × L_D < 3 |
| K249 (difficult) | R1bR2 | Re | false | Re_Ma | 1.15 | R1: within 1.5 FWHM of Si Kα, 1.1 × L_D ≤ 3.1 × L_D |
| K249 (difficult) | R1bR2 | V | false | V_La | 1.13 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 5.7 × L_D |
| K251 (difficult) | R1b | Hf | false | Hf_Ma | 3.76 | R1: within 1.5 FWHM of Si Kα, 3.8 × L_D ≤ 30.6 × L_D |
| K251 (difficult) | R1b | V | false | V_La | 1.73 | R1: within 1.5 FWHM of O Kα, 1.7 × L_D ≤ 7.7 × L_D |
| K251 (difficult) | R1b | Yb | false | Yb_La | 1.54 | R1: within 1.5 FWHM of Ni Kα, 1.5 × L_D ≤ 1.7 × L_D |
| K251 (difficult) | R1b | W | false | W_Ma | 1.18 | R1: within 1.5 FWHM of Si Kα, 1.2 × L_D ≤ 30.6 × L_D |
| K251 (difficult) | R2 | V | false | V_La | 1.73 | R2: 1.7 × L_D < 3 |
| K251 (difficult) | R2 | Yb | false | Yb_La | 1.54 | R2: 1.5 × L_D < 3 |
| K251 (difficult) | R2 | Cs | false | Cs_La | 1.30 | R2: 1.3 × L_D < 3 |
| K251 (difficult) | R2 | W | false | W_Ma | 1.18 | R2: 1.2 × L_D < 3 |
| K251 (difficult) | R1bR2 | Hf | false | Hf_Ma | 3.76 | R1: within 1.5 FWHM of Si Kα, 3.8 × L_D ≤ 30.6 × L_D |
| K251 (difficult) | R1bR2 | V | false | V_La | 1.73 | R1: within 1.5 FWHM of O Kα, 1.7 × L_D ≤ 7.7 × L_D |
| K251 (difficult) | R1bR2 | Yb | false | Yb_La | 1.54 | R1: within 1.5 FWHM of Ni Kα, 1.5 × L_D ≤ 1.7 × L_D |
| K251 (difficult) | R1bR2 | Cs | false | Cs_La | 1.30 | R2: 1.3 × L_D < 3 |
| K251 (difficult) | R1bR2 | W | false | W_Ma | 1.18 | R1: within 1.5 FWHM of Si Kα, 1.2 × L_D ≤ 30.6 × L_D |
| K252 (difficult) | R1b | V | false | V_La | 1.33 | R1: within 1.5 FWHM of O Kα, 1.3 × L_D ≤ 6.1 × L_D |
| K252 (difficult) | R2 | Pt | false | Pt_La | 1.66 | R2: 1.7 × L_D < 3 |
| K252 (difficult) | R2 | V | false | V_La | 1.33 | R2: 1.3 × L_D < 3 |
| K252 (difficult) | R1bR2 | Pt | false | Pt_La | 1.66 | R2: 1.7 × L_D < 3 |
| K252 (difficult) | R1bR2 | V | false | V_La | 1.33 | R1: within 1.5 FWHM of O Kα, 1.3 × L_D ≤ 6.1 × L_D |
| K253 (difficult) | R1b | V | false | V_La | 1.23 | R1: within 1.5 FWHM of O Kα, 1.2 × L_D ≤ 5.2 × L_D |
| K253 (difficult) | R2 | Pt | false | Pt_La | 1.64 | R2: 1.6 × L_D < 3 |
| K253 (difficult) | R2 | V | false | V_La | 1.23 | R2: 1.2 × L_D < 3 |
| K253 (difficult) | R1bR2 | Pt | false | Pt_La | 1.64 | R2: 1.6 × L_D < 3 |
| K253 (difficult) | R1bR2 | V | false | V_La | 1.23 | R1: within 1.5 FWHM of O Kα, 1.2 × L_D ≤ 5.2 × L_D |
| K326 (difficult) | R1b | Te | false | Te_La | 2.03 | R1: within 1.5 FWHM of Ca Kα, 2.0 × L_D ≤ 52.4 × L_D |
| K326 (difficult) | R2 | Te | false | Te_La | 2.03 | R2: 2.0 × L_D < 3 |
| K326 (difficult) | R2 | Nd | false | Nd_La | 1.38 | R2: 1.4 × L_D < 3 |
| K326 (difficult) | R2 | Pb | false | Pb_La | 1.28 | R2: 1.3 × L_D < 3 |
| K326 (difficult) | R1bR2 | Te | false | Te_La | 2.03 | R1: within 1.5 FWHM of Ca Kα, 2.0 × L_D ≤ 52.4 × L_D |
| K326 (difficult) | R1bR2 | Nd | false | Nd_La | 1.38 | R2: 1.4 × L_D < 3 |
| K326 (difficult) | R1bR2 | Pb | false | Pb_La | 1.28 | R2: 1.3 × L_D < 3 |
| K489 (difficult) | R1b | V | false | V_La | 1.40 | R1: within 1.5 FWHM of O Kα, 1.4 × L_D ≤ 5.8 × L_D |
| K489 (difficult) | R2 | Bi | false | Bi_La | 2.08 | R2: 2.1 × L_D < 3 |
| K489 (difficult) | R2 | Ta | TRUE | Ta_La | 2.02 | R2: 2.0 × L_D < 3 |
| K489 (difficult) | R2 | V | false | V_La | 1.40 | R2: 1.4 × L_D < 3 |
| K489 (difficult) | R2 | Hg | false | Hg_La | 1.14 | R2: 1.1 × L_D < 3 |
| K489 (difficult) | R2 | Au | false | Au_La | 1.09 | R2: 1.1 × L_D < 3 |
| K489 (difficult) | R1bR2 | Bi | false | Bi_La | 2.08 | R2: 2.1 × L_D < 3 |
| K489 (difficult) | R1bR2 | Ta | TRUE | Ta_La | 2.02 | R2: 2.0 × L_D < 3 |
| K489 (difficult) | R1bR2 | V | false | V_La | 1.40 | R1: within 1.5 FWHM of O Kα, 1.4 × L_D ≤ 5.8 × L_D |
| K489 (difficult) | R1bR2 | Hg | false | Hg_La | 1.14 | R2: 1.1 × L_D < 3 |
| K489 (difficult) | R1bR2 | Au | false | Au_La | 1.09 | R2: 1.1 × L_D < 3 |
| K491 (difficult) | R1b | Au | false | Au_La | 1.49 | R1: within 1.5 FWHM of Ge Kα, 1.5 × L_D ≤ 38.0 × L_D |
| K491 (difficult) | R1b | V | false | V_La | 1.01 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 5.3 × L_D |
| K491 (difficult) | R2 | Au | false | Au_La | 1.49 | R2: 1.5 × L_D < 3 |
| K491 (difficult) | R2 | Ba | false | Ba_La | 1.24 | R2: 1.2 × L_D < 3 |
| K491 (difficult) | R2 | V | false | V_La | 1.01 | R2: 1.0 × L_D < 3 |
| K491 (difficult) | R1bR2 | Au | false | Au_La | 1.49 | R1: within 1.5 FWHM of Ge Kα, 1.5 × L_D ≤ 38.0 × L_D |
| K491 (difficult) | R1bR2 | Ba | false | Ba_La | 1.24 | R2: 1.2 × L_D < 3 |
| K491 (difficult) | R1bR2 | V | false | V_La | 1.01 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 5.3 × L_D |
| K1053 (very difficult) | R1b | Re | false | Re_Ma | 1.82 | R1: within 1.5 FWHM of Si Kα, 1.8 × L_D ≤ 13.3 × L_D |
| K1053 (very difficult) | R2 | I | TRUE | I_La | 2.46 | R2: 2.5 × L_D < 3 |
| K1053 (very difficult) | R2 | Re | false | Re_Ma | 1.82 | R2: 1.8 × L_D < 3 |
| K1053 (very difficult) | R2 | Tl | false | Tl_La | 1.24 | R2: 1.2 × L_D < 3 |
| K1053 (very difficult) | R1bR2 | I | TRUE | I_La | 2.46 | R2: 2.5 × L_D < 3 |
| K1053 (very difficult) | R1bR2 | Re | false | Re_Ma | 1.82 | R1: within 1.5 FWHM of Si Kα, 1.8 × L_D ≤ 13.3 × L_D |
| K1053 (very difficult) | R1bR2 | Tl | false | Tl_La | 1.24 | R2: 1.2 × L_D < 3 |
| K240 (very difficult) | R1b | V | false | V_La | 2.30 | R1: within 1.5 FWHM of O Kα, 2.3 × L_D ≤ 7.8 × L_D |
| K240 (very difficult) | R1b | Rb | false | Rb_La | 1.35 | R1: within 1.5 FWHM of Si Kα, 1.3 × L_D ≤ 28.9 × L_D |
| K240 (very difficult) | R2 | V | false | V_La | 2.30 | R2: 2.3 × L_D < 3 |
| K240 (very difficult) | R2 | Cs | false | Cs_La | 1.81 | R2: 1.8 × L_D < 3 |
| K240 (very difficult) | R2 | Hf | false | Hf_La | 1.36 | R2: 1.4 × L_D < 3 |
| K240 (very difficult) | R2 | Rb | false | Rb_La | 1.35 | R2: 1.3 × L_D < 3 |
| K240 (very difficult) | R1bR2 | V | false | V_La | 2.30 | R1: within 1.5 FWHM of O Kα, 2.3 × L_D ≤ 7.8 × L_D |
| K240 (very difficult) | R1bR2 | Cs | false | Cs_La | 1.81 | R2: 1.8 × L_D < 3 |
| K240 (very difficult) | R1bR2 | Hf | false | Hf_La | 1.36 | R2: 1.4 × L_D < 3 |
| K240 (very difficult) | R1bR2 | Rb | false | Rb_La | 1.35 | R1: within 1.5 FWHM of Si Kα, 1.3 × L_D ≤ 28.9 × L_D |
| K493 (very difficult) | R1b | Re | false | Re_Ma | 2.08 | R1: within 1.5 FWHM of Si Kα, 2.1 × L_D ≤ 24.3 × L_D |
| K493 (very difficult) | R1b | V | false | V_La | 1.23 | R1: within 1.5 FWHM of O Kα, 1.2 × L_D ≤ 6.5 × L_D |
| K493 (very difficult) | R2 | Re | false | Re_Ma | 2.08 | R2: 2.1 × L_D < 3 |
| K493 (very difficult) | R2 | Ba | false | Ba_La | 1.82 | R2: 1.8 × L_D < 3 |
| K493 (very difficult) | R2 | V | false | V_La | 1.23 | R2: 1.2 × L_D < 3 |
| K493 (very difficult) | R2 | Nd | false | Nd_La | 1.17 | R2: 1.2 × L_D < 3 |
| K493 (very difficult) | R2 | Zr | TRUE | Zr_La | 1.04 | R2: 1.0 × L_D < 3 |
| K493 (very difficult) | R1bR2 | Re | false | Re_Ma | 2.08 | R1: within 1.5 FWHM of Si Kα, 2.1 × L_D ≤ 24.3 × L_D |
| K493 (very difficult) | R1bR2 | Ba | false | Ba_La | 1.82 | R2: 1.8 × L_D < 3 |
| K493 (very difficult) | R1bR2 | V | false | V_La | 1.23 | R1: within 1.5 FWHM of O Kα, 1.2 × L_D ≤ 6.5 × L_D |
| K493 (very difficult) | R1bR2 | Nd | false | Nd_La | 1.17 | R2: 1.2 × L_D < 3 |
| K493 (very difficult) | R1bR2 | Zr | TRUE | Zr_La | 1.04 | R2: 1.0 × L_D < 3 |
| K497 (very difficult) | R1b | V | false | V_La | 1.56 | R1: within 1.5 FWHM of O Kα, 1.6 × L_D ≤ 5.5 × L_D |
| K497 (very difficult) | R2 | V | false | V_La | 1.56 | R2: 1.6 × L_D < 3 |
| K497 (very difficult) | R2 | Tl | false | Tl_La | 1.02 | R2: 1.0 × L_D < 3 |
| K497 (very difficult) | R1bR2 | V | false | V_La | 1.56 | R1: within 1.5 FWHM of O Kα, 1.6 × L_D ≤ 5.5 × L_D |
| K497 (very difficult) | R1bR2 | Tl | false | Tl_La | 1.02 | R2: 1.0 × L_D < 3 |
| K523 (very difficult) | R1b | Nd | false | Nd_La | 1.74 | R1: within 1.5 FWHM of Cr Kα, 1.7 × L_D ≤ 2.2 × L_D |
| K523 (very difficult) | R1b | Re | false | Re_Ma | 1.09 | R1: within 1.5 FWHM of Si Kα, 1.1 × L_D ≤ 14.2 × L_D |
| K523 (very difficult) | R2 | Nd | false | Nd_La | 1.74 | R2: 1.7 × L_D < 3 |
| K523 (very difficult) | R2 | Cs | false | Cs_La | 1.56 | R2: 1.6 × L_D < 3 |
| K523 (very difficult) | R2 | Hf | false | Hf_La | 1.50 | R2: 1.5 × L_D < 3 |
| K523 (very difficult) | R2 | Ba | TRUE | Ba_La | 1.23 | R2: 1.2 × L_D < 3 |
| K523 (very difficult) | R2 | Zr | TRUE | Zr_La | 1.10 | R2: 1.1 × L_D < 3 |
| K523 (very difficult) | R2 | Re | false | Re_Ma | 1.09 | R2: 1.1 × L_D < 3 |
| K523 (very difficult) | R1bR2 | Nd | false | Nd_La | 1.74 | R1: within 1.5 FWHM of Cr Kα, 1.7 × L_D ≤ 2.2 × L_D |
| K523 (very difficult) | R1bR2 | Cs | false | Cs_La | 1.56 | R2: 1.6 × L_D < 3 |
| K523 (very difficult) | R1bR2 | Hf | false | Hf_La | 1.50 | R2: 1.5 × L_D < 3 |
| K523 (very difficult) | R1bR2 | Ba | TRUE | Ba_La | 1.23 | R2: 1.2 × L_D < 3 |
| K523 (very difficult) | R1bR2 | Zr | TRUE | Zr_La | 1.10 | R2: 1.1 × L_D < 3 |
| K523 (very difficult) | R1bR2 | Re | false | Re_Ma | 1.09 | R1: within 1.5 FWHM of Si Kα, 1.1 × L_D ≤ 14.2 × L_D |
| K963 (very difficult) | R1b | V | false | V_La | 1.37 | R1: within 1.5 FWHM of O Kα, 1.4 × L_D ≤ 5.6 × L_D |
| K963 (very difficult) | R2 | V | false | V_La | 1.37 | R2: 1.4 × L_D < 3 |
| K963 (very difficult) | R1bR2 | V | false | V_La | 1.37 | R1: within 1.5 FWHM of O Kα, 1.4 × L_D ≤ 5.6 × L_D |
| K968 (very difficult) | R1b | Au | false | Au_La | 1.62 | R1: within 1.5 FWHM of Ge Kα, 1.6 × L_D ≤ 79.1 × L_D |
| K968 (very difficult) | R1b | V | false | V_La | 1.04 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 5.3 × L_D |
| K968 (very difficult) | R2 | Ba | TRUE | Ba_La | 1.93 | R2: 1.9 × L_D < 3 |
| K968 (very difficult) | R2 | Au | false | Au_La | 1.62 | R2: 1.6 × L_D < 3 |
| K968 (very difficult) | R2 | Eu | TRUE | Eu_La | 1.08 | R2: 1.1 × L_D < 3 |
| K968 (very difficult) | R2 | V | false | V_La | 1.04 | R2: 1.0 × L_D < 3 |
| K968 (very difficult) | R1bR2 | Ba | TRUE | Ba_La | 1.93 | R2: 1.9 × L_D < 3 |
| K968 (very difficult) | R1bR2 | Au | false | Au_La | 1.62 | R1: within 1.5 FWHM of Ge Kα, 1.6 × L_D ≤ 79.1 × L_D |
| K968 (very difficult) | R1bR2 | Eu | TRUE | Eu_La | 1.08 | R2: 1.1 × L_D < 3 |
| K968 (very difficult) | R1bR2 | V | false | V_La | 1.04 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 5.3 × L_D |

#### Truth elements the BASELINE does not pick (T-Q), to see what the rules could not have cost
Al: 10; Si: 7; Mg: 6; Zr: 6; Fe: 5; P: 5; Zn: 5; Pb: 5; B: 5; Ca: 4; Ta: 4; Ti: 4; Na: 3; Ni: 3; Ce: 3; Th: 3; U: 3; Li: 2; Cr: 2; Bi: 2; Ge: 2; Eu: 2; Pr: 1; Nd: 1; Er: 1; Rb: 1; Sr: 1; Cs: 1; Ba: 1; Tm: 1; Yb: 1; Mo: 1; Pd: 1; Hf: 1; F: 1; Cl: 1; Br: 1

## T-S: seeded risk simulator (200 kV, owner's axis, Al matrix; Al is in every truth)

#### Pairs: picks per rule set (L = the L element, K = the K element; Y = picked)
| case | ratio L:K | dose | planted net/L_D L, K | baseline L K | R1b L K | R2 L K | R1b+R2 L K | candidate net/L_D L, K |
|---|---|---|---|---|---|---|---|---|
| Hf La + Cu Ka | 0.3 | low | 1.5, 4.7 | Y Y | - Y | - Y | - Y | 1.3, 3.7 |
| Hf La + Cu Ka | 0.3 | high | 6.0, 18.6 | Y Y | - Y | Y Y | - Y | 4.8, 10.0 |
| Hf La + Cu Ka | 1 | low | 1.6, 1.5 | Y Y | - Y | - Y | - Y | 1.2, 1.5 |
| Hf La + Cu Ka | 1 | high | 6.4, 6.0 | Y Y | Y Y | Y Y | Y Y | 5.4, 4.2 |
| Hf La + Cu Ka | 3 | low | 4.8, 1.5 | Y Y | Y Y | Y Y | Y Y | 4.6, 1.6 |
| Hf La + Cu Ka | 3 | high | 19.3, 6.0 | Y Y | Y Y | Y Y | Y Y | 13.6, 4.0 |
| Ta La + Cu Ka | 0.3 | low | 1.5, 6.2 | Y Y | - Y | - Y | - Y | 1.6, 4.4 |
| Ta La + Cu Ka | 0.3 | high | 6.0, 24.7 | Y Y | - Y | Y Y | - Y | 3.9, 13.8 |
| Ta La + Cu Ka | 1 | low | 1.5, 1.9 | Y Y | Y Y | - Y | - Y | 1.6, 1.0 |
| Ta La + Cu Ka | 1 | high | 6.0, 7.4 | Y Y | - Y | Y Y | - Y | 4.4, 4.5 |
| Ta La + Cu Ka | 3 | low | 3.6, 1.5 | Y Y | Y Y | Y Y | Y Y | 3.3, 1.2 |
| Ta La + Cu Ka | 3 | high | 14.6, 6.0 | Y Y | Y Y | Y Y | Y Y | 13.6, 2.0 |
| Pt La + Ga Ka | 0.3 | low | 1.5, 7.0 | Y Y | - Y | - Y | - Y | 1.8, 6.2 |
| Pt La + Ga Ka | 0.3 | high | 6.0, 28.2 | Y Y | - Y | Y Y | - Y | 6.9, 22.1 |
| Pt La + Ga Ka | 1 | low | 1.5, 2.1 | Y Y | - Y | - Y | - Y | 1.6, 2.2 |
| Pt La + Ga Ka | 1 | high | 6.0, 8.5 | Y Y | - Y | Y Y | - Y | 6.5, 7.3 |
| Pt La + Ga Ka | 3 | low | 3.2, 1.5 | Y Y | Y Y | Y Y | Y Y | 5.0, 1.0 |
| Pt La + Ga Ka | 3 | high | 12.8, 6.0 | Y Y | Y Y | Y Y | Y Y | 18.6, 4.6 |
| Pb La + As Ka | 0.3 | low | 1.5, 4.5 | - Y | - Y | - Y | - Y | 0.7, 2.2 |
| Pb La + As Ka | 0.3 | high | 6.0, 17.9 | Y Y | - Y | Y Y | - Y | 3.6, 5.1 |
| Pb La + As Ka | 1 | low | 1.7, 1.5 | Y - | Y - | - - | - - | 2.9, 0.4 |
| Pb La + As Ka | 1 | high | 6.7, 6.0 | Y Y | Y Y | Y Y | Y Y | 3.7, 1.7 |
| Pb La + As Ka | 3 | low | 5.0, 1.5 | Y - | Y - | Y - | Y - | 5.5, 0.4 |
| Pb La + As Ka | 3 | high | 20.1, 6.0 | Y - | Y - | Y - | Y - | 10.1, 0.9 |
| Ag La + Ar Ka | 0.3 | low | 1.5, 12.2 | - - | - - | - - | - - | 1.6, 6.7 |
| Ag La + Ar Ka | 0.3 | high | 6.0, 48.8 | - - | - - | - - | - - | 1.9, 13.0 |
| Ag La + Ar Ka | 1 | low | 1.5, 3.7 | - - | - - | - - | - - | 2.2, 2.1 |
| Ag La + Ar Ka | 1 | high | 6.0, 14.7 | - - | - - | - - | - - | 4.2, 5.5 |
| Ag La + Ar Ka | 3 | low | 1.8, 1.5 | - - | - - | - - | - - | 2.7, 1.6 |
| Ag La + Ar Ka | 3 | high | 7.4, 6.0 | - - | - - | - - | - - | 5.4, 1.9 |

#### pairs, all: 30 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 74 | 74 | 0 | 90 | 100.0 % | 82.2 % |
| R1b | 63 | 63 | 0 | 90 | 100.0 % | 70.0 % |
| R2 | 67 | 67 | 0 | 90 | 100.0 % | 74.4 % |
| R1bR2 | 61 | 61 | 0 | 90 | 100.0 % | 67.8 % |

#### pairs ratio >= 1: 20 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 49 | 49 | 0 | 60 | 100.0 % | 81.7 % |
| R1b | 45 | 45 | 0 | 60 | 100.0 % | 75.0 % |
| R2 | 45 | 45 | 0 | 60 | 100.0 % | 75.0 % |
| R1bR2 | 43 | 43 | 0 | 60 | 100.0 % | 71.7 % |

#### pairs ratio 0.3: 10 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 25 | 25 | 0 | 30 | 100.0 % | 83.3 % |
| R1b | 18 | 18 | 0 | 30 | 100.0 % | 60.0 % |
| R2 | 22 | 22 | 0 | 30 | 100.0 % | 73.3 % |
| R1bR2 | 18 | 18 | 0 | 30 | 100.0 % | 60.0 % |

#### Pairs: every pick a rule removed against the baseline
| spectrum | rule set | element | in truth | group | net/L_D | rule's reason |
|---|---|---|---|---|---|---|
| Hf La + Cu Ka r0.3 low | R1b | Hf | TRUE | Hf_La | 1.30 | R1: within 1.5 FWHM of Cu Kα, 1.3 × L_D ≤ 3.7 × L_D |
| Hf La + Cu Ka r0.3 low | R2 | Hf | TRUE | Hf_La | 1.30 | R2: 1.3 × L_D < 3 |
| Hf La + Cu Ka r0.3 low | R1bR2 | Hf | TRUE | Hf_La | 1.30 | R1: within 1.5 FWHM of Cu Kα, 1.3 × L_D ≤ 3.7 × L_D |
| Hf La + Cu Ka r0.3 high | R1b | Hf | TRUE | Hf_La | 4.81 | R1: within 1.5 FWHM of Cu Kα, 4.8 × L_D ≤ 10.0 × L_D |
| Hf La + Cu Ka r0.3 high | R1bR2 | Hf | TRUE | Hf_La | 4.81 | R1: within 1.5 FWHM of Cu Kα, 4.8 × L_D ≤ 10.0 × L_D |
| Hf La + Cu Ka r1 low | R1b | Hf | TRUE | Hf_La | 1.17 | R1: within 1.5 FWHM of Cu Kα, 1.2 × L_D ≤ 1.5 × L_D |
| Hf La + Cu Ka r1 low | R2 | Hf | TRUE | Hf_La | 1.17 | R2: 1.2 × L_D < 3 |
| Hf La + Cu Ka r1 low | R1bR2 | Hf | TRUE | Hf_La | 1.17 | R1: within 1.5 FWHM of Cu Kα, 1.2 × L_D ≤ 1.5 × L_D |
| Ta La + Cu Ka r0.3 low | R1b | Ta | TRUE | Ta_La | 1.55 | R1: within 1.5 FWHM of Cu Kα, 1.6 × L_D ≤ 4.4 × L_D |
| Ta La + Cu Ka r0.3 low | R2 | Ta | TRUE | Ta_La | 1.55 | R2: 1.6 × L_D < 3 |
| Ta La + Cu Ka r0.3 low | R1bR2 | Ta | TRUE | Ta_La | 1.55 | R1: within 1.5 FWHM of Cu Kα, 1.6 × L_D ≤ 4.4 × L_D |
| Ta La + Cu Ka r0.3 high | R1b | Ta | TRUE | Ta_La | 3.91 | R1: within 1.5 FWHM of Cu Kα, 3.9 × L_D ≤ 13.8 × L_D |
| Ta La + Cu Ka r0.3 high | R1bR2 | Ta | TRUE | Ta_La | 3.91 | R1: within 1.5 FWHM of Cu Kα, 3.9 × L_D ≤ 13.8 × L_D |
| Ta La + Cu Ka r1 low | R2 | Ta | TRUE | Ta_La | 1.65 | R2: 1.6 × L_D < 3 |
| Ta La + Cu Ka r1 low | R1bR2 | Ta | TRUE | Ta_La | 1.65 | R2: 1.6 × L_D < 3 |
| Ta La + Cu Ka r1 high | R1b | Ta | TRUE | Ta_La | 4.43 | R1: within 1.5 FWHM of Cu Kα, 4.4 × L_D ≤ 4.5 × L_D |
| Ta La + Cu Ka r1 high | R1bR2 | Ta | TRUE | Ta_La | 4.43 | R1: within 1.5 FWHM of Cu Kα, 4.4 × L_D ≤ 4.5 × L_D |
| Pt La + Ga Ka r0.3 low | R1b | Pt | TRUE | Pt_La | 1.78 | R1: within 1.5 FWHM of Ga Kα, 1.8 × L_D ≤ 6.2 × L_D |
| Pt La + Ga Ka r0.3 low | R2 | Pt | TRUE | Pt_La | 1.78 | R2: 1.8 × L_D < 3 |
| Pt La + Ga Ka r0.3 low | R1bR2 | Pt | TRUE | Pt_La | 1.78 | R1: within 1.5 FWHM of Ga Kα, 1.8 × L_D ≤ 6.2 × L_D |
| Pt La + Ga Ka r0.3 high | R1b | Pt | TRUE | Pt_La | 6.93 | R1: within 1.5 FWHM of Ga Kα, 6.9 × L_D ≤ 22.1 × L_D |
| Pt La + Ga Ka r0.3 high | R1bR2 | Pt | TRUE | Pt_La | 6.93 | R1: within 1.5 FWHM of Ga Kα, 6.9 × L_D ≤ 22.1 × L_D |
| Pt La + Ga Ka r1 low | R1b | Pt | TRUE | Pt_La | 1.60 | R1: within 1.5 FWHM of Ga Kα, 1.6 × L_D ≤ 2.2 × L_D |
| Pt La + Ga Ka r1 low | R2 | Pt | TRUE | Pt_La | 1.60 | R2: 1.6 × L_D < 3 |
| Pt La + Ga Ka r1 low | R1bR2 | Pt | TRUE | Pt_La | 1.60 | R1: within 1.5 FWHM of Ga Kα, 1.6 × L_D ≤ 2.2 × L_D |
| Pt La + Ga Ka r1 high | R1b | Pt | TRUE | Pt_La | 6.51 | R1: within 1.5 FWHM of Ga Kα, 6.5 × L_D ≤ 7.3 × L_D |
| Pt La + Ga Ka r1 high | R1bR2 | Pt | TRUE | Pt_La | 6.51 | R1: within 1.5 FWHM of Ga Kα, 6.5 × L_D ≤ 7.3 × L_D |
| Pb La + As Ka r0.3 high | R1b | Pb | TRUE | Pb_La | 3.63 | R1: within 1.5 FWHM of As Kα, 3.6 × L_D ≤ 5.1 × L_D |
| Pb La + As Ka r0.3 high | R1bR2 | Pb | TRUE | Pb_La | 3.63 | R1: within 1.5 FWHM of As Kα, 3.6 × L_D ≤ 5.1 × L_D |
| Pb La + As Ka r1 low | R2 | Pb | TRUE | Pb_La | 2.89 | R2: 2.9 × L_D < 3 |
| Pb La + As Ka r1 low | R1bR2 | Pb | TRUE | Pb_La | 2.89 | R2: 2.9 × L_D < 3 |

#### Ghosts (K element alone on Al at the high dose; any pick other than Al and the planted K is false)
| ghost | planted net/L_D K | baseline picks | R1b | R2 | R1b+R2 |
|---|---|---|---|---|---|
| Cu | 24.7 | Al Cu | Al Cu | Al Cu | Al Cu |
| Ga | 28.2 | Al Ga | Al Ga | Al Ga | Al Ga |
| As | 17.9 | Al As | Al As | Al As | Al As |
| Ar | 48.8 | Al | Al | Al | Al |

#### ghosts: 4 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 7 | 7 | 0 | 8 | 100.0 % | 87.5 % |
| R1b | 7 | 7 | 0 | 8 | 100.0 % | 87.5 % |
| R2 | 7 | 7 | 0 | 8 | 100.0 % | 87.5 % |
| R1bR2 | 7 | 7 | 0 | 8 | 100.0 % | 87.5 % |

#### Ghosts: every pick a rule removed against the baseline
| spectrum | rule set | element | in truth | group | net/L_D | rule's reason |
|---|---|---|---|---|---|---|
| (none) | | | | | | |

## demo-edx dose ladder (8 regions, truth planted)

#### demo ladder: 8 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 18 | 15 | 3 | 39 | 83.3 % | 38.5 % |
| R1b | 18 | 15 | 3 | 39 | 83.3 % | 38.5 % |
| R2 | 17 | 15 | 2 | 39 | 88.2 % | 38.5 % |
| R1bR2 | 17 | 15 | 2 | 39 | 88.2 % | 38.5 % |
| spectrum | rule set | element | in truth | group | net/L_D | rule's reason |
|---|---|---|---|---|---|---|
| region 7 (300 counts/px) | R2 | Rh | false | Rh_La | 2.51 | R2: 2.5 × L_D < 3 |
| region 7 (300 counts/px) | R1bR2 | Rh | false | Rh_La | 2.51 | R2: 2.5 × L_D < 3 |

## T-V: the owner's Velox selections (agreement, not truth)
files scored 88, distinct 78

#### T-V distinct files: 78 spectra
| rule set | picks | hits | false picks | truth elements | precision | recall |
|---|---|---|---|---|---|---|
| base | 530 | 184 | 346 | 404 | 34.7 % | 45.5 % |
| R1b | 469 | 184 | 285 | 404 | 39.2 % | 45.5 % |
| R2 | 365 | 180 | 185 | 404 | 49.3 % | 44.6 % |
| R1bR2 | 364 | 180 | 184 | 404 | 49.5 % | 44.6 % |

#### Every pick a rule removed against the baseline (T-V)
| spectrum | rule set | element | in truth | group | net/L_D | rule's reason |
|---|---|---|---|---|---|---|
| SI HAADF 1508.emd | R2 | Rh | false | Rh_La | 2.11 | R2: 2.1 × L_D < 3 |
| SI HAADF 1508.emd | R2 | Ru | false | Ru_La | 1.47 | R2: 1.5 × L_D < 3 |
| SI HAADF 1508.emd | R2 | Bi | false | Bi_Ma | 1.11 | R2: 1.1 × L_D < 3 |
| SI HAADF 1508.emd | R1bR2 | Rh | false | Rh_La | 2.11 | R2: 2.1 × L_D < 3 |
| SI HAADF 1508.emd | R1bR2 | Ru | false | Ru_La | 1.47 | R2: 1.5 × L_D < 3 |
| SI HAADF 1508.emd | R1bR2 | Bi | false | Bi_Ma | 1.11 | R2: 1.1 × L_D < 3 |
| SI HAADF 1647.emd | R2 | Rh | false | Rh_La | 1.18 | R2: 1.2 × L_D < 3 |
| SI HAADF 1647.emd | R2 | Ce | false | Ce_La | 1.02 | R2: 1.0 × L_D < 3 |
| SI HAADF 1647.emd | R1bR2 | Rh | false | Rh_La | 1.18 | R2: 1.2 × L_D < 3 |
| SI HAADF 1647.emd | R1bR2 | Ce | false | Ce_La | 1.02 | R2: 1.0 × L_D < 3 |
| SI HAADF 1726.emd | R2 | Ru | false | Ru_La | 1.55 | R2: 1.5 × L_D < 3 |
| SI HAADF 1726.emd | R2 | Ce | false | Ce_La | 1.18 | R2: 1.2 × L_D < 3 |
| SI HAADF 1726.emd | R2 | Ta | false | Ta_Ma | 1.15 | R2: 1.2 × L_D < 3 |
| SI HAADF 1726.emd | R2 | Rh | false | Rh_La | 1.11 | R2: 1.1 × L_D < 3 |
| SI HAADF 1726.emd | R1bR2 | Ru | false | Ru_La | 1.55 | R2: 1.5 × L_D < 3 |
| SI HAADF 1726.emd | R1bR2 | Ce | false | Ce_La | 1.18 | R2: 1.2 × L_D < 3 |
| SI HAADF 1726.emd | R1bR2 | Ta | false | Ta_Ma | 1.15 | R2: 1.2 × L_D < 3 |
| SI HAADF 1726.emd | R1bR2 | Rh | false | Rh_La | 1.11 | R2: 1.1 × L_D < 3 |
| SI HAADF 1735.emd | R2 | Ru | false | Ru_La | 1.44 | R2: 1.4 × L_D < 3 |
| SI HAADF 1735.emd | R2 | Rh | false | Rh_La | 1.14 | R2: 1.1 × L_D < 3 |
| SI HAADF 1735.emd | R2 | Ce | false | Ce_La | 1.11 | R2: 1.1 × L_D < 3 |
| SI HAADF 1735.emd | R2 | Rb | false | Rb_La | 1.05 | R2: 1.0 × L_D < 3 |
| SI HAADF 1735.emd | R1bR2 | Ru | false | Ru_La | 1.44 | R2: 1.4 × L_D < 3 |
| SI HAADF 1735.emd | R1bR2 | Rh | false | Rh_La | 1.14 | R2: 1.1 × L_D < 3 |
| SI HAADF 1735.emd | R1bR2 | Ce | false | Ce_La | 1.11 | R2: 1.1 × L_D < 3 |
| SI HAADF 1735.emd | R1bR2 | Rb | false | Rb_La | 1.05 | R2: 1.0 × L_D < 3 |
| SI HAADF 1738.emd | R2 | Tm | false | Tm_Ma | 2.43 | R2: 2.4 × L_D < 3 |
| SI HAADF 1738.emd | R2 | Ru | false | Ru_La | 1.50 | R2: 1.5 × L_D < 3 |
| SI HAADF 1738.emd | R2 | Rh | false | Rh_La | 1.22 | R2: 1.2 × L_D < 3 |
| SI HAADF 1738.emd | R2 | Ce | false | Ce_La | 1.16 | R2: 1.2 × L_D < 3 |
| SI HAADF 1738.emd | R1bR2 | Tm | false | Tm_Ma | 2.43 | R2: 2.4 × L_D < 3 |
| SI HAADF 1738.emd | R1bR2 | Ru | false | Ru_La | 1.50 | R2: 1.5 × L_D < 3 |
| SI HAADF 1738.emd | R1bR2 | Rh | false | Rh_La | 1.22 | R2: 1.2 × L_D < 3 |
| SI HAADF 1738.emd | R1bR2 | Ce | false | Ce_La | 1.16 | R2: 1.2 × L_D < 3 |
| SI HAADF 1151.emd | R1b | Hf | false | Hf_La | 1.26 | R1: within 1.5 FWHM of Cu Kα, 1.3 × L_D ≤ 21.3 × L_D |
| SI HAADF 1151.emd | R2 | Hf | false | Hf_La | 1.26 | R2: 1.3 × L_D < 3 |
| SI HAADF 1151.emd | R2 | Ho | false | Ho_La | 1.06 | R2: 1.1 × L_D < 3 |
| SI HAADF 1151.emd | R1bR2 | Hf | false | Hf_La | 1.26 | R1: within 1.5 FWHM of Cu Kα, 1.3 × L_D ≤ 21.3 × L_D |
| SI HAADF 1151.emd | R1bR2 | Ho | false | Ho_La | 1.06 | R2: 1.1 × L_D < 3 |
| SI HAADF 1315.emd | R1b | Hf | false | Hf_La | 2.52 | R1: within 1.5 FWHM of Cu Kα, 2.5 × L_D ≤ 77.8 × L_D |
| SI HAADF 1315.emd | R2 | Hf | false | Hf_La | 2.52 | R2: 2.5 × L_D < 3 |
| SI HAADF 1315.emd | R2 | Y | false | Y_La | 1.30 | R2: 1.3 × L_D < 3 |
| SI HAADF 1315.emd | R2 | Ho | false | Ho_La | 1.11 | R2: 1.1 × L_D < 3 |
| SI HAADF 1315.emd | R1bR2 | Hf | false | Hf_La | 2.52 | R1: within 1.5 FWHM of Cu Kα, 2.5 × L_D ≤ 77.8 × L_D |
| SI HAADF 1315.emd | R1bR2 | Y | false | Y_La | 1.30 | R2: 1.3 × L_D < 3 |
| SI HAADF 1315.emd | R1bR2 | Ho | false | Ho_La | 1.11 | R2: 1.1 × L_D < 3 |
| SI HAADF 1339 65000 x 20260508.emd | R1b | Hf | false | Hf_La | 1.36 | R1: within 1.5 FWHM of Cu Kα, 1.4 × L_D ≤ 24.3 × L_D |
| SI HAADF 1339 65000 x 20260508.emd | R2 | Eu | false | Eu_La | 2.08 | R2: 2.1 × L_D < 3 |
| SI HAADF 1339 65000 x 20260508.emd | R2 | Hf | false | Hf_La | 1.36 | R2: 1.4 × L_D < 3 |
| SI HAADF 1339 65000 x 20260508.emd | R2 | Ho | false | Ho_La | 1.20 | R2: 1.2 × L_D < 3 |
| SI HAADF 1339 65000 x 20260508.emd | R1bR2 | Eu | false | Eu_La | 2.08 | R2: 2.1 × L_D < 3 |
| SI HAADF 1339 65000 x 20260508.emd | R1bR2 | Hf | false | Hf_La | 1.36 | R1: within 1.5 FWHM of Cu Kα, 1.4 × L_D ≤ 24.3 × L_D |
| SI HAADF 1339 65000 x 20260508.emd | R1bR2 | Ho | false | Ho_La | 1.20 | R2: 1.2 × L_D < 3 |
| SI HAADF 1840 23000 x 20260506.emd | R2 | Ho | false | Ho_La | 1.76 | R2: 1.8 × L_D < 3 |
| SI HAADF 1840 23000 x 20260506.emd | R2 | Ta | false | Ta_Ma | 1.51 | R2: 1.5 × L_D < 3 |
| SI HAADF 1840 23000 x 20260506.emd | R1bR2 | Ho | false | Ho_La | 1.76 | R2: 1.8 × L_D < 3 |
| SI HAADF 1840 23000 x 20260506.emd | R1bR2 | Ta | false | Ta_Ma | 1.51 | R2: 1.5 × L_D < 3 |
| SI HAADF 1909 11500 x 20260506.emd | R2 | Ho | false | Ho_La | 1.74 | R2: 1.7 × L_D < 3 |
| SI HAADF 1909 11500 x 20260506.emd | R2 | Ta | false | Ta_Ma | 1.47 | R2: 1.5 × L_D < 3 |
| SI HAADF 1909 11500 x 20260506.emd | R1bR2 | Ho | false | Ho_La | 1.74 | R2: 1.7 × L_D < 3 |
| SI HAADF 1909 11500 x 20260506.emd | R1bR2 | Ta | false | Ta_Ma | 1.47 | R2: 1.5 × L_D < 3 |
| SI HAADF 1949 91000 x 20260506.emd | R2 | Ho | false | Ho_La | 1.76 | R2: 1.8 × L_D < 3 |
| SI HAADF 1949 91000 x 20260506.emd | R2 | Ta | false | Ta_Ma | 1.20 | R2: 1.2 × L_D < 3 |
| SI HAADF 1949 91000 x 20260506.emd | R1bR2 | Ho | false | Ho_La | 1.76 | R2: 1.8 × L_D < 3 |
| SI HAADF 1949 91000 x 20260506.emd | R1bR2 | Ta | false | Ta_Ma | 1.20 | R2: 1.2 × L_D < 3 |
| SI HAADF 1312 11500 x 20260508.emd | R1b | Hf | false | Hf_La | 1.07 | R1: within 1.5 FWHM of Cu Kα, 1.1 × L_D ≤ 20.3 × L_D |
| SI HAADF 1312 11500 x 20260508.emd | R2 | Eu | false | Eu_La | 1.32 | R2: 1.3 × L_D < 3 |
| SI HAADF 1312 11500 x 20260508.emd | R2 | Ho | false | Ho_La | 1.11 | R2: 1.1 × L_D < 3 |
| SI HAADF 1312 11500 x 20260508.emd | R2 | Hf | false | Hf_La | 1.07 | R2: 1.1 × L_D < 3 |
| SI HAADF 1312 11500 x 20260508.emd | R1bR2 | Eu | false | Eu_La | 1.32 | R2: 1.3 × L_D < 3 |
| SI HAADF 1312 11500 x 20260508.emd | R1bR2 | Ho | false | Ho_La | 1.11 | R2: 1.1 × L_D < 3 |
| SI HAADF 1312 11500 x 20260508.emd | R1bR2 | Hf | false | Hf_La | 1.07 | R1: within 1.5 FWHM of Cu Kα, 1.1 × L_D ≤ 20.3 × L_D |
| SI HAADF 1402 23000 x 20260605.emd | R1b | Hf | false | Hf_La | 1.71 | R1: within 1.5 FWHM of Cu Kα, 1.7 × L_D ≤ 36.1 × L_D |
| SI HAADF 1402 23000 x 20260605.emd | R1b | V | false | V_La | 1.05 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 3.3 × L_D |
| SI HAADF 1402 23000 x 20260605.emd | R2 | Ta | false | Ta_Ma | 2.04 | R2: 2.0 × L_D < 3 |
| SI HAADF 1402 23000 x 20260605.emd | R2 | Hf | false | Hf_La | 1.71 | R2: 1.7 × L_D < 3 |
| SI HAADF 1402 23000 x 20260605.emd | R2 | V | false | V_La | 1.05 | R2: 1.1 × L_D < 3 |
| SI HAADF 1402 23000 x 20260605.emd | R2 | Eu | false | Eu_La | 1.04 | R2: 1.0 × L_D < 3 |
| SI HAADF 1402 23000 x 20260605.emd | R1bR2 | Ta | false | Ta_Ma | 2.04 | R2: 2.0 × L_D < 3 |
| SI HAADF 1402 23000 x 20260605.emd | R1bR2 | Hf | false | Hf_La | 1.71 | R1: within 1.5 FWHM of Cu Kα, 1.7 × L_D ≤ 36.1 × L_D |
| SI HAADF 1402 23000 x 20260605.emd | R1bR2 | V | false | V_La | 1.05 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 3.3 × L_D |
| SI HAADF 1402 23000 x 20260605.emd | R1bR2 | Eu | false | Eu_La | 1.04 | R2: 1.0 × L_D < 3 |
| SI HAADF 1438 33000 x 20260605.emd | R1b | V | false | V_La | 1.01 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 3.8 × L_D |
| SI HAADF 1438 33000 x 20260605.emd | R2 | Ho | false | Ho_La | 2.08 | R2: 2.1 × L_D < 3 |
| SI HAADF 1438 33000 x 20260605.emd | R2 | V | false | V_La | 1.01 | R2: 1.0 × L_D < 3 |
| SI HAADF 1438 33000 x 20260605.emd | R1bR2 | Ho | false | Ho_La | 2.08 | R2: 2.1 × L_D < 3 |
| SI HAADF 1438 33000 x 20260605.emd | R1bR2 | V | false | V_La | 1.01 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 3.8 × L_D |
| SI HAADF 1509 65000 x 20260605.emd | R1b | V | false | V_La | 1.11 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 4.3 × L_D |
| SI HAADF 1509 65000 x 20260605.emd | R2 | Ho | false | Ho_La | 1.98 | R2: 2.0 × L_D < 3 |
| SI HAADF 1509 65000 x 20260605.emd | R2 | V | false | V_La | 1.11 | R2: 1.1 × L_D < 3 |
| SI HAADF 1509 65000 x 20260605.emd | R1bR2 | Ho | false | Ho_La | 1.98 | R2: 2.0 × L_D < 3 |
| SI HAADF 1509 65000 x 20260605.emd | R1bR2 | V | false | V_La | 1.11 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 4.3 × L_D |
| SI HAADF 1534 16500 x 20260512.emd | R1b | Hf | false | Hf_La | 1.52 | R1: within 1.5 FWHM of Cu Kα, 1.5 × L_D ≤ 31.7 × L_D |
| SI HAADF 1534 16500 x 20260512.emd | R1b | V | false | V_La | 1.04 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 3.6 × L_D |
| SI HAADF 1534 16500 x 20260512.emd | R2 | Ta | false | Ta_Ma | 2.10 | R2: 2.1 × L_D < 3 |
| SI HAADF 1534 16500 x 20260512.emd | R2 | Hf | false | Hf_La | 1.52 | R2: 1.5 × L_D < 3 |
| SI HAADF 1534 16500 x 20260512.emd | R2 | V | false | V_La | 1.04 | R2: 1.0 × L_D < 3 |
| SI HAADF 1534 16500 x 20260512.emd | R1bR2 | Ta | false | Ta_Ma | 2.10 | R2: 2.1 × L_D < 3 |
| SI HAADF 1534 16500 x 20260512.emd | R1bR2 | Hf | false | Hf_La | 1.52 | R1: within 1.5 FWHM of Cu Kα, 1.5 × L_D ≤ 31.7 × L_D |
| SI HAADF 1534 16500 x 20260512.emd | R1bR2 | V | false | V_La | 1.04 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 3.6 × L_D |
| SI HAADF 1537 91000 x 20260605.emd | R1b | V | false | V_La | 1.28 | R1: within 1.5 FWHM of O Kα, 1.3 × L_D ≤ 4.0 × L_D |
| SI HAADF 1537 91000 x 20260605.emd | R2 | Ho | false | Ho_La | 1.94 | R2: 1.9 × L_D < 3 |
| SI HAADF 1537 91000 x 20260605.emd | R2 | V | false | V_La | 1.28 | R2: 1.3 × L_D < 3 |
| SI HAADF 1537 91000 x 20260605.emd | R1bR2 | Ho | false | Ho_La | 1.94 | R2: 1.9 × L_D < 3 |
| SI HAADF 1537 91000 x 20260605.emd | R1bR2 | V | false | V_La | 1.28 | R1: within 1.5 FWHM of O Kα, 1.3 × L_D ≤ 4.0 × L_D |
| SI HAADF 1549 11500 x 20260512.emd | R1b | Hf | false | Hf_La | 1.63 | R1: within 1.5 FWHM of Cu Kα, 1.6 × L_D ≤ 33.9 × L_D |
| SI HAADF 1549 11500 x 20260512.emd | R2 | Ta | false | Ta_Ma | 1.96 | R2: 2.0 × L_D < 3 |
| SI HAADF 1549 11500 x 20260512.emd | R2 | Hf | false | Hf_La | 1.63 | R2: 1.6 × L_D < 3 |
| SI HAADF 1549 11500 x 20260512.emd | R2 | Eu | false | Eu_La | 1.20 | R2: 1.2 × L_D < 3 |
| SI HAADF 1549 11500 x 20260512.emd | R1bR2 | Ta | false | Ta_Ma | 1.96 | R2: 2.0 × L_D < 3 |
| SI HAADF 1549 11500 x 20260512.emd | R1bR2 | Hf | false | Hf_La | 1.63 | R1: within 1.5 FWHM of Cu Kα, 1.6 × L_D ≤ 33.9 × L_D |
| SI HAADF 1549 11500 x 20260512.emd | R1bR2 | Eu | false | Eu_La | 1.20 | R2: 1.2 × L_D < 3 |
| SI HAADF 1606 130 kx 20260512.emd | R1b | V | false | V_La | 1.07 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 3.7 × L_D |
| SI HAADF 1606 130 kx 20260512.emd | R2 | Ho | false | Ho_La | 1.66 | R2: 1.7 × L_D < 3 |
| SI HAADF 1606 130 kx 20260512.emd | R2 | Ta | false | Ta_Ma | 1.08 | R2: 1.1 × L_D < 3 |
| SI HAADF 1606 130 kx 20260512.emd | R2 | V | false | V_La | 1.07 | R2: 1.1 × L_D < 3 |
| SI HAADF 1606 130 kx 20260512.emd | R1bR2 | Ho | false | Ho_La | 1.66 | R2: 1.7 × L_D < 3 |
| SI HAADF 1606 130 kx 20260512.emd | R1bR2 | Ta | false | Ta_Ma | 1.08 | R2: 1.1 × L_D < 3 |
| SI HAADF 1606 130 kx 20260512.emd | R1bR2 | V | false | V_La | 1.07 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 3.7 × L_D |
| SI HAADF 1623 91000 x 20260512.emd | R1b | Hf | false | Hf_La | 1.61 | R1: within 1.5 FWHM of Cu Kα, 1.6 × L_D ≤ 29.6 × L_D |
| SI HAADF 1623 91000 x 20260512.emd | R2 | Hf | false | Hf_La | 1.61 | R2: 1.6 × L_D < 3 |
| SI HAADF 1623 91000 x 20260512.emd | R1bR2 | Hf | false | Hf_La | 1.61 | R1: within 1.5 FWHM of Cu Kα, 1.6 × L_D ≤ 29.6 × L_D |
| SI HAADF 1633 46000 x 20260512.emd | R2 | Ta | false | Ta_Ma | 2.42 | R2: 2.4 × L_D < 3 |
| SI HAADF 1633 46000 x 20260512.emd | R2 | Ho | false | Ho_La | 2.03 | R2: 2.0 × L_D < 3 |
| SI HAADF 1633 46000 x 20260512.emd | R1bR2 | Ta | false | Ta_Ma | 2.42 | R2: 2.4 × L_D < 3 |
| SI HAADF 1633 46000 x 20260512.emd | R1bR2 | Ho | false | Ho_La | 2.03 | R2: 2.0 × L_D < 3 |
| SI HAADF 1006 65000 x 20260603.emd | R1b | Hf | false | Hf_La | 1.75 | R1: within 1.5 FWHM of Cu Kα, 1.8 × L_D ≤ 51.6 × L_D |
| SI HAADF 1006 65000 x 20260603.emd | R2 | Hf | false | Hf_La | 1.75 | R2: 1.8 × L_D < 3 |
| SI HAADF 1006 65000 x 20260603.emd | R2 | Ta | false | Ta_Ma | 1.44 | R2: 1.4 × L_D < 3 |
| SI HAADF 1006 65000 x 20260603.emd | R2 | Ho | false | Ho_La | 1.28 | R2: 1.3 × L_D < 3 |
| SI HAADF 1006 65000 x 20260603.emd | R2 | Cs | false | Cs_La | 1.20 | R2: 1.2 × L_D < 3 |
| SI HAADF 1006 65000 x 20260603.emd | R1bR2 | Hf | false | Hf_La | 1.75 | R1: within 1.5 FWHM of Cu Kα, 1.8 × L_D ≤ 51.6 × L_D |
| SI HAADF 1006 65000 x 20260603.emd | R1bR2 | Ta | false | Ta_Ma | 1.44 | R2: 1.4 × L_D < 3 |
| SI HAADF 1006 65000 x 20260603.emd | R1bR2 | Ho | false | Ho_La | 1.28 | R2: 1.3 × L_D < 3 |
| SI HAADF 1006 65000 x 20260603.emd | R1bR2 | Cs | false | Cs_La | 1.20 | R2: 1.2 × L_D < 3 |
| SI HAADF 1038 91000 x 20260603.emd | R1b | Hf | false | Hf_La | 1.81 | R1: within 1.5 FWHM of Cu Kα, 1.8 × L_D ≤ 51.4 × L_D |
| SI HAADF 1038 91000 x 20260603.emd | R2 | Hf | false | Hf_La | 1.81 | R2: 1.8 × L_D < 3 |
| SI HAADF 1038 91000 x 20260603.emd | R2 | Ta | false | Ta_Ma | 1.38 | R2: 1.4 × L_D < 3 |
| SI HAADF 1038 91000 x 20260603.emd | R2 | Cs | false | Cs_La | 1.38 | R2: 1.4 × L_D < 3 |
| SI HAADF 1038 91000 x 20260603.emd | R2 | Ho | false | Ho_La | 1.38 | R2: 1.4 × L_D < 3 |
| SI HAADF 1038 91000 x 20260603.emd | R1bR2 | Hf | false | Hf_La | 1.81 | R1: within 1.5 FWHM of Cu Kα, 1.8 × L_D ≤ 51.4 × L_D |
| SI HAADF 1038 91000 x 20260603.emd | R1bR2 | Ta | false | Ta_Ma | 1.38 | R2: 1.4 × L_D < 3 |
| SI HAADF 1038 91000 x 20260603.emd | R1bR2 | Cs | false | Cs_La | 1.38 | R2: 1.4 × L_D < 3 |
| SI HAADF 1038 91000 x 20260603.emd | R1bR2 | Ho | false | Ho_La | 1.38 | R2: 1.4 × L_D < 3 |
| SI HAADF 1052 33000 x 20260605.emd | R1b | V | false | V_La | 1.33 | R1: within 1.5 FWHM of O Kα, 1.3 × L_D ≤ 3.1 × L_D |
| SI HAADF 1052 33000 x 20260605.emd | R2 | Ta | false | Ta_Ma | 2.01 | R2: 2.0 × L_D < 3 |
| SI HAADF 1052 33000 x 20260605.emd | R2 | Ho | false | Ho_La | 1.89 | R2: 1.9 × L_D < 3 |
| SI HAADF 1052 33000 x 20260605.emd | R2 | V | false | V_La | 1.33 | R2: 1.3 × L_D < 3 |
| SI HAADF 1052 33000 x 20260605.emd | R1bR2 | Ta | false | Ta_Ma | 2.01 | R2: 2.0 × L_D < 3 |
| SI HAADF 1052 33000 x 20260605.emd | R1bR2 | Ho | false | Ho_La | 1.89 | R2: 1.9 × L_D < 3 |
| SI HAADF 1052 33000 x 20260605.emd | R1bR2 | V | false | V_La | 1.33 | R1: within 1.5 FWHM of O Kα, 1.3 × L_D ≤ 3.1 × L_D |
| SI HAADF 1122 130 kx 20260603.emd | R2 | Ho | false | Ho_La | 1.95 | R2: 1.9 × L_D < 3 |
| SI HAADF 1122 130 kx 20260603.emd | R2 | Ta | false | Ta_Ma | 1.81 | R2: 1.8 × L_D < 3 |
| SI HAADF 1122 130 kx 20260603.emd | R1bR2 | Ho | false | Ho_La | 1.95 | R2: 1.9 × L_D < 3 |
| SI HAADF 1122 130 kx 20260603.emd | R1bR2 | Ta | false | Ta_Ma | 1.81 | R2: 1.8 × L_D < 3 |
| SI HAADF 1129 23000 x 20260605.emd | R1b | V | false | V_La | 1.56 | R1: within 1.5 FWHM of O Kα, 1.6 × L_D ≤ 4.1 × L_D |
| SI HAADF 1129 23000 x 20260605.emd | R2 | Ta | false | Ta_Ma | 2.04 | R2: 2.0 × L_D < 3 |
| SI HAADF 1129 23000 x 20260605.emd | R2 | Ho | false | Ho_La | 1.92 | R2: 1.9 × L_D < 3 |
| SI HAADF 1129 23000 x 20260605.emd | R2 | V | false | V_La | 1.56 | R2: 1.6 × L_D < 3 |
| SI HAADF 1129 23000 x 20260605.emd | R1bR2 | Ta | false | Ta_Ma | 2.04 | R2: 2.0 × L_D < 3 |
| SI HAADF 1129 23000 x 20260605.emd | R1bR2 | Ho | false | Ho_La | 1.92 | R2: 1.9 × L_D < 3 |
| SI HAADF 1129 23000 x 20260605.emd | R1bR2 | V | false | V_La | 1.56 | R1: within 1.5 FWHM of O Kα, 1.6 × L_D ≤ 4.1 × L_D |
| SI HAADF 1653 33000 x 20260423.emd | R1b | Rb | false | Rb_La | 2.68 | R1: within 1.5 FWHM of Si Kα, 2.7 × L_D ≤ 22.4 × L_D |
| SI HAADF 1653 33000 x 20260423.emd | R1b | V | false | V_La | 1.81 | R1: within 1.5 FWHM of O Kα, 1.8 × L_D ≤ 5.9 × L_D |
| SI HAADF 1653 33000 x 20260423.emd | R1b | Re | false | Re_Ma | 1.27 | R1: within 1.5 FWHM of Si Kα, 1.3 × L_D ≤ 22.4 × L_D |
| SI HAADF 1653 33000 x 20260423.emd | R2 | Rb | false | Rb_La | 2.68 | R2: 2.7 × L_D < 3 |
| SI HAADF 1653 33000 x 20260423.emd | R2 | V | false | V_La | 1.81 | R2: 1.8 × L_D < 3 |
| SI HAADF 1653 33000 x 20260423.emd | R2 | Ho | false | Ho_La | 1.68 | R2: 1.7 × L_D < 3 |
| SI HAADF 1653 33000 x 20260423.emd | R2 | Re | false | Re_Ma | 1.27 | R2: 1.3 × L_D < 3 |
| SI HAADF 1653 33000 x 20260423.emd | R1bR2 | Rb | false | Rb_La | 2.68 | R1: within 1.5 FWHM of Si Kα, 2.7 × L_D ≤ 22.4 × L_D |
| SI HAADF 1653 33000 x 20260423.emd | R1bR2 | V | false | V_La | 1.81 | R1: within 1.5 FWHM of O Kα, 1.8 × L_D ≤ 5.9 × L_D |
| SI HAADF 1653 33000 x 20260423.emd | R1bR2 | Ho | false | Ho_La | 1.68 | R2: 1.7 × L_D < 3 |
| SI HAADF 1653 33000 x 20260423.emd | R1bR2 | Re | false | Re_Ma | 1.27 | R1: within 1.5 FWHM of Si Kα, 1.3 × L_D ≤ 22.4 × L_D |
| SI HAADF 1727 46000 x 20260422.emd | R1b | Ta | false | Ta_Ma | 1.67 | R1: within 1.5 FWHM of Si Kα, 1.7 × L_D ≤ 6.7 × L_D |
| SI HAADF 1727 46000 x 20260422.emd | R1b | Hf | false | Hf_La | 1.64 | R1: within 1.5 FWHM of Cu Kα, 1.6 × L_D ≤ 40.1 × L_D |
| SI HAADF 1727 46000 x 20260422.emd | R1b | V | false | V_La | 1.59 | R1: within 1.5 FWHM of O Kα, 1.6 × L_D ≤ 2.9 × L_D |
| SI HAADF 1727 46000 x 20260422.emd | R2 | Ta | false | Ta_Ma | 1.67 | R2: 1.7 × L_D < 3 |
| SI HAADF 1727 46000 x 20260422.emd | R2 | Hf | false | Hf_La | 1.64 | R2: 1.6 × L_D < 3 |
| SI HAADF 1727 46000 x 20260422.emd | R2 | V | false | V_La | 1.59 | R2: 1.6 × L_D < 3 |
| SI HAADF 1727 46000 x 20260422.emd | R2 | Ba | false | Ba_La | 1.09 | R2: 1.1 × L_D < 3 |
| SI HAADF 1727 46000 x 20260422.emd | R1bR2 | Ta | false | Ta_Ma | 1.67 | R1: within 1.5 FWHM of Si Kα, 1.7 × L_D ≤ 6.7 × L_D |
| SI HAADF 1727 46000 x 20260422.emd | R1bR2 | Hf | false | Hf_La | 1.64 | R1: within 1.5 FWHM of Cu Kα, 1.6 × L_D ≤ 40.1 × L_D |
| SI HAADF 1727 46000 x 20260422.emd | R1bR2 | V | false | V_La | 1.59 | R1: within 1.5 FWHM of O Kα, 1.6 × L_D ≤ 2.9 × L_D |
| SI HAADF 1727 46000 x 20260422.emd | R1bR2 | Ba | false | Ba_La | 1.09 | R2: 1.1 × L_D < 3 |
| SI HAADF 1742 23000 x 20260422.emd | R1b | Rb | false | Rb_La | 1.88 | R1: within 1.5 FWHM of Si Kα, 1.9 × L_D ≤ 23.3 × L_D |
| SI HAADF 1742 23000 x 20260422.emd | R1b | Ba | false | Ba_La | 1.84 | R1: within 1.5 FWHM of Ti Kα, 1.8 × L_D ≤ 15.4 × L_D |
| SI HAADF 1742 23000 x 20260422.emd | R1b | Hf | false | Hf_La | 1.36 | R1: within 1.5 FWHM of Cu Kα, 1.4 × L_D ≤ 31.7 × L_D |
| SI HAADF 1742 23000 x 20260422.emd | R2 | Rb | false | Rb_La | 1.88 | R2: 1.9 × L_D < 3 |
| SI HAADF 1742 23000 x 20260422.emd | R2 | Ba | false | Ba_La | 1.84 | R2: 1.8 × L_D < 3 |
| SI HAADF 1742 23000 x 20260422.emd | R2 | Hf | false | Hf_La | 1.36 | R2: 1.4 × L_D < 3 |
| SI HAADF 1742 23000 x 20260422.emd | R1bR2 | Rb | false | Rb_La | 1.88 | R1: within 1.5 FWHM of Si Kα, 1.9 × L_D ≤ 23.3 × L_D |
| SI HAADF 1742 23000 x 20260422.emd | R1bR2 | Ba | false | Ba_La | 1.84 | R1: within 1.5 FWHM of Ti Kα, 1.8 × L_D ≤ 15.4 × L_D |
| SI HAADF 1742 23000 x 20260422.emd | R1bR2 | Hf | false | Hf_La | 1.36 | R1: within 1.5 FWHM of Cu Kα, 1.4 × L_D ≤ 31.7 × L_D |
| SI HAADF 1759 185 kx 20260422.emd | R1b | V | false | V_La | 1.63 | R1: within 1.5 FWHM of O Kα, 1.6 × L_D ≤ 3.0 × L_D |
| SI HAADF 1759 185 kx 20260422.emd | R2 | V | false | V_La | 1.63 | R2: 1.6 × L_D < 3 |
| SI HAADF 1759 185 kx 20260422.emd | R2 | Ba | false | Ba_La | 1.06 | R2: 1.1 × L_D < 3 |
| SI HAADF 1759 185 kx 20260422.emd | R2 | Cs | false | Cs_La | 1.03 | R2: 1.0 × L_D < 3 |
| SI HAADF 1759 185 kx 20260422.emd | R1bR2 | V | false | V_La | 1.63 | R1: within 1.5 FWHM of O Kα, 1.6 × L_D ≤ 3.0 × L_D |
| SI HAADF 1759 185 kx 20260422.emd | R1bR2 | Ba | false | Ba_La | 1.06 | R2: 1.1 × L_D < 3 |
| SI HAADF 1759 185 kx 20260422.emd | R1bR2 | Cs | false | Cs_La | 1.03 | R2: 1.0 × L_D < 3 |
| SI HAADF 1804 23000 x 20260423.emd | R1b | Pt | false | Pt_La | 3.62 | R1: within 1.5 FWHM of Ga Kα, 3.6 × L_D ≤ 6.6 × L_D |
| SI HAADF 1804 23000 x 20260423.emd | R1b | V | false | V_La | 1.13 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 3.0 × L_D |
| SI HAADF 1804 23000 x 20260423.emd | R2 | V | false | V_La | 1.13 | R2: 1.1 × L_D < 3 |
| SI HAADF 1804 23000 x 20260423.emd | R1bR2 | Pt | false | Pt_La | 3.62 | R1: within 1.5 FWHM of Ga Kα, 3.6 × L_D ≤ 6.6 × L_D |
| SI HAADF 1804 23000 x 20260423.emd | R1bR2 | V | false | V_La | 1.13 | R1: within 1.5 FWHM of O Kα, 1.1 × L_D ≤ 3.0 × L_D |
| SI HAADF 1441 71000 x 20260420.emd | R1b | Yb | false | Yb_La | 1.24 | R1: within 1.5 FWHM of Ni Kα, 1.2 × L_D ≤ 7.0 × L_D |
| SI HAADF 1441 71000 x 20260420.emd | R2 | Yb | false | Yb_La | 1.24 | R2: 1.2 × L_D < 3 |
| SI HAADF 1441 71000 x 20260420.emd | R1bR2 | Yb | false | Yb_La | 1.24 | R1: within 1.5 FWHM of Ni Kα, 1.2 × L_D ≤ 7.0 × L_D |
| SI HAADF 1456 77000 x 20260420.emd | R1b | Yb | false | Yb_La | 1.60 | R1: within 1.5 FWHM of Ni Kα, 1.6 × L_D ≤ 5.1 × L_D |
| SI HAADF 1456 77000 x 20260420.emd | R1b | V | false | V_La | 1.02 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 1.9 × L_D |
| SI HAADF 1456 77000 x 20260420.emd | R2 | Yb | false | Yb_La | 1.60 | R2: 1.6 × L_D < 3 |
| SI HAADF 1456 77000 x 20260420.emd | R2 | V | false | V_La | 1.02 | R2: 1.0 × L_D < 3 |
| SI HAADF 1456 77000 x 20260420.emd | R1bR2 | Yb | false | Yb_La | 1.60 | R1: within 1.5 FWHM of Ni Kα, 1.6 × L_D ≤ 5.1 × L_D |
| SI HAADF 1456 77000 x 20260420.emd | R1bR2 | V | false | V_La | 1.02 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 1.9 × L_D |
| SI HAADF 1549.emd | R1b | Nd | false | Nd_La | 1.40 | R1: within 1.5 FWHM of Cr Kα, 1.4 × L_D ≤ 2.0 × L_D |
| SI HAADF 1549.emd | R2 | Pt | TRUE | Pt_Ma | 2.76 | R2: 2.8 × L_D < 3 |
| SI HAADF 1549.emd | R2 | Cs | false | Cs_La | 1.58 | R2: 1.6 × L_D < 3 |
| SI HAADF 1549.emd | R2 | Nd | false | Nd_La | 1.40 | R2: 1.4 × L_D < 3 |
| SI HAADF 1549.emd | R1bR2 | Pt | TRUE | Pt_Ma | 2.76 | R2: 2.8 × L_D < 3 |
| SI HAADF 1549.emd | R1bR2 | Cs | false | Cs_La | 1.58 | R2: 1.6 × L_D < 3 |
| SI HAADF 1549.emd | R1bR2 | Nd | false | Nd_La | 1.40 | R1: within 1.5 FWHM of Cr Kα, 1.4 × L_D ≤ 2.0 × L_D |
| SI HAADF 1206 33000 x.emd | R2 | Ho | false | Ho_La | 1.31 | R2: 1.3 × L_D < 3 |
| SI HAADF 1206 33000 x.emd | R1bR2 | Ho | false | Ho_La | 1.31 | R2: 1.3 × L_D < 3 |
| SI HAADF 1211 23000 x.emd | R1b | Ru | false | Ru_La | 1.23 | R1: within 1.5 FWHM of Cl Kα, 1.2 × L_D ≤ 9.7 × L_D |
| SI HAADF 1211 23000 x.emd | R1b | Hf | false | Hf_La | 1.16 | R1: within 1.5 FWHM of Cu Kα, 1.2 × L_D ≤ 28.9 × L_D |
| SI HAADF 1211 23000 x.emd | R1b | As | false | As_La | 1.05 | R1: within 1.5 FWHM of Mg Kα, 1.0 × L_D ≤ 1.4 × L_D |
| SI HAADF 1211 23000 x.emd | R2 | Ru | false | Ru_La | 1.23 | R2: 1.2 × L_D < 3 |
| SI HAADF 1211 23000 x.emd | R2 | Hf | false | Hf_La | 1.16 | R2: 1.2 × L_D < 3 |
| SI HAADF 1211 23000 x.emd | R2 | As | false | As_La | 1.05 | R2: 1.0 × L_D < 3 |
| SI HAADF 1211 23000 x.emd | R1bR2 | Ru | false | Ru_La | 1.23 | R1: within 1.5 FWHM of Cl Kα, 1.2 × L_D ≤ 9.7 × L_D |
| SI HAADF 1211 23000 x.emd | R1bR2 | Hf | false | Hf_La | 1.16 | R1: within 1.5 FWHM of Cu Kα, 1.2 × L_D ≤ 28.9 × L_D |
| SI HAADF 1211 23000 x.emd | R1bR2 | As | false | As_La | 1.05 | R1: within 1.5 FWHM of Mg Kα, 1.0 × L_D ≤ 1.4 × L_D |
| SI HAADF 1425 16500 x.emd | R1b | Sb | false | Sb_La | 1.15 | R1: within 1.5 FWHM of Ca Kα, 1.2 × L_D ≤ 6.1 × L_D |
| SI HAADF 1425 16500 x.emd | R1b | V | false | V_La | 1.04 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 4.0 × L_D |
| SI HAADF 1425 16500 x.emd | R2 | Tb | false | Tb_Ma | 2.78 | R2: 2.8 × L_D < 3 |
| SI HAADF 1425 16500 x.emd | R2 | Ba | false | Ba_La | 1.57 | R2: 1.6 × L_D < 3 |
| SI HAADF 1425 16500 x.emd | R2 | Sb | false | Sb_La | 1.15 | R2: 1.2 × L_D < 3 |
| SI HAADF 1425 16500 x.emd | R2 | V | false | V_La | 1.04 | R2: 1.0 × L_D < 3 |
| SI HAADF 1425 16500 x.emd | R1bR2 | Tb | false | Tb_Ma | 2.78 | R2: 2.8 × L_D < 3 |
| SI HAADF 1425 16500 x.emd | R1bR2 | Ba | false | Ba_La | 1.57 | R2: 1.6 × L_D < 3 |
| SI HAADF 1425 16500 x.emd | R1bR2 | Sb | false | Sb_La | 1.15 | R1: within 1.5 FWHM of Ca Kα, 1.2 × L_D ≤ 6.1 × L_D |
| SI HAADF 1425 16500 x.emd | R1bR2 | V | false | V_La | 1.04 | R1: within 1.5 FWHM of O Kα, 1.0 × L_D ≤ 4.0 × L_D |
| SI HAADF 1138.emd | R1b | Hf | false | Hf_La | 1.03 | R1: within 1.5 FWHM of Cu Kα, 1.0 × L_D ≤ 39.9 × L_D |
| SI HAADF 1138.emd | R2 | Hf | false | Hf_La | 1.03 | R2: 1.0 × L_D < 3 |
| SI HAADF 1138.emd | R1bR2 | Hf | false | Hf_La | 1.03 | R1: within 1.5 FWHM of Cu Kα, 1.0 × L_D ≤ 39.9 × L_D |
| SI HAADF 1318.emd | R2 | Ho | false | Ho_La | 1.50 | R2: 1.5 × L_D < 3 |
| SI HAADF 1318.emd | R2 | Au | false | Au_Ma | 1.44 | R2: 1.4 × L_D < 3 |
| SI HAADF 1318.emd | R1bR2 | Ho | false | Ho_La | 1.50 | R2: 1.5 × L_D < 3 |
| SI HAADF 1318.emd | R1bR2 | Au | false | Au_Ma | 1.44 | R2: 1.4 × L_D < 3 |
| SI HAADF 1432.emd | R1b | Bi | false | Bi_Ma | 1.04 | R1: within 1.5 FWHM of S Kα, 1.0 × L_D ≤ 7.8 × L_D |
| SI HAADF 1432.emd | R2 | Ho | false | Ho_La | 2.34 | R2: 2.3 × L_D < 3 |
| SI HAADF 1432.emd | R2 | Bi | false | Bi_Ma | 1.04 | R2: 1.0 × L_D < 3 |
| SI HAADF 1432.emd | R1bR2 | Ho | false | Ho_La | 2.34 | R2: 2.3 × L_D < 3 |
| SI HAADF 1432.emd | R1bR2 | Bi | false | Bi_Ma | 1.04 | R1: within 1.5 FWHM of S Kα, 1.0 × L_D ≤ 7.8 × L_D |
| SI HAADF 1436.emd | R2 | Ho | false | Ho_La | 2.41 | R2: 2.4 × L_D < 3 |
| SI HAADF 1436.emd | R1bR2 | Ho | false | Ho_La | 2.41 | R2: 2.4 × L_D < 3 |
| SI HAADF 1437.emd | R2 | Ho | false | Ho_La | 2.17 | R2: 2.2 × L_D < 3 |
| SI HAADF 1437.emd | R1bR2 | Ho | false | Ho_La | 2.17 | R2: 2.2 × L_D < 3 |
| SI HAADF 1448.emd | R2 | Ho | false | Ho_La | 2.07 | R2: 2.1 × L_D < 3 |
| SI HAADF 1448.emd | R1bR2 | Ho | false | Ho_La | 2.07 | R2: 2.1 × L_D < 3 |
| SI HAADF 0912.emd | R1b | Hf | false | Hf_La | 1.31 | R1: within 1.5 FWHM of Cu Kα, 1.3 × L_D ≤ 31.9 × L_D |
| SI HAADF 0912.emd | R2 | Ho | false | Ho_La | 1.88 | R2: 1.9 × L_D < 3 |
| SI HAADF 0912.emd | R2 | Hf | false | Hf_La | 1.31 | R2: 1.3 × L_D < 3 |
| SI HAADF 0912.emd | R1bR2 | Ho | false | Ho_La | 1.88 | R2: 1.9 × L_D < 3 |
| SI HAADF 0912.emd | R1bR2 | Hf | false | Hf_La | 1.31 | R1: within 1.5 FWHM of Cu Kα, 1.3 × L_D ≤ 31.9 × L_D |
| SI HAADF 1024.emd | R1b | Hf | false | Hf_La | 1.81 | R1: within 1.5 FWHM of Cu Kα, 1.8 × L_D ≤ 98.0 × L_D |
| SI HAADF 1024.emd | R1b | Sb | false | Sb_La | 1.23 | R1: within 1.5 FWHM of Ca Kα, 1.2 × L_D ≤ 37.0 × L_D |
| SI HAADF 1024.emd | R2 | Hf | false | Hf_La | 1.81 | R2: 1.8 × L_D < 3 |
| SI HAADF 1024.emd | R2 | Sb | false | Sb_La | 1.23 | R2: 1.2 × L_D < 3 |
| SI HAADF 1024.emd | R2 | Ho | false | Ho_La | 1.02 | R2: 1.0 × L_D < 3 |
| SI HAADF 1024.emd | R1bR2 | Hf | false | Hf_La | 1.81 | R1: within 1.5 FWHM of Cu Kα, 1.8 × L_D ≤ 98.0 × L_D |
| SI HAADF 1024.emd | R1bR2 | Sb | false | Sb_La | 1.23 | R1: within 1.5 FWHM of Ca Kα, 1.2 × L_D ≤ 37.0 × L_D |
| SI HAADF 1024.emd | R1bR2 | Ho | false | Ho_La | 1.02 | R2: 1.0 × L_D < 3 |
| SI HAADF 1038.emd | R2 | Ho | false | Ho_La | 2.51 | R2: 2.5 × L_D < 3 |
| SI HAADF 1038.emd | R1bR2 | Ho | false | Ho_La | 2.51 | R2: 2.5 × L_D < 3 |
| SI HAADF 1020.emd | R2 | Ge | TRUE | Ge_La | 2.45 | R2: 2.5 × L_D < 3 |
| SI HAADF 1020.emd | R1bR2 | Ge | TRUE | Ge_La | 2.45 | R2: 2.5 × L_D < 3 |
| SI HAADF 1100.emd | R2 | Ni | TRUE | Ni_La | 2.20 | R2: 2.2 × L_D < 3 |
| SI HAADF 1100.emd | R2 | Ce | false | Ce_Ma | 2.06 | R2: 2.1 × L_D < 3 |
| SI HAADF 1100.emd | R1bR2 | Ni | TRUE | Ni_La | 2.20 | R2: 2.2 × L_D < 3 |
| SI HAADF 1100.emd | R1bR2 | Ce | false | Ce_Ma | 2.06 | R2: 2.1 × L_D < 3 |
| SI HAADF 1253.emd | R2 | Eu | false | Eu_Ma | 1.90 | R2: 1.9 × L_D < 3 |
| SI HAADF 1253.emd | R2 | In | TRUE | In_La | 1.36 | R2: 1.4 × L_D < 3 |
| SI HAADF 1253.emd | R1bR2 | Eu | false | Eu_Ma | 1.90 | R2: 1.9 × L_D < 3 |
| SI HAADF 1253.emd | R1bR2 | In | TRUE | In_La | 1.36 | R2: 1.4 × L_D < 3 |
| SI HAADF 1312.emd | R2 | Ce | false | Ce_Ma | 2.06 | R2: 2.1 × L_D < 3 |
| SI HAADF 1312.emd | R1bR2 | Ce | false | Ce_Ma | 2.06 | R2: 2.1 × L_D < 3 |
| SI HAADF 1633.emd | R2 | Pb | false | Pb_La | 1.97 | R2: 2.0 × L_D < 3 |
| SI HAADF 1633.emd | R1bR2 | Pb | false | Pb_La | 1.97 | R2: 2.0 × L_D < 3 |
| SI HAADF 1105.emd | R1b | V | false | V_La | 1.59 | R1: within 1.5 FWHM of O Kα, 1.6 × L_D ≤ 1.8 × L_D |
| SI HAADF 1105.emd | R1b | Hf | false | Hf_La | 1.38 | R1: within 1.5 FWHM of Cu Kα, 1.4 × L_D ≤ 24.4 × L_D |
| SI HAADF 1105.emd | R2 | V | false | V_La | 1.59 | R2: 1.6 × L_D < 3 |
| SI HAADF 1105.emd | R2 | Hf | false | Hf_La | 1.38 | R2: 1.4 × L_D < 3 |
| SI HAADF 1105.emd | R1bR2 | V | false | V_La | 1.59 | R1: within 1.5 FWHM of O Kα, 1.6 × L_D ≤ 1.8 × L_D |
| SI HAADF 1105.emd | R1bR2 | Hf | false | Hf_La | 1.38 | R1: within 1.5 FWHM of Cu Kα, 1.4 × L_D ≤ 24.4 × L_D |
| SI HAADF 1146.emd | R1b | Hf | false | Hf_La | 1.39 | R1: within 1.5 FWHM of Cu Kα, 1.4 × L_D ≤ 24.4 × L_D |
| SI HAADF 1146.emd | R1b | V | false | V_La | 1.32 | R1: within 1.5 FWHM of O Kα, 1.3 × L_D ≤ 3.8 × L_D |
| SI HAADF 1146.emd | R2 | Ta | false | Ta_Ma | 2.10 | R2: 2.1 × L_D < 3 |
| SI HAADF 1146.emd | R2 | Hf | false | Hf_La | 1.39 | R2: 1.4 × L_D < 3 |
| SI HAADF 1146.emd | R2 | V | false | V_La | 1.32 | R2: 1.3 × L_D < 3 |
| SI HAADF 1146.emd | R1bR2 | Ta | false | Ta_Ma | 2.10 | R2: 2.1 × L_D < 3 |
| SI HAADF 1146.emd | R1bR2 | Hf | false | Hf_La | 1.39 | R1: within 1.5 FWHM of Cu Kα, 1.4 × L_D ≤ 24.4 × L_D |
| SI HAADF 1146.emd | R1bR2 | V | false | V_La | 1.32 | R1: within 1.5 FWHM of O Kα, 1.3 × L_D ≤ 3.8 × L_D |
| SI HAADF 1248.emd | R2 | Dy | false | Dy_La | 2.95 | R2: 2.9 × L_D < 3 |
| SI HAADF 1248.emd | R2 | Nd | false | Nd_La | 1.96 | R2: 2.0 × L_D < 3 |
| SI HAADF 1248.emd | R2 | I | false | I_La | 1.54 | R2: 1.5 × L_D < 3 |
| SI HAADF 1248.emd | R2 | Pd | false | Pd_La | 1.21 | R2: 1.2 × L_D < 3 |
| SI HAADF 1248.emd | R1bR2 | Dy | false | Dy_La | 2.95 | R2: 2.9 × L_D < 3 |
| SI HAADF 1248.emd | R1bR2 | Nd | false | Nd_La | 1.96 | R2: 2.0 × L_D < 3 |
| SI HAADF 1248.emd | R1bR2 | I | false | I_La | 1.54 | R2: 1.5 × L_D < 3 |
| SI HAADF 1248.emd | R1bR2 | Pd | false | Pd_La | 1.21 | R2: 1.2 × L_D < 3 |
| SI HAADF 1304.emd | R2 | I | false | I_La | 2.16 | R2: 2.2 × L_D < 3 |
| SI HAADF 1304.emd | R2 | Pd | false | Pd_La | 1.11 | R2: 1.1 × L_D < 3 |
| SI HAADF 1304.emd | R1bR2 | I | false | I_La | 2.16 | R2: 2.2 × L_D < 3 |
| SI HAADF 1304.emd | R1bR2 | Pd | false | Pd_La | 1.11 | R2: 1.1 × L_D < 3 |
| SI HAADF 1221.emd | R1b | Hf | false | Hf_La | 1.42 | R1: within 1.5 FWHM of Cu Kα, 1.4 × L_D ≤ 47.1 × L_D |
| SI HAADF 1221.emd | R1b | Ta | false | Ta_Ma | 1.00 | R1: within 1.5 FWHM of Si Kα, 1.0 × L_D ≤ 3.1 × L_D |
| SI HAADF 1221.emd | R2 | Hf | false | Hf_La | 1.42 | R2: 1.4 × L_D < 3 |
| SI HAADF 1221.emd | R2 | Ta | false | Ta_Ma | 1.00 | R2: 1.0 × L_D < 3 |
| SI HAADF 1221.emd | R1bR2 | Hf | false | Hf_La | 1.42 | R1: within 1.5 FWHM of Cu Kα, 1.4 × L_D ≤ 47.1 × L_D |
| SI HAADF 1221.emd | R1bR2 | Ta | false | Ta_Ma | 1.00 | R1: within 1.5 FWHM of Si Kα, 1.0 × L_D ≤ 3.1 × L_D |
| SI HAADF 1225.emd | R1b | Hf | false | Hf_La | 1.29 | R1: within 1.5 FWHM of Cu Kα, 1.3 × L_D ≤ 38.1 × L_D |
| SI HAADF 1225.emd | R2 | Hf | false | Hf_La | 1.29 | R2: 1.3 × L_D < 3 |
| SI HAADF 1225.emd | R1bR2 | Hf | false | Hf_La | 1.29 | R1: within 1.5 FWHM of Cu Kα, 1.3 × L_D ≤ 38.1 × L_D |
| SI HAADF 1420.emd | R1b | Hf | false | Hf_La | 1.28 | R1: within 1.5 FWHM of Cu Kα, 1.3 × L_D ≤ 39.2 × L_D |
| SI HAADF 1420.emd | R2 | Hf | false | Hf_La | 1.28 | R2: 1.3 × L_D < 3 |
| SI HAADF 1420.emd | R1bR2 | Hf | false | Hf_La | 1.28 | R1: within 1.5 FWHM of Cu Kα, 1.3 × L_D ≤ 39.2 × L_D |
| SI HAADF 1435.emd | R1b | Hf | false | Hf_La | 1.36 | R1: within 1.5 FWHM of Cu Kα, 1.4 × L_D ≤ 44.5 × L_D |
| SI HAADF 1435.emd | R2 | Hf | false | Hf_La | 1.36 | R2: 1.4 × L_D < 3 |
| SI HAADF 1435.emd | R2 | Cd | false | Cd_La | 1.19 | R2: 1.2 × L_D < 3 |
| SI HAADF 1435.emd | R1bR2 | Hf | false | Hf_La | 1.36 | R1: within 1.5 FWHM of Cu Kα, 1.4 × L_D ≤ 44.5 × L_D |
| SI HAADF 1435.emd | R1bR2 | Cd | false | Cd_La | 1.19 | R2: 1.2 × L_D < 3 |
| SI HAADF 1658.emd | R2 | Ho | false | Ho_La | 2.18 | R2: 2.2 × L_D < 3 |
| SI HAADF 1658.emd | R1bR2 | Ho | false | Ho_La | 2.18 | R2: 2.2 × L_D < 3 |
| SI HAADF 1708.emd | R2 | Ho | false | Ho_La | 1.65 | R2: 1.7 × L_D < 3 |
| SI HAADF 1708.emd | R1bR2 | Ho | false | Ho_La | 1.65 | R2: 1.7 × L_D < 3 |
| SI HAADF 1721.emd | R1b | Hf | false | Hf_La | 1.10 | R1: within 1.5 FWHM of Cu Kα, 1.1 × L_D ≤ 64.9 × L_D |
| SI HAADF 1721.emd | R2 | Ho | false | Ho_La | 2.07 | R2: 2.1 × L_D < 3 |
| SI HAADF 1721.emd | R2 | Te | false | Te_La | 1.29 | R2: 1.3 × L_D < 3 |
| SI HAADF 1721.emd | R2 | Hf | false | Hf_La | 1.10 | R2: 1.1 × L_D < 3 |
| SI HAADF 1721.emd | R2 | Eu | false | Eu_La | 1.01 | R2: 1.0 × L_D < 3 |
| SI HAADF 1721.emd | R1bR2 | Ho | false | Ho_La | 2.07 | R2: 2.1 × L_D < 3 |
| SI HAADF 1721.emd | R1bR2 | Te | false | Te_La | 1.29 | R2: 1.3 × L_D < 3 |
| SI HAADF 1721.emd | R1bR2 | Hf | false | Hf_La | 1.10 | R1: within 1.5 FWHM of Cu Kα, 1.1 × L_D ≤ 64.9 × L_D |
| SI HAADF 1721.emd | R1bR2 | Eu | false | Eu_La | 1.01 | R2: 1.0 × L_D < 3 |
| SI HAADF 1729.emd | R2 | Ho | false | Ho_La | 2.10 | R2: 2.1 × L_D < 3 |
| SI HAADF 1729.emd | R1bR2 | Ho | false | Ho_La | 2.10 | R2: 2.1 × L_D < 3 |
| SI HAADF 1755.emd | R1b | Br | false | Br_La | 1.13 | R1: within 1.5 FWHM of Al Kα, 1.1 × L_D ≤ 2.7 × L_D |
| SI HAADF 1755.emd | R2 | Ho | false | Ho_La | 1.52 | R2: 1.5 × L_D < 3 |
| SI HAADF 1755.emd | R2 | Br | false | Br_La | 1.13 | R2: 1.1 × L_D < 3 |
| SI HAADF 1755.emd | R1bR2 | Ho | false | Ho_La | 1.52 | R2: 1.5 × L_D < 3 |
| SI HAADF 1755.emd | R1bR2 | Br | false | Br_La | 1.13 | R1: within 1.5 FWHM of Al Kα, 1.1 × L_D ≤ 2.7 × L_D |
| SI HAADF 1552.emd | R2 | Ho | false | Ho_La | 2.94 | R2: 2.9 × L_D < 3 |
| SI HAADF 1552.emd | R2 | Ba | false | Ba_La | 1.21 | R2: 1.2 × L_D < 3 |
| SI HAADF 1552.emd | R1bR2 | Ho | false | Ho_La | 2.94 | R2: 2.9 × L_D < 3 |
| SI HAADF 1552.emd | R1bR2 | Ba | false | Ba_La | 1.21 | R2: 1.2 × L_D < 3 |
| SI HAADF 1637.emd | R2 | Er | false | Er_La | 2.22 | R2: 2.2 × L_D < 3 |
| SI HAADF 1637.emd | R1bR2 | Er | false | Er_La | 2.22 | R2: 2.2 × L_D < 3 |
| SI HAADF 1410.emd | R2 | Rh | false | Rh_La | 1.16 | R2: 1.2 × L_D < 3 |
| SI HAADF 1410.emd | R1bR2 | Rh | false | Rh_La | 1.16 | R2: 1.2 × L_D < 3 |
| SI HAADF 1555.emd | R1b | W | false | W_Ma | 1.21 | R1: within 1.5 FWHM of Si Kα, 1.2 × L_D ≤ 5.2 × L_D |
| SI HAADF 1555.emd | R2 | W | false | W_Ma | 1.21 | R2: 1.2 × L_D < 3 |
| SI HAADF 1555.emd | R2 | Rh | false | Rh_La | 1.02 | R2: 1.0 × L_D < 3 |
| SI HAADF 1555.emd | R1bR2 | W | false | W_Ma | 1.21 | R1: within 1.5 FWHM of Si Kα, 1.2 × L_D ≤ 5.2 × L_D |
| SI HAADF 1555.emd | R1bR2 | Rh | false | Rh_La | 1.02 | R2: 1.0 × L_D < 3 |
| SI HAADF 1016.emd | R2 | Ga | false | Ga_La | 2.26 | R2: 2.3 × L_D < 3 |
| SI HAADF 1016.emd | R2 | Ce | false | Ce_La | 1.42 | R2: 1.4 × L_D < 3 |
| SI HAADF 1016.emd | R1bR2 | Ga | false | Ga_La | 2.26 | R2: 2.3 × L_D < 3 |
| SI HAADF 1016.emd | R1bR2 | Ce | false | Ce_La | 1.42 | R2: 1.4 × L_D < 3 |
| SI HAADF 1102.emd | R2 | Sb | false | Sb_La | 2.79 | R2: 2.8 × L_D < 3 |
| SI HAADF 1102.emd | R2 | Bi | false | Bi_La | 2.55 | R2: 2.5 × L_D < 3 |
| SI HAADF 1102.emd | R2 | Pr | false | Pr_Ma | 1.09 | R2: 1.1 × L_D < 3 |
| SI HAADF 1102.emd | R1bR2 | Sb | false | Sb_La | 2.79 | R2: 2.8 × L_D < 3 |
| SI HAADF 1102.emd | R1bR2 | Bi | false | Bi_La | 2.55 | R2: 2.5 × L_D < 3 |
| SI HAADF 1102.emd | R1bR2 | Pr | false | Pr_Ma | 1.09 | R2: 1.1 × L_D < 3 |
| SI HAADF 1029.emd | R1b | Rb | false | Rb_La | 2.34 | R1: within 1.5 FWHM of Si Kα, 2.3 × L_D ≤ 11.4 × L_D |
| SI HAADF 1029.emd | R1b | V | false | V_La | 1.86 | R1: within 1.5 FWHM of O Kα, 1.9 × L_D ≤ 2.5 × L_D |
| SI HAADF 1029.emd | R1b | Hf | false | Hf_La | 1.83 | R1: within 1.5 FWHM of Cu Kα, 1.8 × L_D ≤ 28.9 × L_D |
| SI HAADF 1029.emd | R2 | Rb | false | Rb_La | 2.34 | R2: 2.3 × L_D < 3 |
| SI HAADF 1029.emd | R2 | V | false | V_La | 1.86 | R2: 1.9 × L_D < 3 |
| SI HAADF 1029.emd | R2 | Hf | false | Hf_La | 1.83 | R2: 1.8 × L_D < 3 |
| SI HAADF 1029.emd | R1bR2 | Rb | false | Rb_La | 2.34 | R1: within 1.5 FWHM of Si Kα, 2.3 × L_D ≤ 11.4 × L_D |
| SI HAADF 1029.emd | R1bR2 | V | false | V_La | 1.86 | R1: within 1.5 FWHM of O Kα, 1.9 × L_D ≤ 2.5 × L_D |
| SI HAADF 1029.emd | R1bR2 | Hf | false | Hf_La | 1.83 | R1: within 1.5 FWHM of Cu Kα, 1.8 × L_D ≤ 28.9 × L_D |
| SI HAADF 1330.emd | R1b | Ba | false | Ba_La | 1.15 | R1: within 1.5 FWHM of Ti Kα, 1.1 × L_D ≤ 16.2 × L_D |
| SI HAADF 1330.emd | R1b | Ta | false | Ta_Ma | 1.02 | R1: within 1.5 FWHM of Si Kα, 1.0 × L_D ≤ 3.2 × L_D |
| SI HAADF 1330.emd | R2 | Zr | false | Zr_La | 2.27 | R2: 2.3 × L_D < 3 |
| SI HAADF 1330.emd | R2 | Ba | false | Ba_La | 1.15 | R2: 1.1 × L_D < 3 |
| SI HAADF 1330.emd | R2 | Ta | false | Ta_Ma | 1.02 | R2: 1.0 × L_D < 3 |
| SI HAADF 1330.emd | R1bR2 | Zr | false | Zr_La | 2.27 | R2: 2.3 × L_D < 3 |
| SI HAADF 1330.emd | R1bR2 | Ba | false | Ba_La | 1.15 | R1: within 1.5 FWHM of Ti Kα, 1.1 × L_D ≤ 16.2 × L_D |
| SI HAADF 1330.emd | R1bR2 | Ta | false | Ta_Ma | 1.02 | R1: within 1.5 FWHM of Si Kα, 1.0 × L_D ≤ 3.2 × L_D |

## The registered refuting observations, one by one (each is a count; the verdict is the reader's)
- H5 (a): true elements dropped by R1b on T-S pairs at ratio >= 1: 4
     Hf La + Cu Ka r1 low Hf 1.17 R1: within 1.5 FWHM of Cu Kα, 1.2 × L_D ≤ 1.5 × L_D
     Ta La + Cu Ka r1 high Ta 4.43 R1: within 1.5 FWHM of Cu Kα, 4.4 × L_D ≤ 4.5 × L_D
     Pt La + Ga Ka r1 low Pt 1.60 R1: within 1.5 FWHM of Ga Kα, 1.6 × L_D ≤ 2.2 × L_D
     Pt La + Ga Ka r1 high Pt 6.51 R1: within 1.5 FWHM of Ga Kα, 6.5 × L_D ≤ 7.3 × L_D
- H5 (b): true elements dropped by R1b at ratio 0.3 (admitted cost): 7
     Hf La + Cu Ka r0.3 low Hf 1.30 R1: within 1.5 FWHM of Cu Kα, 1.3 × L_D ≤ 3.7 × L_D
     Hf La + Cu Ka r0.3 high Hf 4.81 R1: within 1.5 FWHM of Cu Kα, 4.8 × L_D ≤ 10.0 × L_D
     Ta La + Cu Ka r0.3 low Ta 1.55 R1: within 1.5 FWHM of Cu Kα, 1.6 × L_D ≤ 4.4 × L_D
     Ta La + Cu Ka r0.3 high Ta 3.91 R1: within 1.5 FWHM of Cu Kα, 3.9 × L_D ≤ 13.8 × L_D
     Pt La + Ga Ka r0.3 low Pt 1.78 R1: within 1.5 FWHM of Ga Kα, 1.8 × L_D ≤ 6.2 × L_D
     Pt La + Ga Ka r0.3 high Pt 6.93 R1: within 1.5 FWHM of Ga Kα, 6.9 × L_D ≤ 22.1 × L_D
     Pb La + As Ka r0.3 high Pb 3.63 R1: within 1.5 FWHM of As Kα, 3.6 × L_D ≤ 5.1 × L_D
- H5 (c): ghosts: false picks the baseline makes 0; removed by R1b 0
  pairs: false picks the baseline makes 0; removed by R1b 0
- H6 (b): true elements lost by R2 (R2's own drops, incl. the R1b+R2 set) on T-S pairs with PLANTED net/L_D >= 3: 0 (all true losses, any planted level: 9; the planted level of each is in the pairs table)
- H5 (d): T-Q hits lost by R1b: 0; T-Q false picks removed by R1b: 54
- H6 (a): T-Q precision baseline 53.9 % -> R2 81.3 % (all classes, truth as given); easy/moderate hits lost by R2: 0
     K1001 (difficult) Pb 2.80 R2: 2.8 × L_D < 3
     K489 (difficult) Ta 2.02 R2: 2.0 × L_D < 3
     K1053 (very difficult) I 2.46 R2: 2.5 × L_D < 3
     K493 (very difficult) Zr 1.04 R2: 1.0 × L_D < 3
     K523 (very difficult) Ba 1.23 R2: 1.2 × L_D < 3
     K523 (very difficult) Zr 1.10 R2: 1.1 × L_D < 3
     K968 (very difficult) Ba 1.93 R2: 1.9 × L_D < 3
     K968 (very difficult) Eu 1.08 R2: 1.1 × L_D < 3
- H5 (d): T-V hits lost by R1b: 0; false picks removed by R1b: 61
- H6 (c): T-V hits lost by R2: 4 (registered: refuted if more than one); by R1b+R2: 4
     SI HAADF 1549.emd Pt 2.76 R2: 2.8 × L_D < 3
     SI HAADF 1020.emd Ge 2.45 R2: 2.5 × L_D < 3
     SI HAADF 1100.emd Ni 2.20 R2: 2.2 × L_D < 3
     SI HAADF 1253.emd In 1.36 R2: 1.4 × L_D < 3
- H5 (e): false picks removed by R1b anywhere (T-S pairs + ghosts, T-Q, T-V): 115 (refuted if none)
