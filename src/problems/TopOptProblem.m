classdef (Abstract) TopOptProblem < handle
    %UNTITLED Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        fem
        weights
        computedWeights = false;
        
        designMin = 0;
        designMax = 1;
        
        options = struct(...
            'heavisideFilter', [], ...
            'designFilter', [], ...
            'filterRadius', [], ...
            'filterWeightFunction', [], ...
            'materials', [], ...
            'plot', [] ...
        );
        
        intermediateFunc
        heaviside
        iteration = 0;
    end
    
    properties(Access = protected)
        designFig
        curveFig
        designPlot
        curvePlots
        
        nbrConstraints
    end
    
    methods(Abstract)
        g = objective(obj, designPar)
        
        dgdphi = gradObjective(obj, designPar)
    end
    
    methods
        function obj = TopOptProblem(femModel, options, intermediateFunc)
            obj.fem = femModel;
            obj.nbrConstraints = numel(obj.nlopt_constraints);

            if nargin == 3
                obj.intermediateFunc = intermediateFunc;
            end
            
            if options.heavisideFilter
                obj.heaviside = HeavisideFilter(0.01, 0.5);
            end
            
            % Use indexing of obj.options to force similar structures
            obj.options(1) = options;
            obj.fem.assemble();
            
            if obj.options.plot
                obj.designFig = figure;
                if femModel.spatialDimensions == 2
                    title("Design at iteration 0");
                    obj.designPlot = plotDesign(femModel.Ex, femModel.Ey, femModel.designPar);
                end
                obj.curveFig = figure;
                obj.curvePlots = cell(1, 1 + obj.nbrConstraints);
                for i = 1:(1+obj.nbrConstraints)
                    subplot(1 + obj.nbrConstraints, 1, i);
                    obj.curvePlots{i} = plot(0, 0);
                    title("g_" + (i-1));
                end
            end
        end
        
        function [val, gradient] = nlopt_objective(obj, designPar)
            obj.iteration = obj.iteration + 1;
            
            designPar = reshape(designPar, [], size(obj.fem.Enod, 2));
            filteredPar = obj.filterParameters(designPar);

            disp("Calling objective function");
            val = obj.objective(filteredPar);
            
            if obj.options.plot
                figure(obj.curveFig);
                subplot(1 + numel(obj.nlopt_constraints), 1, 1)
                obj.curvePlots{1}.XData(end+1) = obj.iteration;
                obj.curvePlots{1}.YData(end+1) = val;

                if obj.fem.spatialDimensions == 2
                    figure(obj.designFig);
                    title("Design at iteration " + obj.iteration);
                    plotDesign(obj.fem.Ex, obj.fem.Ey, filteredPar, obj.designPlot);
                end
            end
            
            if obj.options.heavisideFilter
                obj.heaviside.update(filteredPar);
            end
            
            if ~isempty(obj.intermediateFunc)
                obj.intermediateFunc(obj.fem, filteredPar);
            end
            
            if nargout > 1
                gradient = obj.gradObjective(filteredPar);    
                gradient(:) = obj.filterGradient(gradient, designPar);
                gradient = reshape(gradient, 1, []);
            end
        end
        
        function [gs] = nlopt_constraints(obj)
            c = 0;
            gs = {};
            while ismethod(obj, "constraint" + (c+1))
                c = c + 1;
                gs{c} = @(varargin) obj.nlopt_constraint_i(c, varargin{:});
            end
        end
        
        function [val, gradient] = nlopt_constraint_i(obj, iConstraint, designPar)
            designPar = reshape(designPar, [], size(obj.fem.Enod, 2));
            filteredPar = obj.filterParameters(designPar);
            val = obj.("constraint" + iConstraint)(filteredPar);
            
            if obj.options.plot
                figure(obj.curveFig);
                subplot(1 + numel(obj.nlopt_constraints), 1, iConstraint+1)
                obj.curvePlots{iConstraint+1}.XData(end+1) = obj.iteration;
                obj.curvePlots{iConstraint+1}.YData(end+1) = val;
            end
            
            fprintf("Calling constraint(%d): %f\n", iConstraint, val);
            if (nargout > 1)
                gradient = obj.("gradConstraint" + iConstraint)(filteredPar);
                gradient(:) = obj.filterGradient(gradient, designPar);
                gradient = reshape(gradient, 1, []);
            end
        end
        
        function conf = getConfiguration(obj)
            conf = obj.options;
            conf.problemName = class(obj);
        end
        
        function filteredPar = filterParameters(obj, designPar)
            filteredPar = designPar;
            if obj.options.designFilter
                if ~obj.computedWeights
                    obj.weights = obj.fem.computeWeights(...
                        obj.options.filterRadius, ...
                        obj.options.filterWeightFunction)';
                    obj.computedWeights = true;
                end
                filteredPar = designPar * obj.weights;
            end
            
            if obj.options.heavisideFilter
                filteredPar = obj.heaviside.filter(filteredPar);
            end
        end
        
        function filteredGrad = filterGradient(obj, grad, designPar)
            filteredGrad = grad;
            filteredPar = designPar;
            if obj.options.designFilter
                if ~obj.computedWeights
                    obj.weights = obj.fem.computeWeights(...
                        obj.options.filterRadius, ...
                        obj.options.filterWeightFunction)';
                    obj.computedWeights = true;
                end

                filteredGrad = filteredGrad * obj.weights;
                filteredPar = filteredPar * obj.weights;
            end
            
            if obj.options.heavisideFilter
                filteredGrad = obj.heaviside.gradFilter(filteredPar).*filteredGrad;
                %filteredPar = obj.heaviside.filter(filteredPar);
            end
            %filteredGrad = 1./max(designPar, 0.01) .* obj.weights * (designPar.*grad);
        end
        
        function relErrors = testGradients(obj, designPar, h)
            if nargin < 3
                h = 1e-8;
            end
            dgdphi = numGrad(@obj.nlopt_objective, designPar, h);

            % Analytical gradient
            [~, der_g] = obj.nlopt_objective(designPar);
            objError = norm(dgdphi - der_g) / norm(dgdphi);
            c = 1;
            constraintFuncs = obj.nlopt_constraints;
            constraintErrors = zeros(size(constraintFuncs));
            for constraintFunc = constraintFuncs
                dgdphi = numGrad(constraintFunc{:}, designPar, h);
                [~, der_g] = constraintFunc{:}(designPar);
                constraintErrors(c) = norm(dgdphi - der_g) / norm(dgdphi);
                c = c + 1;
            end
            relErrors = [objError, constraintErrors];
        end
    end
end
