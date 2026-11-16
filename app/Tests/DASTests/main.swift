import DASCore
import Foundation

let t = TestRunner()
runCatalogTests(t)
runStatusTests(t)
runPlanningTests(t)
runPlumbingTests(t)
runCLITests(t)
runOutputTests(t)
runAuditTests(t)
runAdapterTests(t)
exit(t.finish())
