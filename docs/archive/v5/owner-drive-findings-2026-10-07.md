# The owner's drive of the ADR 058 landing (2026-10-07 ~12:30, his words, verbatim; his copy an Xcode build of f71b41eb)

Shots: Imaging on AlMgSi_4D_EDX.dm4 (light appearance), the Spectroscopy room on the same cube, SI HAADF 1438 (whole map and a 4 444 px region), the Show menu.

- "where did the compute image button go? did we do changes to the other workspaces? something is off" → "yes compute image should be back!"
- "looks better now but still no liquid glass effect like in xcode, i see the whole windows in the left and right pane are liquid glass, but i
  preferred it better with no floating panes but instead only the buttons to liquid glass"
- "Auto id doesn't really work, why can't we do it like velox? do you have velox code/application for comparison? i also have velox light
  (/Volumes/PL_SSD_2TB/NAS_Backup/02_methods/Software/Velox/VeloxLite_3.22.1.3229.exe)"
- "the lines in the spectrum are too thin, also lines in the region are too thin, maybe give them color, the corresponding spectrum is shown
  as well, this should have the same color of course, it has to be intuitive, and well designed, it should be fun to play with the dataset"
- "i like right click in spectrum to select elements"
- "the show dropdown could live in the settings pane as well, not as a dropdown but as well designed buttons, makes more sense to me"
- "zooming in on the spectrum doesn't work yet, maybe we didn't consider this feature, but it should be there somewhere, it has to feel natural
  interacting with the spectrum, the colormaps have no scalebar"
- "exporting works well, we still need the option to export with or without the scalebar"
- "on which basis are the KLM lines preselected? this has to match velox. in velox you can also select alpha and beta separately, sometimes you want that"

Answers given (12:40): Compute Image left by his own card of 2026-10-04 (a1a8d234); the only shell-wide change of the morning was the glass;
no Velox code exists, but 41 of his 112 SI files carry Velox's selections and its 200 kV element table (`velox-family-table-200kV-2026-10-07.json`);
the VeloxLite 3.22 guide (innoextract) says lines are chosen for maps and markers only, the fit takes whole families; our family rule was eXSpy's.
Built as ADR 059.
