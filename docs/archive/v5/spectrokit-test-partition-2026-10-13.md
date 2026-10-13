# SpectroKit S1: the test partition (2026-10-13)

ADR 064 section 3.3 asks for the moving-test delta *stated by name*. This is that list. It was produced at `f01bec85` by re-deriving a static partition (a name-level parse made earlier the same day at `71929a01`) at that HEAD, splitting every mixed test file by method, and then **compile-checking** the result: a scratch SwiftPM test target holding only the moving files, depending on `DSTEMCore` alone (a `Package.swift` in a throwaway copy; the repo's `Package.swift` is untouched). No assertion changed; no test was added or removed.

## Counts

| | files | test methods |
|---|---|---|
| Whole test target (before and after; moves only) | 293 | **2494** |
| **Moving** (28 files: 18 whole files + 10 `+Spectro` halves of split files) | 28 | **258** |
| Staying | | **2236** |

The static estimate (259 moving) was not confirmed: 258 methods move. The ADR's 560 counted the whole room as well; the compile partition moves only what needs nothing but `DSTEMCore`. Every one of the 258 compiles in the DSTEMCore-only target, and a name check against every staying declaration (the same parse that made the partition, re-run on the new tree) finds no staying symbol in a moving file and no moving-only file in a staying one.

## The compile check

`swift build --build-tests` on a copy of the tree whose `Package.swift` gains one target, `SpectroMovingTests` (path `mac4DSTEMTests`, `sources:` = the 28 files below, dependency `DSTEMCore` only, the same Swift 5 / MainActor-default / upcoming-feature settings as the app's test target). Result: **Build complete, 0 errors** (warnings only: actor-isolated-call notes already present in the Xcode build). A file that imported `@testable mac4DSTEM` or `DSTEMSession` failed at once with `unable to resolve module dependency: 'mac4DSTEM'`; a leftover private helper naming `AppState` / `SpectroscopyRoomController` failed with `cannot find type`. Both were fixed (below); no file had to be reclassified STAYS.

The added target, verbatim apart from the file list: `.testTarget(name: "SpectroMovingTests", dependencies: ["DSTEMCore"], path: "mac4DSTEMTests", sources: [<the 28 files>], swiftSettings: [.swiftLanguageMode(.v5), .defaultIsolation(MainActor.self), <the four upcoming features of DSTEMCore>])`; then `swift build --build-tests`.

Imports of the moving files after the change: `XCTest` and `DSTEMCore` (`@testable` in `MapSmoothingTests` and `SpectrumImageOpeningTests+Spectro`), plus the system frameworks `CryptoKit` (`DemoEDXFixtureTests+Spectro`) and `CoreGraphics` (`SpectrumImageOpeningTests+Spectro`). No `mac4DSTEM`, `DSTEMSession`, `SwiftUI` or `DSTEMTraining`.

**What the compile check cannot see.** `DSTEMCore` still holds the staying 4D Core (`DM4Reader` and the other 4D types), so a moving test that named a 4D Core symbol would still compile; that is what the name check above is for. The check proves the *tests* need nothing outside the moving set plus DSTEMCore, not that the moving *sources* are free of 4D coupling (that is the seam and `public` work, other lanes).

## Whole files that move (18)

Unchanged except where noted. Identifiers are unchanged.

| file | class | methods |
|---|---|---|
| `AutoIDRulesWP4bTests.swift` | `AutoIDRulesWP4bTests` | 4 |
| `DM4TagTreeTests.swift` | `DM4TagTreeTests` | 3 |
| `EDSQuantPinsTests.swift` | `EDSQuantPinsTests` | 8 |
| `MapSmoothingTests.swift` | `MapSmoothingTests` | 7 |
| `SpectroCancellationTests.swift` | `SpectroCancellationTests` | 10 |
| `SpectroscopyAbsorptionTruthTests.swift` | `SpectroscopyAbsorptionTruthTests` | 3 |
| `SpectroscopyComputedKTests.swift` | `SpectroscopyComputedKTests` | 6 |
| `SpectroscopyCoreTests.swift` | `SpectroscopyCoreTests` | 15 |
| `SpectroscopyDriveL10Tests.swift` | `SpectroscopyDriveL10Tests` | 5 |
| `SpectroscopyFitTests.swift` | `SpectroscopyFitTests` | 27 |
| `SpectroscopyProposerTests.swift` | `SpectroscopyProposerTests` | 15 |
| `SpectroscopyQuantTests.swift` | `SpectroscopyQuantTests` | 18 |
| `SpectroscopyStatisticsTests.swift` | `SpectroscopyStatisticsTests` | 16 |
| `SumColumnDedupTests.swift` | `SumColumnDedupTests` | 3 |
| `SumEscapeIdenticalTests.swift` | `SumEscapeIdenticalTests` | 4 |
| `VeloxEMDReaderTests.swift` | `VeloxEMDReaderTests` | 30 |
| `VeloxLockAndCancelTests.swift` | `VeloxLockAndCancelTests` | 7 |
| `VeloxMetadataBoundTests.swift` | `VeloxMetadataBoundTests` | 1 |

Edits to whole moving files (no assertion touched): `@testable import mac4DSTEM` removed from `AutoIDRulesWP4bTests`, `EDSQuantPinsTests`, `SpectroCancellationTests`, `SpectroscopyAbsorptionTruthTests`, `SpectroscopyComputedKTests`, `SpectroscopyQuantTests`; `import DSTEMSession` removed from `SpectroscopyAbsorptionTruthTests`; `SpectroCancellationTests` now reads `SpectroscopyQuantifySpectro.resources` (it was `SpectroscopyQuantifyTests.resources`) so it depends on the moving half of the split.

## Split files (10): the moving half is `<Name>+Spectro.swift`

| staying file (class) | moving file (class) | methods moved | methods stay |
|---|---|---|---|
| `DM4ExperimentTests.swift` (`DM4ExperimentTests`) | `DM4ExperimentTests+Spectro.swift` (`DM4ExperimentSpectro`) | 22 | 1 |
| `DemoEDXFixtureTests.swift` (`DemoEDXFixtureTests`) | `DemoEDXFixtureTests+Spectro.swift` (`DemoEDXFixtureSpectro`) | 5 | 2 |
| `FinalPolishDTests.swift` (`FinalPolishDTests`) | `FinalPolishDTests+Spectro.swift` (`FinalPolishDSpectro`) | 1 | 11 |
| `MethodTests.swift` (`QuantificationMethodTests`) | `MethodTests+Spectro.swift` (`QuantificationMethodSpectro`) | 5 | 5 |
| `SpectroscopyDriveL12Tests.swift` (`SpectroscopyDriveL12Tests`) | `SpectroscopyDriveL12Tests+Spectro.swift` (`SpectroscopyDriveL12Spectro`) | 8 | 1 |
| `SpectroscopyFitRangeTests.swift` (`SpectroscopyFitRangeTests`) | `SpectroscopyFitRangeTests+Spectro.swift` (`SpectroscopyFitRangeSpectro`) | 4 | 4 |
| `SpectroscopyLaneUTests.swift` (`SpectroscopyLaneUTests`) | `SpectroscopyLaneUTests+Spectro.swift` (`SpectroscopyLaneUSpectro`) | 6 | 11 |
| `SpectroscopyQuantifyTests.swift` (`SpectroscopyQuantifyTests`) | `SpectroscopyQuantifyTests+Spectro.swift` (`SpectroscopyQuantifySpectro`) | 8 | 11 |
| `SpectroscopyUnlistedLineTests.swift` (`SpectroscopyUnlistedLineTests`) | `SpectroscopyUnlistedLineTests+Spectro.swift` (`SpectroscopyUnlistedLineSpectro`) | 6 | 4 |
| `SpectrumImageOpeningTests.swift` (`SpectrumImageOpeningTests`) | `SpectrumImageOpeningTests+Spectro.swift` (`SpectrumImageOpeningSpectro`) | 11 | 15 |

Helpers are **duplicated, not shared**, across each split: every non-test member the other half still needs is a private copy in that half, and a private helper no kept method uses was dropped from it. Non-private statics (`SpectroscopyQuantifyTests.fixtures / resources / tables / image() / truthArea / method / input`) are kept in both halves because the staying files, and the moving `SpectroscopyFitRange` / `SpectroscopyUnlistedLine` halves, reach them as `Q.`; the moving ones now point at `SpectroscopyQuantifySpectro` (and `SpectroscopyUnlistedLineSpectro`). Duplicated helpers per file:

- `DM4ExperimentTests.swift`: `Axis`, `Node`, `calibrations`, `delim`, `diffraction`, `diffractionValues`, `eds`, `encode`, `experiment`, `f32s`, `file`, `fullFile`, `head`, `i16s`, `int16s`, `keywords`, `le`, `nm`, `noise`, `object`, `rectValues`, `scanSignal`, `survey`, `surveyID`, `surveyLink`, `tempFile`, `thumbnail`, `thumbnails`, `u16be`, `u16s`, `u64be`, `um`, `umY`
- `DemoEDXFixtureTests.swift`: `dir`, `dm4`, `hash`, `hex`, `object`, `truth`
- `FinalPolishDTests.swift`: `directory`, `setUpWithError`, `tearDownWithError`
- `MethodTests.swift`: `richMethod`
- `SpectroscopyDriveL12Tests.swift`: `candidate`, `held`, `proposal`
- `SpectroscopyFitRangeTests.swift`: `Fixture`, `Q`, `SplitMix64`, `counts`, `fx`, `input`, `poisson`, `row`
- `SpectroscopyLaneUTests.swift`: `Q`
- `SpectroscopyQuantifyTests.swift`: `fixtures`, `image`, `input`, `method`, `resources`, `tables`, `truthArea`
- `SpectroscopyUnlistedLineTests.swift`: `Pool`, `Q`, `SplitMix64`, `four`, `groups`, `input`, `note`, `poisson`, `pool`
- `SpectrumImageOpeningTests.swift`: `dir`, `dm4`, `h5`, `velox`

## Method renames (old identifier to new; split files only)

Identifier form `mac4DSTEMTests/<Class>/<method>`. The method name never changes; only the class does, and only for the moving half. Staying methods keep their identifiers.

| old class | new class | methods |
|---|---|---|
| `DM4ExperimentTests` | `DM4ExperimentSpectro` | 22 |
| `DemoEDXFixtureTests` | `DemoEDXFixtureSpectro` | 5 |
| `FinalPolishDTests` | `FinalPolishDSpectro` | 1 |
| `QuantificationMethodTests` | `QuantificationMethodSpectro` | 5 |
| `SpectroscopyDriveL12Tests` | `SpectroscopyDriveL12Spectro` | 8 |
| `SpectroscopyFitRangeTests` | `SpectroscopyFitRangeSpectro` | 4 |
| `SpectroscopyLaneUTests` | `SpectroscopyLaneUSpectro` | 6 |
| `SpectroscopyQuantifyTests` | `SpectroscopyQuantifySpectro` | 8 |
| `SpectroscopyUnlistedLineTests` | `SpectroscopyUnlistedLineSpectro` | 6 |
| `SpectrumImageOpeningTests` | `SpectrumImageOpeningSpectro` | 11 |

The full old to new list is the table in the next section: each moving method of a split file appears under its new class, and its old identifier is the same method under the old class in the table above. `comm` of declared names before and after (old identifiers renamed by the class table) is empty: 2 494 before, 2 494 after.

## Every moving method, by name (258)

### `AutoIDRulesWP4bTests.swift` (`AutoIDRulesWP4bTests`), 4
- `testGuardKeepsAStrongerLBesideAWeakerKAndDropsAWeakerOne`
- `testGuardWithTwoKCandidatesInTheWindowDropsWhenAnyOneIsAtLeastAsStrong`
- `testGuardChangesNothingOutsideItsClause`
- `testShippedRegisteredAndNoneAreUnchanged`

### `DM4TagTreeTests.swift` (`DM4TagTreeTests`), 3
- `testABareTagStreamListsNoObjectsButTagTreeMatchesNcempy`
- `testATruncatedBareStreamThrowsAtEveryCut`
- `testAStreamWithAnImageListStillListsAndKeepsItsRootPrefix`

### `EDSQuantPinsTests.swift` (`EDSQuantPinsTests`), 8
- `testFixtureCoversThePreRegisteredCases`
- `testCliffLorimerWithoutAbsorption`
- `testCliffLorimerAbsorptionMatchesEXSpyIterationForIteration`
- `testZetaWithoutAbsorption`
- `testZetaAbsorptionMatchesEXSpyIterationForIteration`
- `testAbsoluteCriterionStaysWithinEXSpysStoppingError`
- `testAbsoluteCriterionRunsOnWhereEXSpyStopsEarly`
- `testPinsDistinguishKOrderAndDose`

### `MapSmoothingTests.swift` (`MapSmoothingTests`), 7
- `testNoneIsIdentityAndAShapeMismatchIsLeftAlone`
- `testEveryKernelConservesTheTotalOfAnInteriorFeatureIncludingNegatives`
- `testTheBorderKeepsTheMeanNotADarkRim`
- `testAFlatMapStaysFlat`
- `testBox3SpreadsAnInteriorDeltaEvenly`
- `testGaussianIsSymmetricAndPeakedAtTheSource`
- `testLabelsNameTheKernelAndNoneIsSilent`

### `SpectroCancellationTests.swift` (`SpectroCancellationTests`), 10
- `testImageLoopsCancelAtTheFirstAndAtALaterBlockAndReportProgress`
- `testElementWindowMapsForwardTheCancel`
- `testOpenersCancelBeforeAndBetweenSteps`
- `testOpenVeloxForwardsCancelAndProgressIntoTheRead`
- `testPooledQuantifierCancelsAtTheEntryInsideTheRefinementAndAtTheLaterBoundaries`
- `testAxisRefinementCancelsPerSimplexIterationAndReportsProgress`
- `testFitRangeSensitivityCancelsAndIsNeverFoldedIntoFailure`
- `testUnlistedLineCheckCancelsInsideTheRefit`
- `testProposerCancelsThroughTheClosureAndReportsProgress`
- `testBundledTablesTakeTheBundleTheyAreGiven`

### `SpectroscopyAbsorptionTruthTests.swift` (`SpectroscopyAbsorptionTruthTests`), 3
- `testExactAreasRecoverTruthWithTheSimulatorsGeometryAndTheUncorrectedIsOffAsPredicted`
- `testPooledFitRecoversTruthAndTheCorrectionMovesTheSharesTheRightWay`
- `testPooledCorrectionAgreesWithTheSimulatorsOwnTransmissionOnTheSameFittedAreas`

### `SpectroscopyComputedKTests.swift` (`SpectroscopyComputedKTests`), 6
- `testBoteSalvatMatchesReimplementation`
- `testBoteSalvatEdgesAndMonotonicity`
- `testKrauseK`
- `testSDDEfficiencyPins`
- `testComputedKRatiosAndSet`
- `testClosedLoopWithRealModels`

### `SpectroscopyCoreTests.swift` (`SpectroscopyCoreTests`), 15
- `testFWHMLawMatchesExspy`
- `testLineTableIsExspyVerbatim`
- `testDefaultLineChoiceMatchesExspy`
- `testValue2IndexMatchesHyperspy`
- `testSliceSemanticsMatchHyperspy`
- `testFePtPins`
- `testTM002Pins`
- `testWindowOutsideAxis`
- `testSparseAndDenseWindowMapsAreBitIdentical`
- `testPerPixelMapOfAKnownSpectrumReproducesThePins`
- `testWidthLawUndefinedIsNilNotNaN`
- `testCSRContractIsValidated`
- `testEmptyOnlyLinesIsNoFilter`
- `testHeliumAndHydrogenAreDroppedWhereExspyKeepsThem`
- `testMgAlSiMergedBackgroundSitsOnSiliconsFlank`

### `SpectroscopyDriveL10Tests.swift` (`SpectroscopyDriveL10Tests`), 5
- `testSelectionSymbolsFollowTheAtomicNumbers`
- `testNoSelectionIsNil`
- `testVersion9ReadsTheFirstOperationEntry`
- `testVersion11ReadsTheSharedPropertiesEntry`
- `testAFileWithoutASelectionReturnsNil`

### `SpectroscopyFitTests.swift` (`SpectroscopyFitTests`), 27
- `testDesignColumnsMatchHyperspy`
- `testClosedLoopRecoversWeightFractions`
- `testPoly6PathEqualsHyperspyModel`
- `testClosedLoopWithEscapeColumnsStillWithinPin`
- `testFePtLeastSquaresPins`
- `testNNLSMatchesScipyAndDiffersFromUnbounded`
- `testFreeColumnsAreExactlyEliminated`
- `testIRLSDevianceNonIncreasingConvergesAndSatisfiesKKT`
- `testIRLSDevianceNonIncreasingOnLowCountPixels`
- `testPoissonDevianceKnownValues`
- `testCovarianceMatchesRepeatedFits`
- `testContinuumAlEdgeResidualIsFlat`
- `testContinuumResidualAcrossSeedsMatchesPerfectModel`
- `testContinuumStepBeatsPlainPolynomialAtTheEdge`
- `testStandardizedResidualStaysFiniteWhereModelIsZero`
- `testAxisRefinementRecoversPlantedOffsetAndGain`
- `testEscapePeaksAreFittedAndMgAlSiHaveNone`
- `testReferenceShapeSlotIsEmptyByDefaultAndTiesWork`
- `testMaximumLikelihoodBiasVersusLeastSquaresAtLowCounts`
- `testWeakLineRecoveryRegisteredSelection`
- `testTailReferenceShapeRemovesTheSimulatorWeakLineBias`
- `testCovarianceOfTheDefaultContinuumFit`
- `testWeakLineBadgeAccompaniesContinuumFitsOnly`
- `testEfficiencyIsComparedByParametersNotName`
- `testReferenceShapePreconditionsThrow`
- `testLineWithoutARealWidthIsDroppedAndReported`
- `testWarningsNameTheLargeEscapeRatioAndTheSignedMLBackground`

### `SpectroscopyProposerTests.swift` (`SpectroscopyProposerTests`), 15
- `testKramersContinuumNoFalseMgAndTheDetectionRate`
- `testGaLAlphaDoesNotMakeAFalseMg`
- `testUnlistedOxygenIsProposedAndBiasesNoNeighbour`
- `testAlEdgeStepMakesNoFalseMgOrSi`
- `testSumPeaksAreNamedExactlyWhereTruthExceedsTheDetectionLimit`
- `testTheProposerNeverMutatesTheElementList`
- `testLightElementsAreRefusedWithTheirReasons`
- `testCuDefaultsToQuantifyWithTheGridQuestionAndTheHoleCheck`
- `testNotesCarryTheFitWarningsAndTheDetectionRule`
- `testNullVarianceEqualsTheFittedOneForAnAbsentLineAndIsSmallerForAStrongOne`
- `testFalsePositiveRateAtTheCriticalLevelIsAboutAlpha`
- `testNotesAndCandidatesExposeTheMisfitFactorAndTheLookElsewhereRate`
- `testFitSigmaPredictsTheScatterOfTheAlphaArea`
- `testProposerNullVarianceKeepsTheFullDesign`
- `testACancelledTaskThrowsCancelledBeforeFinishing`

### `SpectroscopyQuantTests.swift` (`SpectroscopyQuantTests`), 18
- `testTakeOffPins`
- `testMassAbsorptionPins`
- `testSentinelIsStrippedAndOutsideTableRefuses`
- `testCliffLorimerAlZnAndFePt`
- `testCuSnWeightToAtomic`
- `testCliffLorimerZeroHandlingTable`
- `testMassThicknessCL`
- `testCLAbsorptionPinsBothCriteria`
- `testConvergenceMeasure`
- `testZetaAndCrossSectionPins`
- `testFourIdenticalSegmentsEqualSingleDetector`
- `testWeightedMeanIsNotGeometricMeanAndShadowWeights`
- `testSymmetricSegmentsIgnoreTheTiltSign`
- `testFourDetectorRefusals`
- `testThicknessSigmaByFiniteDifference`
- `testKFactorSourceAndRatioSigma`
- `testComputedKClosedLoop`
- `testEPQLineWeights`

### `SpectroscopyStatisticsTests.swift` (`SpectroscopyStatisticsTests`), 16
- `testGammaQuantileMatchesScipy`
- `testGammaQuantileRoundTripsThroughP`
- `testNormalQuantile`
- `testGarwoodPins95`
- `testGarwoodAtOtherCountsAndConfidence`
- `testNetCounts`
- `testCurrieClassicConstantsAtScaleOne`
- `testCurrieUsesTheWindowScale`
- `testCurrieDetectionLimitSolvesItsDefiningEquation`
- `testSigmaTermsQuadratureAndNames`
- `testKTermCarriedAsRatioAndCancelsForRatioOfRatios`
- `testAmplitudeCovarianceRatioVariance`
- `testLiveTimeRoutesAgreeAcrossDeadTimeNoiseFree`
- `testLiveTimeRoutesAgreeWithinOneSigmaUnderPoissonNoise`
- `testLiveTimeFallbackIsNamedAndReasoned`
- `testCoverageAcrossTheCountLadder`

### `SumColumnDedupTests.swift` (`SumColumnDedupTests`), 3
- `testTwoCoincidingSumPairsScoreAndTheKeptColumnNamesBoth`
- `testALonePairKeepsItsPlainLabelAndElements`
- `testNearPairsFourHundredEVApartStayTwoColumns`

### `SumEscapeIdenticalTests.swift` (`SumEscapeIdenticalTests`), 4
- `testVKaEscapeEqualToTbMaPlusIrMaScoresOnAShortAxis`
- `testPileUpAtAnInactivePoolGroupsOneComponentEnergyKeepsItsSumColumn`
- `testLaKaEqualToCdKaPlusTlLaIsNotDroppedAndNeverProposesLa`
- `testSrPlusBaSumAtAMultiLineGroupsAlphaKeepsItsColumn`

### `VeloxEMDReaderTests.swift` (`VeloxEMDReaderTests`), 30
- `testMarkersEndPixelsAndAnEmptyPixelIsTwoMarkersInARow`
- `testFrameRangeSumsOnlyThoseFrames`
- `testSubAreaRasterIsRowMajorAndAPartialFrameIsReported`
- `testDetectorsSumAndOutOfRangeChannelsAreCounted`
- `testSuperXGeometryAndTheEnergyAxisAreParsed`
- `testAMissingEnergyCalibrationIsNilNotUnity`
- `testNestedScanTransformationIsAFallback`
- `testDetectionRecognisesAVeloxEMDAndNothingElse`
- `testAVeloxImageFileWithNoStreamIsNotASpectrumImage`
- `testAVersionDatasetOfSeveralElementsIsNotVelox`
- `testMainFileDecodesEndToEnd`
- `testStreamsSegmentsAndTheEnergyCalibrationCheck`
- `testMainFileFrameRange`
- `testMainFileFrameTransformationsAndMarkerWindows`
- `testTheCeilPathWithNoTableAndNoSettings`
- `testAFrameEndingWithoutItsLastMarkerIsComplete`
- `testTheLastImageGridFallback`
- `testAGridInconsistentWithTheStreamIsRefused`
- `testAGridLargerThanTheStreamIsRefusedWithoutATable`
- `testBadFramePositionsThrow`
- `testATruncatedFileThrows`
- `testImagesListsTheTypedFilesThreeStacks`
- `testEveryFrameOfEveryTypeEqualsRsciio`
- `testTheOtherStoredTypesAreNamedAndReadRoundedToFloat32`
- `testImageMetadataEqualsRsciiosAxesAfterUnitConversion`
- `testMetadataReportsBothPixelUnitsAndBothOffsets`
- `testIsVeloxFileAcceptsStreamAndImageFilesAndNothingElse`
- `testReadImageFrameRefusesAnUnknownIdAndAFrameOutOfRange`
- `testAnImageWithNoFloatReadOrTooManyPixelsIsRefusedByName`
- `testImagesOfTheMainFileAndOfFilesThatAreNotVelox`

### `VeloxLockAndCancelTests.swift` (`VeloxLockAndCancelTests`), 7
- `testAnotherThreadGetsTheHDF5LockBetweenBlocksOfADecode`
- `testMarkerScansAlsoReleaseTheLockBetweenBlocks`
- `testSmallBlocksGiveTheSameStoreAsTheDefaultBlock`
- `testCancelAfterTheFirstBlockThrowsAndStopsReading`
- `testEveryLongCallThrowsSpectroCancelled`
- `testProgressIsMonotoneAndEndsAtOne`
- `testLibraryCandidatesDefaultAndOverride`

### `VeloxMetadataBoundTests.swift` (`VeloxMetadataBoundTests`), 1
- `testAnOversizedMetadataDatasetIsRefusedBeforeItIsAllocated`

### `DM4ExperimentTests+Spectro.swift` (`DM4ExperimentSpectro`) (was `DM4ExperimentTests`), 22
- `testMetaDataFormatAndSignalAreReportedVerbatim`
- `testEachObjectExposesItsOwnImageTags`
- `testTheRealEDSFixtureCarriesSpectrumImageAndXRay`
- `testRolesAreListedFromTheExperimentLabels`
- `testTheSpectrumImageRectAndTheSurveyLinkAreParsed`
- `testTheSurveyLinkResolvesByIDNotByPosition`
- `testTheSurveysOwnIDFallsBackToItsImageTag`
- `testAFileWithoutASurveyStillListsCorrectly`
- `testTheLabelDecidesNotTheNameAndAnUnknownLabelFallsToTheName`
- `testKeywordPositionsAreNotRelied`
- `testTheRootThumbnailListDecidesBeforeTheDataType`
- `testEDSDetectorTagsAreListed`
- `testA2DSurveyReadsBackExactly`
- `testEveryPixelTypeReadsBackWithItsSign`
- `testOnlyA2DImageIsReadAndEachRefusalSaysWhy`
- `testA3DObjectWhoseDataTagDeclaresNoBytesIsStillRefused`
- `testTheFileHandlePathListsAndReadsTheSameAsData`
- `testListingNeverReadsTheBlob`
- `testAType18StringTagBeforeTheFourDObjectDoesNotDesync`
- `testATruncatedFileThrowsAtEveryCut`
- `testAFileThatIsNotDM3OrDM4IsRefusedByName`
- `testMalformedNumbersThrowInsteadOfTrapping`

### `DemoEDXFixtureTests+Spectro.swift` (`DemoEDXFixtureSpectro`) (was `DemoEDXFixtureTests`), 5
- `testTheFixtureListsFiveObjectsInOrderUnderOneExperiment`
- `testTheRectAndTheSurveyLinkOfEverySIObjectMatchTheTruth`
- `testTheEDSObjectCarriesTheDetectorTagsAndTheEnergyAxis`
- `testTheSurveyAndTheScanImageReadBackEqualToWhatWasWritten`
- `testTheEDSBlobIsEnergySlowestAndItsPerRecipeSumsMatchTheTruthMap`

### `FinalPolishDTests+Spectro.swift` (`FinalPolishDSpectro`) (was `FinalPolishDTests`), 1
- `testTheErrorTextIsTheOwnersSentence`

### `MethodTests+Spectro.swift` (`QuantificationMethodSpectro`) (was `QuantificationMethodTests`), 5
- `testRoundTripIsByteIdenticalAndTheHashSeesEveryField`
- `testTheDefaultMethodHashIsPinned`
- `testANewerVersionAndGarbageAreRefused`
- `testATypedKNeedsItsSourceAndBuildsTheSet`
- `testAComputedKRecordsTheTableIdentityNotTheDay`

### `SpectroscopyDriveL12Tests+Spectro.swift` (`SpectroscopyDriveL12Spectro`) (was `SpectroscopyDriveL12Tests`), 8
- `testR1NeverPicksAnActinide`
- `testR1DropsAnLOrMPickBesideAnotherProposedCandidatesKAlpha`
- `testR2AnLOrMPickNeedsThreeDetectionLimitsAKPickKeepsTheBar`
- `testR3ReleasesAHeldSumPeakCandidateAtTenDetectionLimits`
- `testAReleasedCandidateStillMeetsR1`
- `testRegisteredNamesTheThreeCutsAndShippedKeepsOnlyR1`
- `testRegisteredOnAMixedResultAndTheRawProposalIsUntouched`
- `testTheShippedSetKeepsAnLPickBesideAProposedK`

### `SpectroscopyFitRangeTests+Spectro.swift` (`SpectroscopyFitRangeSpectro`) (was `SpectroscopyFitRangeTests`), 4
- `testP1TheDefaultStopsAt20keVAndTiIsUnbiased`
- `testP3TheSensitivityStatementAppearsOnlyPastTheDefault`
- `testP4TheUnlistedCheckStillWithholdsAtTheDefault`
- `testP5AxesEndingAt20keVKeepTheOldRange`

### `SpectroscopyLaneUTests+Spectro.swift` (`SpectroscopyLaneUSpectro`) (was `SpectroscopyLaneUTests`), 6
- `testTheBeamEnergySourceIsTheObjectsThenTheSameRunCubes`
- `testTheProvenanceNamesTheBeamAndItsSource`
- `testTheFitFooterCarriesTheBeamProvenance`
- `testTheCSVCarriesTheTableTheValidationBadgeAndTheMethodHash`
- `testTheMethodJSONIsTheCanonicalEncodingAndItsHash`
- `testTheWeakLineWarningNeedsAlAndAQuantifiedNeighbour`

### `SpectroscopyQuantifyTests+Spectro.swift` (`SpectroscopyQuantifySpectro`) (was `SpectroscopyQuantifyTests`), 8
- `testTheFitsChiSquaredIsShownAndExportedBesideTheSigmaScope`
- `testPooledAreasAreWithinTwoSigmaOfTruth`
- `testPoissonMLIsNamedAndReportsADeviance`
- `testAbsorptionIsRefusedOnAGMSFileWithTheReason`
- `testAbsorptionAppliesWithGeometryTiltAndThickness`
- `testARunWithoutABeamEnergyOrElementsIsRefused`
- `testNewMethodFieldsDoNotChangeTheDefaultJSON`
- `testTheKFooterDescribesTheSetItUsed`

### `SpectroscopyUnlistedLineTests+Spectro.swift` (`SpectroscopyUnlistedLineSpectro`) (was `SpectroscopyUnlistedLineTests`), 6
- `testP5CompleteListNamesAChanceProposalButDoesNotWithhold`
- `testT1NeighbourIsAGeometryRule`
- `testT2BesideCandidatesAreExcessesNotElementsAndNeverRefitted`
- `testT3TheQuantityShipsWithTheCaveat`
- `testTheRefitUsesTheSameAxisRefinement`
- `testR8TheOwnerOfASplitEdgeIsNeverBesideIt`

### `SpectrumImageOpeningTests+Spectro.swift` (`SpectrumImageOpeningSpectro`) (was `SpectrumImageOpeningTests`), 11
- `testTheDM4EDSDecodeMatchesTheTruthPerRecipe`
- `testTheDM4EDSBlobIsTransposedFromEnergySlowest`
- `testTheDM4EnergyAxisAndMetadataAreTheFiles`
- `testOnlyAnEDSObjectDecodes`
- `testTheVeloxStoreJoinsTheSparseImageAndSumsEqualADensifiedReference`
- `testTheVeloxOpenerCarriesTheFilesAxisAndMetadata`
- `testTheRouterTellsASpectrumImageFromACube`
- `testAnEllipseKeepsThePixelsWhoseCentresAreInside`
- `testNetCountsAndSigmaFollowThePoissonFormula`
- `testConflictNotesNameTheOtherLine`
- `testABackgroundThatHoldsMoreThanTheSignalIsNotAMeasurement`

## Fixtures that go with the moving tests

Located by `#filePath` next to the test files (`mac4DSTEMTests/Fixtures/...`) unless noted; they travel with the tests at extraction. Fixtures **also used by a staying test** are marked: they are copied, not moved (or the staying side keeps reading the 4D repo's copy).

| fixture | moving users | also used by a staying test |
|---|---|---|
| `demo-edx-tiny.dm4` | `DM4TagTreeTests`, `SpectroCancellationTests`, `DM4ExperimentTests+Spectro`, `DemoEDXFixtureTests+Spectro`, `SpectroscopyQuantifyTests+Spectro`, `SpectrumImageOpeningTests+Spectro` | yes (`DemoEDXFixtureTests`, `E1PoolRecording`, `SpectroscopyQuantifyTests`, `SpectroGoldenTests`, `SpectroscopyLaneUTests`, `SpectrumImageOpeningTests`) |
| `demo-edx-tiny.truth.json` | `DemoEDXFixtureTests+Spectro`, `SpectroscopyQuantifyTests+Spectro`, `SpectrumImageOpeningTests+Spectro` | yes (`DemoEDXFixtureTests`, `SpectroscopyQuantifyTests`) |
| `dm-tag65027-saved-with-DM.dm4`, `dm-tag65027-saved-with-DM.truth.json` | `DM4TagTreeTests` | no |
| `eds-absorption-truth.json` | `SpectroscopyAbsorptionTruthTests` | no |
| `eds-fit-exspy-7185a4d1.json` | `SpectroscopyFitTests` | no |
| `eds-pins-exspy-7185a4d1.json` | `SpectroscopyCoreTests` | no |
| `eds-quant-pins-exspy-7185a4d1.json` | `EDSQuantPinsTests` | no |
| `eds-proposer-sim.json` | `SpectroscopyProposerTests` | yes (`SpectroGoldenTests`) |
| `eds-realistic-l-sim.json` | `SpectroscopyFitRangeTests+Spectro` | yes (`SpectroGoldenTests`, `SpectroscopyFitRangeTests`) |
| `eds-unlisted-sim.json` | `SpectroscopyUnlistedLineTests+Spectro` | yes (`SpectroGoldenTests`, `SpectroscopyUnlistedLineTests`) |
| `eds-weakline-sim.json` | `SpectroscopyFitTests`, `SpectroscopyFitRangeTests+Spectro` | yes (`SpectroGoldenTests`) |
| `qshape3.mac4dstem.h5` | `SpectrumImageOpeningTests+Spectro` (one assertion: the sniff calls it `.other`) | yes (`CR3ReviewFixTests`, `SpectrumImageOpeningTests`) |
| `velox-tiny.emd` | `SpectroCancellationTests`, `SpectroscopyDriveL10Tests`, `VeloxLockAndCancelTests`, `SpectrumImageOpeningTests+Spectro` | yes (`SpectroGoldenTests`, `SpectrumImageOpeningTests`) |

Staying only (not moved): `edx-regmismatch-m1.json` (`RegistrationTests`), `spectro-golden/` (6 files, `SpectroGoldenTests`).

Not under `Fixtures/`: the six CSVs of `mac4DSTEM/Resources/Spectroscopy` (`FFastMAC`, `Krause1979`, `LineWeights`, `SalvatXionA`, `SalvatXionB`, `xionUis`), reached by `#filePath`-relative `../mac4DSTEM/Resources/Spectroscopy` from `EDSQuantPinsTests`, `SpectroscopyAbsorptionTruthTests`, `SpectroscopyComputedKTests`, `SpectroscopyFitTests`, `SpectroscopyQuantTests` and `SpectroscopyQuantifyTests+Spectro`; they must become `Bundle.module` resources at extraction (slot plan section 6). Moving tests also name, but do not require, files outside the repo: `example_velox_EELS_EDS.emd` and `velox-missing-file.emd` appear in `VeloxEMDReaderTests` only as comment or as a path that must not exist.


## Gate (in an isolated copy of `f01bec85` plus this change)

`xcodebuild test -only-testing:mac4DSTEMTests` (Debug, `CODE_SIGNING_ALLOWED=NO`), 2026-10-13, lane log `su/t1.log`: exit 0, `** TEST SUCCEEDED **`, **2 490 passed, 0 failed, 4 skipped = 2 494**, the declared count. Reconciliation by name: 2 494 declared at `f01bec85`, 2 494 declared after, 2 494 executed; declared-but-not-executed and executed-but-not-declared are both empty; the after set equals the before set once the ten new class names are mapped back to the old ones. The four skips are the existing environment skips (`TB1StallProbeTests.testOpeningWS2BesideItsSidecarCompletes`, `SpectroscopyViewModelTests.testRenderRoom`, `DiffractionEmbeddingTwoPassTests.testProfileSingleVersusTwoPass`, `SpectroGoldenTests.testRecordBaseline`). `SpectroGoldenTests.testOutputsAreByteIdenticalToTheBaseline` passed.

The partition has no new test to mutate. Its check is the compile gate, which went red on a real defect before it went green: the first split left a private `openedRoom()` helper (naming `AppState`, `SpectroscopyRoomController`) in `SpectroscopyQuantifyTests+Spectro.swift` and the DSTEMCore-only target refused it; the first run before that stopped on `@testable import mac4DSTEM` in `AutoIDRulesWP4bTests`.
