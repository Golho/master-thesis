clear; close all;

global mechFEM
global materials
global mesh
global tempPrescribed
global body
global opt
global jobManager
global timeSteps
global stiffFEM

jobManager = JobManager();
jobs = Job.empty();

opt.maxtime = 20*60;
opt.verbose = 1;
opt.ftol_rel = 1e-6;
%opt.xtol_abs = 1e-7*ones(size(fem.mainDensities));
opt.algorithm = NLOPT_LD_MMA;

timeSteps = 50;
angle = pi/4;
k = 1e6;

void = Material(9.3, 1.9e5, 1e-3, 1.1e3, 0.45, 0);
material_1 = Material(930, 1.9e3, 22, 1.1e9, 0.45, 2e-5);
material_2 = Material(930, 1.9e3, 22, 1.1e9, 0.45, 8e-5);
materials = [void, material_1, material_2];
%% Define the geometry
width = 0.1;
height = 0.1;
mesh = StructuredMesh([61, width], [61, height]);
globalCoord = mesh.coordinates();


topAndLeftNodes = find(globalCoord(1, :) == 0 | ...
    globalCoord(2, :) == height);
topRightNode = find(globalCoord(1, :) == height & globalCoord(2, :) == width);
topCornerExpanded = find(globalCoord(2, :) == height & ...
    globalCoord(1, :) <= width/25);
bottomNodes = find(globalCoord(2, :) == 0);
rightCornerExpanded = find((globalCoord(1, :) >= width*9/10 & globalCoord(2, :) == 0) | ...
                           (globalCoord(2, :) <= height/10 & globalCoord(1, :) == width));
rightCorner = find(globalCoord(1, :) >= width*9/10 & globalCoord(2, :) == 0);

% Create boundary conditions
fixed = struct(...
    'nodes', rightCornerExpanded, ...
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
    'nodes', topRightNode, ...
    'type', 'dummy', ...
    'name', 'josse', ...
    'value', -cos(angle)*1e4, ...
    'components', [1, 0], ...
    'timeSteps', timeSteps ...
);

output2 = struct( ...
    'nodes', topRightNode, ...
    'type', 'dummy', ...
    'name', 'josse', ...
    'value', sin(angle)*1e4, ...
    'components', [0, 1], ...
    'timeSteps', timeSteps ...
);

spring = struct( ...
    'nodes', topRightNode, ...
    'type', 'Robin', ...
    'value', k, ...
    'components', [1, 0], ...
    'timeSteps', 1:timeSteps ...
);

tempPrescribed = struct( ...
    'nodes', rightCorner, ...
    'type', 'Dirichlet', ...
    'value', 100, ...
    'timeSteps', 1:timeSteps ...
);


% Create body conditions
body = struct(...
    'type', 'main' ...
);

stiffFEM = OptMechFEMStructured(numel(materials), mesh, 1, "plane stress");

fixed2 = struct(...
    'nodes', rightCornerExpanded, ...
    'type', 'Dirichlet', ...
    'value', 0, ...
    'components', [1, 0], ...
    'timeSteps', 1 ...
);

symmetry2 = struct(...
    'nodes', bottomNodes, ...
    'type', 'Dirichlet', ...
    'value', 0, ...
    'components', [0, 1], ...
    'timeSteps', 1 ...
);

retention = struct( ...
    'nodes', topRightNode, ...
    'type', 'Neumann', ...
    'value', 100, ...
    'components', [1, 0], ...
    'timeSteps', 1 ...
);

stiffFEM.addBoundaryCondition(fixed2);
stiffFEM.addBoundaryCondition(symmetry2);
stiffFEM.addBoundaryCondition(retention);

% Create the FEM model and add the boundary/body conditions
mechFEM = OptMechFEMStructured(numel(materials), mesh, timeSteps, "plane stress");

mechFEM.addBoundaryCondition(fixed);
mechFEM.addBoundaryCondition(symmetry);
mechFEM.addBoundaryCondition(output);
mechFEM.addBoundaryCondition(spring);
%mechFEM.addBoundaryCondition(output2);
mechFEM.addBodyCondition(body);


%%
opt.maxeval = 70;

p_cp = 3;
p_kappa = 3;
p_E = 3;
p_alpha = 3;

addJob(600, p_cp, p_kappa, p_E, p_alpha);

%%

%%
%jobManager.runAndSaveAll();
jobManager.runAll();
%%
jobManager.plotAll();
%%
% saveAnswer = questdlg("Would you like to save all jobs?", "Yes", "No");
% switch saveAnswer
%     case "Yes"
%         jobManager.saveAll();
%     case "No"
%         disp("Did not save the jobs");
% end

function addJob(tFinal, p_cp, p_kappa, p_E, p_alpha)
    global mechFEM
    global materials
    global mesh
    global tempPrescribed
    global body
    global opt
    global jobManager
    global timeSteps
    global stiffFEM

    radius = 0.005;
    u_max = 0.002;
    volumeFraction = 0.3;
    
    massLimit = volumeFraction * sum(mechFEM.volumes*materials(2).density);
    
    heatFEM_i = OptThermoMechStructured(mechFEM, numel(materials), mesh, tFinal, timeSteps, 1);

    heatFEM_i.addBoundaryCondition(tempPrescribed);
    heatFEM_i.addBodyCondition(body);

    [E, EDer, alpha, alphaDer] = MechSIMP(materials, p_E, p_alpha);
    heatFEM_i.mechFEM.addInterpFuncs(E, EDer, alpha, alphaDer);
    stiffFEM.addInterpFuncs(E, EDer, alpha, alphaDer);

    [kappaF, kappaFDer, cp, cpDer] = HeatSIMP(materials, p_kappa, p_cp);
    heatFEM_i.addInterpFuncs(kappaF, kappaFDer, cp, cpDer);

    coupledFEM = heatFEM_i;
    
        options = struct(...
            'heavisideFilter', false, ...
            'designFilter', true, ...
            'filterRadius', radius, ...
            'filterWeightFunction', @(dx, dy, dz) max(radius-sqrt(dx.^2+dy.^2+dz.^2), 0), ...
            'materials', materials, ...
            'plot', true ...
            );
        topOpt = ThermallyActuatedProblem3(coupledFEM, stiffFEM, options, massLimit, u_max);

        initial = volumeFraction * ones(size(heatFEM_i.designPar));
        %initial(1, :) = 0.1;
        initial(2, :) = 0.5;

        job = Job(topOpt, initial, opt);
        jobManager.add(job);
end