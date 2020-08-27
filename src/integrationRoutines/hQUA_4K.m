function [Ke] = hQUA_4K(ex, ey, D, t, integrationRule)
ex = reshape(ex, [], 1);
ey = reshape(ey, [], 1);

if nargin < 5
    integrationRule = 2;
end
nbrGaussPnts = integrationRule^2;
gaussPoints = zeros(nbrGaussPnts, 2);
weights = zeros(nbrGaussPnts, 1);

if integrationRule == 1
    oneDimGaussPnts = 0;
    oneDimWeights = 2;
elseif integrationRule == 2
    oneDimGaussPnts = [-0.577350269189626, 0.577350269189626];
    oneDimWeights = [1, 1];
elseif integrationRule == 3
    oneDimGaussPnts = [-0.7745966692414834, 0, 0.7745966692414834];
    oneDimWeights = [0.5555555555555556, 0.8888888888888888, 0.5555555555555556];
else
    error('Used number of integration points not implemented');
end

i = 1;
for x = oneDimGaussPnts
    for y = oneDimGaussPnts
        gaussPoints(i, :) = [x, y];
        i = i + 1;
    end
end

% Product of the weights in each dimension (for each point)
i = 1;
for wx = oneDimWeights
    for wy = oneDimWeights
        weights(i) = wx*wy;
        i = i + 1;
    end
end

xi = gaussPoints(:,1);
eta = gaussPoints(:,2);

% Have every chunk of 2 rows below to one gaussian point
dNr = zeros(2*nbrGaussPnts, 4);
dNr(1:2:end, [1 3]) = dNr(1:2:end, [1 3]) + eta/4;
dNr(1:2:end, [2 4]) = dNr(1:2:end, [2 4]) - eta/4;
dNr(1:2:end, [2 3]) = dNr(1:2:end, [2 3]) + 1/4;
dNr(1:2:end, [1 4]) = dNr(1:2:end, [1 4]) - 1/4;

dNr(2:2:end, [1 3]) = dNr(2:2:end, [1 3]) + xi/4;
dNr(2:2:end, [2 4]) = dNr(2:2:end, [2 4]) - xi/4;
dNr(2:2:end, [1 2]) = dNr(2:2:end, [1 2]) - 1/4;
dNr(2:2:end, [3 4]) = dNr(2:2:end, [3 4]) + 1/4;

Ke = zeros(4,4);
B = zeros(2, 4);
JT = dNr*[ex, ey];
index = zeros(1, 2);

for i = 1:nbrGaussPnts
    index(:) = (1:2) + 2*(i-1);
    detJ = abs(det(JT(index, :)));
    B(:) = JT(index, :) \ dNr(index, :);
    Ke(:) = Ke + B' * D * B * detJ * weights(i) * t;
end
end
