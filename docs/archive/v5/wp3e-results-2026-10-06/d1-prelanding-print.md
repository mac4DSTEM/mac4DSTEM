# D1 pre-landing print (lane R9, 2026-10-06)

Harness: gateD2 harness (realdiag prop ... --print-conflicts, sigma0 mode 0 = flank, file axis, list O,Mg,Al,Si), pooled spectra only. 'without (b)' = the gateD2 binary (repo ElementProposer at ef64c372); 'with (b)' = the lane's ElementProposer (v2: parents taken strongest first, none whose sums land on a parent already taken). Pools 1339/1909/1840 x whole/matrix/network + synthetic whole/Al-phase.

## v2 (the landed code in the lane copy)

| pool | variant | proposed | sum-peak questions | found parents | passes/settled |
|---|---|---|---|---|---|
| 1339_whole | without (b) | Ba Cu Ho Th | Ar Co Fe Hf Mn Zr | Ba Co Cu Fe Hf Ho Mn Th Zr | 24/true |
| 1339_whole | with (b) | Ba Co Cu Hf Ho Mn Th Zr | Ar Fe | Co Cu Ho Mn Th Zr | 25/true |
| 1339_matrix | without (b) | Cu Ho Mn Th | Ar Fe Hf Zr | Cu Fe Hf Ho Mn Th Zr | 22/true |
| 1339_matrix | with (b) | Cu Hf Ho Mn Th Zr | Ar Fe | Cu Ho Mn Th Zr | 18/true |
| 1339_network | without (b) | Ca Cu Mn Tm V | Ar Fe Rh | Ca Cu Fe Mn Tm V | 41/false |
| 1339_network | with (b) | Ca Cu Mn Tm V | Ar Fe Rh | Ca Cu Mn Tm V | 37/false |
| 1909_whole | without (b) | Cu Eu Hf | Ar Zr | Cu Eu Hf Zr | 9/true |
| 1909_whole | with (b) | Cu Eu Hf Zr | Ar | Cu Eu Zr | 9/true |
| 1909_matrix | without (b) | Co Cu Eu Hf Ho Se | Ar Zr | Co Cu Eu Hf Ho Se Zr | 15/true |
| 1909_matrix | with (b) | Co Cu Eu Hf Ho Se Zr | Ar | Co Cu Eu Ho Se Zr | 15/true |
| 1909_network | without (b) | As Ba Cr Cs Cu Nd Tm V | Fe Ho Mn | As Ba Cr Cs Cu Fe Ho Mn Nd Tm V | 65/false |
| 1909_network | with (b) | Ba Cu Hf Mn Tm V Zr | Ag Fe | Cu Mn Tm V Zr | 40/false |
| 1840_whole | without (b) | Cu Eu Hf | Ar Zr | Cu Eu Hf Zr | 9/true |
| 1840_whole | with (b) | Cu Eu Hf Zr | Ar | Cu Eu Zr | 9/true |
| 1840_matrix | without (b) | Ba Co Cu Eu Hf Ho La | Ar Se | Ba Co Cu Eu Hf Ho La Se | 22/true |
| 1840_matrix | with (b) | Ba Co Cu Eu Hf Ho La Zr | Ar | Ba Co Cu Eu Ho La Zr | 22/true |
| 1840_network | without (b) | Ba Cs Cu Nd Tm V | Co Fe Hf Mn Pr Zr | Ba Co Cs Cu Fe Hf Mn Nd Pr Tm V Zr | 56/true |
| 1840_network | with (b) | Ba Cu Hf Mn Tm V | Ag Fe | Cu Hf Mn Tm V | 40/false |
| synth_whole | without (b) | Cu | Ar | Cu | 4/true |
| synth_whole | with (b) | Cu | Ar | Cu | 4/true |
| synth_matrix | without (b) | Cu | Ar | Cu | 4/true |
| synth_matrix | with (b) | Cu | Ar | Cu | 4/true |


## v1 (the literal spec: each candidate judged against the previous pass's parents), for the record

| pool | variant | proposed | sum-peak questions | found parents | passes/settled |
|---|---|---|---|---|---|
| 1339_whole | without (b) | Ba Cu Ho Th | Ar Co Fe Hf Mn Zr | Ba Co Cu Fe Hf Ho Mn Th Zr | 24/true |
| 1339_whole | with (b) | Ba Cu Fe Ho Zr | Ar Co Hf Mn | Ba Cu Fe Ho Zr | 28/false |
| 1339_matrix | without (b) | Cu Ho Mn Th | Ar Fe Hf Zr | Cu Fe Hf Ho Mn Th Zr | 22/true |
| 1339_matrix | with (b) | Cu Hf Ho Mn | Ar Fe Zr | Cu Hf Ho Mn | 23/true |
| 1339_network | without (b) | Ca Cu Mn Tm V | Ar Fe Rh | Ca Cu Fe Mn Tm V | 41/false |
| 1339_network | with (b) | Ca Cu Mn Tm V | Ar Fe Rh | Ca Cu Mn Tm V | 42/false |
| 1909_whole | without (b) | Cu Eu Hf | Ar Zr | Cu Eu Hf Zr | 9/true |
| 1909_whole | with (b) | Cu Eu Hf | Ar Zr | Cu Eu Hf | 10/true |
| 1909_matrix | without (b) | Co Cu Eu Hf Ho Se | Ar Zr | Co Cu Eu Hf Ho Se Zr | 15/true |
| 1909_matrix | with (b) | Co Cu Eu Hf Ho Se | Ar Zr | Co Cu Eu Hf Ho Se | 16/true |
| 1909_network | without (b) | As Ba Cr Cs Cu Nd Tm V | Fe Ho Mn | As Ba Cr Cs Cu Fe Ho Mn Nd Tm V | 65/false |
| 1909_network | with (b) | Ba Cs Cu Fe Nd Se Tm V Zr | Ag Hf Mn Pr | Ba Cs Cu Fe Nd Se Tm V Zr | 45/false |
| 1840_whole | without (b) | Cu Eu Hf | Ar Zr | Cu Eu Hf Zr | 9/true |
| 1840_whole | with (b) | Cu Eu Hf | Ar Zr | Cu Eu Hf | 10/true |
| 1840_matrix | without (b) | Ba Co Cu Eu Hf Ho La | Ar Se | Ba Co Cu Eu Hf Ho La Se | 22/true |
| 1840_matrix | with (b) | Ba Co Cu Eu Hf Ho La | Ar Se Zr | Ba Co Cu Eu Hf Ho La | 20/true |
| 1840_network | without (b) | Ba Cs Cu Nd Tm V | Co Fe Hf Mn Pr Zr | Ba Co Cs Cu Fe Hf Mn Nd Pr Tm V Zr | 56/true |
| 1840_network | with (b) | Ba Cs Cu Fe Nd Tm V | Ag Mn Pr | Ba Cs Cu Fe Nd Tm V | 50/false |
| synth_whole | without (b) | Cu | Ar | Cu | 4/true |
| synth_whole | with (b) | Cu | Ar | Cu | 4/true |
| synth_matrix | without (b) | Cu | Ar | Cu | 4/true |
| synth_matrix | with (b) | Cu | Ar | Cu | 4/true |


## Verdict against the landing condition

Synthetic whole and Al-phase: proposed set, questions, found parents and every sum column identical (HELD).
Real whole/matrix pools (1339, 1909, 1840): the changes are questions -> proposals (Zr on all six; Hf, Mn, Co on 1339 whole; Hf on 1339 matrix) and found-only sum columns disappearing (HELD), with these exceptions:
 - 1840 matrix: Zr appears from nothing (it was neither proposed nor a question), the Se question disappears, and found-only columns Al+Zr, O+Zr appear and Ba+Ho (11.186 keV, detected) appears where the Se question used to claim that energy.
 - the 'possible' lists shift on 1339 whole (Lu, Nd, Re), 1339 matrix (Co), 1909 matrix (Ru), 1840 whole (Se).
Network pools (1339 unchanged; 1909 and 1840 not): proposals vanish (1909: As Cr Cs Nd; 1840: Cs Nd), a new question Ag appears, listed-only columns (Al+Al, Al+Mg, Mg+Mg, Mg+Si) vanish, 1840 network goes settled true -> false (1909/1339 network were already unsettled).
Landing condition NOT met by v2; v1 (literal) is worse (1339 whole does not settle: 28 passes, settled false; Zr stays a question wherever Hf is proposed). Per the spec: stop, new registration. The rule was not tuned after the print.
