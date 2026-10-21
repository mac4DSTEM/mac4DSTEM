//
//  MaterialsProjectKitAmbiguity.swift
//  Interim: DiffractoKit 0.7.1 (DiffractoCore) exports the same names as the app's own Materials Project import
//  (`DSTEMCore`). A module-scope alias in this target shadows the imports, so a file that imports both keeps naming the
//  app's types. delete at the Materials Project switch to DiffractoKit 0.7.1 (open item DiffractoKit / MaterialsProjectImport).
//

import DSTEMCore

package typealias MaterialsProjectDocument = DSTEMCore.MaterialsProjectDocument
package typealias MaterialsProjectError = DSTEMCore.MaterialsProjectError
package typealias MaterialsProjectImport = DSTEMCore.MaterialsProjectImport
package typealias MaterialsProjectLattice = DSTEMCore.MaterialsProjectLattice
package typealias MaterialsProjectSite = DSTEMCore.MaterialsProjectSite
package typealias MaterialsProjectSpecies = DSTEMCore.MaterialsProjectSpecies
package typealias MaterialsProjectStructure = DSTEMCore.MaterialsProjectStructure
package typealias MaterialsProjectSummaryResponse = DSTEMCore.MaterialsProjectSummaryResponse
package typealias MaterialsProjectSymmetry = DSTEMCore.MaterialsProjectSymmetry
package typealias PhaseExpectation = DSTEMCore.PhaseExpectation
package typealias PhaseExpectationVerdict = DSTEMCore.PhaseExpectationVerdict

