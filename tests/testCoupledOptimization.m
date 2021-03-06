function testCoupledOptimization()
jobManager = JobManager();

opt.maxtime = 5*60;
opt.verbose = 1;
opt.ftol_rel = 1e-6;
%opt.xtol_abs = 1e-7*ones(size(fem.mainDensities));
opt.algorithm = NLOPT_LD_MMA;

timeSteps = 20;
volumeFraction = 0.2;
radius = 1e-5;
P = 1;
k = 500e7;
tFinal = 0.2;

void = Material(1, 1e7, 0.01, 1e3, 0.4, 0);
copper = Material(8900, 390, 402, 130e9, 0.355, 23e-5);
aluminium = Material(2700, 240, 88, 70e9, 0.335, 16e-5);
materials = [void, aluminium, copper];

%%
width = 5e-4;
height = 2.5e-4;
mesh = StructuredMesh([17, width], [9, height]);
globalCoord = mesh.coordinates();

topAndLeftNodes = find(globalCoord(1, :) == 0 | ...
    globalCoord(2, :) == height);
topCornerExpanded = find(globalCoord(2, :) == height & ...
    globalCoord(1, :) <= width/25);
bottomNodes = find(globalCoord(2, :) == 0);
rightCornerExpanded = find(globalCoord(1, :) == width & globalCoord(2, :) < height/25);

% Create boundary conditions
fixed = struct(...
    'nodes', topAndLeftNodes, ...
    'type', 'Dirichlet', ...
    'value', 0, ...
    'components', [1, 1], ...
    'timeSteps', 1:timeSteps ...
    );

symmetry = struct(...
    'nodes', bottomNodes, ...
    'type', 'Dirichlet', ...
    'value', 0, ...
    'components', [0, 1], ...
    'timeSteps', 1:timeSteps ...
    );

output = struct( ...
    'nodes', rightCornerExpanded, ...
    'type', 'dummy', ...
    'name', 'josse', ...
    'value', 1e6, ...
    'components', [1, 0], ...
    'timeSteps', timeSteps ...
    );

spring = struct( ...
    'nodes', rightCornerExpanded, ...
    'type', 'Robin', ...
    'value', k, ...
    'components', [1, 0], ...
    'timeSteps', 1:timeSteps ...
    );

tempPrescribed = struct( ...
    'nodes', rightCornerExpanded, ...
    'type', 'Dirichlet', ...
    'value', 0, ...
    'timeSteps', 1:timeSteps ...
    );

heatInput = struct(...
    'nodes', topCornerExpanded, ...
    'type', 'Neumann', ...
    'value', 100, ...
    'timeSteps', 1:timeSteps ...
    );

% Create body conditions
body = struct(...
    'type', 'main' ...
    );

mechFEM = OptMechFEMStructured(numel(materials), mesh, timeSteps, "plane stress");

mechFEM.addBoundaryCondition(fixed);
mechFEM.addBoundaryCondition(symmetry);
mechFEM.addBoundaryCondition(output);
mechFEM.addBoundaryCondition(spring);
mechFEM.addBodyCondition(body);

mechFEM.setMaterial(copper);
massLimit = volumeFraction * sum(mechFEM.volumes*aluminium.density);

options = struct(...
    'heavisideFilter', false, ...
    'designFilter', true, ...
    'filterRadius', radius, ...
    'filterWeightFunction', @(dx, dy, dz) max(radius-sqrt(dx.^2+dy.^2+dz.^2), 0), ...
    'materials', materials, ...
    'plot', false ...
    );

%%
p_E = 1;
p_kappa = 1;
p_cp = 1;
for p_alpha = [1]
    heatFEM_i = OptThermoMechStructured(mechFEM, numel(materials), mesh, tFinal, timeSteps, 1);
    
    heatFEM_i.addBoundaryCondition(tempPrescribed);
    heatFEM_i.addBoundaryCondition(heatInput);
    heatFEM_i.addBodyCondition(body);
    
    heatFEM_i.setMaterial(copper);
    
    [E, EDer, alpha, alphaDer] = MechSIMP(materials, p_E, p_alpha);
    heatFEM_i.mechFEM.addInterpFuncs(E, EDer, alpha, alphaDer);
    
    [kappaF, kappaFDer, cp, cpDer] = HeatSIMP(materials, p_kappa, p_cp);
    heatFEM_i.addInterpFuncs(kappaF, kappaFDer, cp, cpDer);
    
    coupledFEM = heatFEM_i;
    topOpt = ThermallyActuatedProblem(coupledFEM, options, massLimit);
    initial = volumeFraction*ones(size(heatFEM_i.designPar));
    
    job = Job(topOpt, initial, opt);
    jobManager.add(job);
end
%%
jobManager.runAll();
%%
jobManager.plotAll();
end