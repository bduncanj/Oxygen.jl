module RunTests 

include("constants.jl"); using .Constants
include("test_utils.jl"); using .TestUtils

#### Extension Tests ####

include("extensions/timezonetests.jl")
include("extensions/templatingtests.jl")
include("extensions/protobuf/protobuftests.jl")
include("extensions/cairomakietests.jl")
include("extensions/wglmakietests.jl")
include("extensions/bonitotests.jl")

#### Sepcial Handler Tests ####

include("ssetests.jl")
include("websockettests.jl")
include("streamingtests.jl")
include("handlertests.jl")

#### Core Tests ####
include("test_reexports.jl")
include("precompilationtest.jl")
include("autodoctests.jl")
include("extractortests.jl")
include("reflectiontests.jl")
include("metricstests.jl")
include("routingfunctionstests.jl")
include("rendertests.jl")
include("bodyparsertests.jl")
include("crontests.jl")
include("oxidise.jl")
include("instancetests.jl")
include("paralleltests.jl")
include("taskmanagement.jl")
include("cronmanagement.jl")
include("middlewaretests.jl")
include("appcontexttests.jl")
include("originaltests.jl")
include("revise.jl")

#### Scenario Tests ####
include("./scenarios/thunderingherd.jl")

end 
