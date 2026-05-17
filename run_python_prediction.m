function y = run_python_prediction(features)

persistent t IA_avg IB_avg IC_avg

if isempty(t)
    t = 0;
    IA_avg = 0;
    IB_avg = 0;
    IC_avg = 0;
end

t = t + 1;

% Smooth with exponential moving average (alpha=0.01 = heavy smoothing)
alpha = 0.01;
IA_avg = (1-alpha)*IA_avg + alpha*(abs(features(1))/sqrt(2));
IB_avg = (1-alpha)*IB_avg + alpha*(abs(features(2))/sqrt(2));
IC_avg = (1-alpha)*IC_avg + alpha*(abs(features(3))/sqrt(2));

if t < 500
    y = 0;
    return
end

IA = IA_avg;
IB = IB_avg;
IC = IC_avg;

Iavg = (IA + IB + IC) / 3;
Imax = max([IA IB IC]);
Imin = min([IA IB IC]);

thresh = 0.4 * Iavg;

A_fault = abs(IA - Iavg) > thresh;
B_fault = abs(IB - Iavg) > thresh;
C_fault = abs(IC - Iavg) > thresh;
num_faults = A_fault + B_fault + C_fault;

ground = (Imax - Imin) > (0.3 * Iavg);

y = 0;

if num_faults == 0
    y = 0;
elseif num_faults == 3
    y = 1;
elseif num_faults == 1
    y = 2;
elseif num_faults == 2 && ground
    y = 4;
elseif num_faults == 2 && ~ground
    y = 3;
end

end