clc; clear;

%% =========================
% LOAD MODEL
%% =========================
model = 'real_world_idmt_relay_3phase';
load_system(model);
set_param(model, 'FastRestart', 'off');
set_param(model, 'SimulationMode', 'normal');

%% =========================
% FIND FAULT BLOCK
%% =========================
fault_block = find_system(model, ...
    'LookUnderMasks', 'all', ...
    'FollowLinks',    'on',  ...
    'RegExp',         'on',  ...
    'Name',           '.*Fault.*');
if isempty(fault_block)
    error('No Fault block found in model.');
end
fault_block = fault_block{1};
fprintf("Using fault block: %s\n", fault_block);

%% =========================
% ENABLE SCOPE LOGGING
%% =========================
scopeA = [model '/Bus A Scope'];
scopeB = [model '/Bus B Scope1'];

set_param(scopeA, ...
    'DataLogging',             'on', ...
    'DataLoggingVariableName', 'ScopeData', ...
    'DataLoggingSaveFormat',   'Structure With Time');

set_param(scopeB, ...
    'DataLogging',             'on', ...
    'DataLoggingVariableName', 'ScopeData1', ...
    'DataLoggingSaveFormat',   'Structure With Time');

%% =========================
% DISABLE EXTERNAL MODE
%% =========================
set_param(fault_block, 'External',     'off');
set_param(fault_block, 'SwitchStatus', '0');
set_param(model, 'dirty', 'off');

%% =========================
% DIAGNOSTIC SIM
%% =========================
fprintf("Running diagnostic sim...\n");
simOut_test = sim(model, 'StopTime', '0.2');

fprintf("=== ScopeData (Bus A) signals ===\n");
for s = 1:length(simOut_test.ScopeData.signals)
    fprintf("  [%d] label='%s'  size=%s\n", s, ...
        simOut_test.ScopeData.signals(s).label, ...
        mat2str(size(simOut_test.ScopeData.signals(s).values)));
end

fprintf("=== ScopeData1 (Bus B) signals ===\n");
for s = 1:length(simOut_test.ScopeData1.signals)
    fprintf("  [%d] label='%s'  size=%s\n", s, ...
        simOut_test.ScopeData1.signals(s).label, ...
        mat2str(size(simOut_test.ScopeData1.signals(s).values)));
end

%% =========================
% SET AFTER READING DIAGNOSTIC
%% =========================
I_sig_idx = 1;   % ← adjust after seeing diagnostic
V_sig_idx = 2;   % ← adjust after seeing diagnostic

%% =========================
% FAULT PATTERNS [A B C G]
%% =========================
fault_matrix = [
    1 0 0 1;
    0 1 0 1;
    0 0 1 1;
    1 1 0 0;
    0 1 1 0;
    1 0 1 0;
    1 1 1 0;
];

%% =========================
% PRE-ALLOCATE
%% =========================
N          = 200;
data       = zeros(N, 11);
failedRuns = [];
SIM_STOP   = 0.2;
SIM_STOP_S = num2str(SIM_STOP);

%% =========================
% MAIN LOOP
%% =========================
for k = 1:N
    try
        fRow    = fault_matrix(randi(size(fault_matrix,1)), :);
        A = fRow(1); B = fRow(2); C = fRow(3); G = fRow(4);

        Rf      = 0.01 + rand() * 4.99;
        Rg      = 0.01;
        t_start = 0.05 + rand() * 0.05;
        t_end   = t_start + 0.05;

        set_param(fault_block, ...
            'FaultA',           onoff(A),                               ...
            'FaultB',           onoff(B),                               ...
            'FaultC',           onoff(C),                               ...
            'GroundFault',      onoff(G),                               ...
            'SwitchTimes',      sprintf('[%.6f %.6f]', t_start, t_end), ...
            'FaultResistance',  num2str(Rf),                            ...
            'GroundResistance', num2str(Rg),                            ...
            'External',         'off');
        set_param(model, 'dirty', 'off');

        simOut = sim(model, 'StopTime', SIM_STOP_S);

        Iabc = simOut.ScopeData.signals(I_sig_idx).values;
        Vabc = simOut.ScopeData.signals(V_sig_idx).values;

        Ia = Iabc(:,1); Ib = Iabc(:,2); Ic = Iabc(:,3);
        Va = Vabc(:,1); Vb = Vabc(:,2); Vc = Vabc(:,3);

        Nsig = length(Ia);
        i1   = max(1,    floor(t_start / SIM_STOP * Nsig));
        i2   = min(Nsig, i1 + round(0.02 * Nsig));
        if i2 <= i1, i2 = min(Nsig, i1+10); end

        feat = [
            rms(Ia(i1:i2)), rms(Ib(i1:i2)), rms(Ic(i1:i2)), ...
            rms(Va(i1:i2)), rms(Vb(i1:i2)), rms(Vc(i1:i2))
        ];

        data(k,:) = [feat, A, B, C, G, Rf];
        fprintf("[%3d/%d] OK  | Fault=[%d%d%d%d]  Rf=%.3f Ohm  t=[%.3f,%.3f]s\n", ...
            k, N, A, B, C, G, Rf, t_start, t_end);

    catch ME
        fprintf("[%3d/%d] FAIL: %s\n", k, N, ME.message);
        failedRuns(end+1) = k; %#ok<SAGROW>
        data(k,:) = NaN;
    end
end

%% =========================
% SAVE CSV
%% =========================
validMask = ~any(isnan(data), 2);
data      = data(validMask, :);
fprintf("\nValid samples: %d / %d\n", sum(validMask), N);
if ~isempty(failedRuns)
    fprintf("Failed at: %s\n", num2str(failedRuns));
end

T = array2table(data, 'VariableNames', ...
    {'Ia_rms','Ib_rms','Ic_rms', ...
     'Va_rms','Vb_rms','Vc_rms', ...
     'FaultA','FaultB','FaultC','Ground','Rf'});
writetable(T, 'fault_dataset.csv');
fprintf("\nDONE: fault_dataset.csv saved with %d samples.\n", height(T));

%% =========================
% LOCAL FUNCTION
%% =========================
function s = onoff(x)
    opts = {'off','on'};
    s = opts{x+1};
end
