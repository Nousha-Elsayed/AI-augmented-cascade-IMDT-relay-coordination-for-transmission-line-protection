%% ============================================================
%  generate_fault_dataset.m  — FIXED + FAST
%
%  HOW IT'S FAST:
%    Old way: 500 simulations × 0.6s each = ~40–90 min
%    New way: 1 long simulation per fault config, extract 50+ windows
%             Total: ~20 simulations = ~2–5 min
%
%  HOW IT'S FIXED:
%    Fix 1: Window extracted AFTER fault (t_fault + 1 cycle), not before
%    Fix 2: Normal records have load variation so they're not identical
%    Fix 3: Voltage signal check built in — warns if values look wrong
%
%  REQUIRES 9 To-Workspace blocks (Save format = Array, Sample time = -1):
%    IbusA_A, IbusA_B, IbusA_C   Bus A currents
%    IbusB_A, IbusB_B, IbusB_C   Bus B currents
%    VbusB_A, VbusB_B, VbusB_C   Bus B voltages (must be LINE voltage, ~6350V)
% ============================================================

clear; clc;
fprintf('=== Fault Dataset Generator — FIXED + FAST ===\n\n');

%% ── 1. Configuration ─────────────────────────────────────────
MODEL_NAME  = 'real_world_idmt_relay_3phase_for_dataset';
FAULT_BLOCK = [MODEL_NAME '/Three-Phase Fault1'];

% One long simulation: fault ON at 0.1s, stays ON until end
% We extract many 128-sample windows from the fault period
T_FAULT_ON   = 0.1;     % s — fault starts here
T_SIM        = 2.0;     % s — long sim (gives ~90 cycles of fault data to sample)
Fs           = 3200;    % Sa/s
WINDOW_LEN   = 128;     % samples = 2 cycles at 50 Hz
WINDOW_STEP  = 64;      % samples between windows (50% overlap = more diversity)
F_NOMINAL    = 50;

% How many windows to extract per simulation
% (T_SIM - T_FAULT_ON) × Fs / WINDOW_STEP = available windows
% We take a random subset for diversity
WINDOWS_PER_SIM = 25;   % windows extracted per fault simulation

% Per-unit bases
Ibase_A = (10e6) / (sqrt(3) * 11e3);   % 524.86 A
Vbase_V = (11e3) / sqrt(3);            % 6350.9 V (phase-to-ground)
fprintf('Ibase = %.2f A\n', Ibase_A);
fprintf('Vbase = %.2f V\n\n', Vbase_V);

%% ── 2. Fault types ───────────────────────────────────────────
FAULT_TYPES = struct( ...
    'label', {'3LG',   'SLG_A',  'LL_BC',  'DLG_BC' }, ...
    'A',     { true,    true,     false,    false    }, ...
    'B',     { true,    false,    true,     true     }, ...
    'C',     { true,    false,    true,     true     }, ...
    'G',     { false,   true,     false,    true     }  );

% Fault resistances — fewer values, more windows per sim = same total data
FAULT_RESISTANCES = [0.01, 1, 3, 7, 15];   % 5 values (was 20)
SECTION_LABELS    = [2 2 2 2 2];            % all Bus C faults = Section 2

%% ── 3. Feature names ─────────────────────────────────────────
featureNames = { ...
    'Ib_A_rms_pu','Ib_B_rms_pu','Ib_C_rms_pu', ...
    'Ib_pos_pu','Ib_neg_pu','Ib_zer_pu', ...
    'Ib_neg_pos','Ib_zer_pos', ...
    'Ib_ang_pos','Ib_ang_neg','Ib_ang_zer', ...
    'Ib_dA_pu','Ib_dB_pu','Ib_dC_pu', ...
    'Ib_pkA_pu','Ib_pkB_pu','Ib_pkC_pu', ...
    'Ib_thd2','Ib_thd5', ...
    'window_time_s','wavelet_energy_pu', ...
    'Ia_A_rms_pu','Ia_B_rms_pu','Ia_C_rms_pu', ...
    'Ia_pos_pu','Ia_neg_pu','Ia_zer_pu', ...
    'Vb_A_rms_pu','Vb_B_rms_pu','Vb_C_rms_pu', ...
    'Vb_pos_pu','Vb_neg_pu','Vb_zer_pu', ...
    'Vb_neg_pos','Vb_zer_pos', ...
    'Vb_ang_pos','Vb_ang_neg','Vb_ang_zer', ...
    'ZbusB_pos_pu', ...
    'rms_ratio_IaIb','section_label','fault_resistance_ohm'};

nFT      = numel(FAULT_TYPES);
nRf      = numel(FAULT_RESISTANCES);
nFault   = nFT * nRf * WINDOWS_PER_SIM;   % 4×5×25 = 500 fault records
nNorm    = 200;                            % normal records with load variation

results  = nan(nNorm + nFault, numel(featureNames) + 1);
recIdx   = 0;

%% ── 4. Load model ────────────────────────────────────────────
fprintf('Loading model: %s\n', MODEL_NAME);
load_system(MODEL_NAME);
set_param(MODEL_NAME, 'ReturnWorkspaceOutputs', 'off');

%% ── 5. Signal test ───────────────────────────────────────────
fprintf('Running signal test...\n');
disableFault(FAULT_BLOCK);
set_param(MODEL_NAME, 'StopTime', '0.3');
sim(MODEL_NAME);

required = {'IbusA_A','IbusA_B','IbusA_C','IbusB_A','IbusB_B','IbusB_C','VbusB_A','VbusB_B','VbusB_C'};
missing = {};
for k = 1:numel(required)
    if ~evalin('base', ['exist(''' required{k} ''',''var'')'])
        missing{end+1} = required{k};
    end
end
if ~isempty(missing)
    allVars = evalin('base','who');
    fprintf('[!] Missing: %s\n', strjoin(missing,', '));
    fprintf('    Found: %s\n', strjoin(allVars,', '));
    error('Fix missing To-Workspace blocks first.');
end

% ── CRITICAL: Check voltage magnitude ────────────────────────
[VbA,~,~] = getSignals('VbusB', 0.05, WINDOW_LEN);
V_rms_actual = rms(VbA);
V_rms_pu     = V_rms_actual / Vbase_V;
fprintf('\nVoltage sanity check:\n');
fprintf('  VbusB_A RMS = %.2f  (in whatever units your block uses)\n', V_rms_actual);
fprintf('  As pu of %.0f V = %.4f pu\n', Vbase_V, V_rms_pu);
if V_rms_pu < 0.1
    fprintf('\n  [!] WARNING: Voltage is %.4f pu — this is WAY too small.\n', V_rms_pu);
    fprintf('      VbusB_A/B/C are NOT connected to bus voltage.\n');
    fprintf('      They are probably tapped from a current measurement output.\n');
    fprintf('      FIX: Connect VbusB blocks to a Three-Phase V Measurement\n');
    fprintf('           block wired directly to the Bus B line.\n');
    fprintf('      Continuing without voltage features (Vb columns = 0)...\n\n');
    USE_VOLTAGE = false;
elseif V_rms_pu > 0.8 && V_rms_pu < 1.3
    fprintf('  [OK] Voltage looks correct (%.3f pu)\n\n', V_rms_pu);
    USE_VOLTAGE = true;
else
    fprintf('  [?] Voltage is %.4f pu — unusual, check units.\n\n', V_rms_pu);
    USE_VOLTAGE = true;
end

%% ── 6. Normal records — WITH LOAD VARIATION ─────────────────
fprintf('Simulating normal records with load variation...\n');
set_param(MODEL_NAME, 'StopTime', '0.5');
disableFault(FAULT_BLOCK);

% Find the load block to vary it
% Common names — update if yours is different
LOAD_BLOCK = '';
possible_loads = {[MODEL_NAME '/3-Phase Series RLC Load'], ...
                  [MODEL_NAME '/Load'], ...
                  [MODEL_NAME '/Three-Phase Series RLC Load']};
for k = 1:numel(possible_loads)
    try
        get_param(possible_loads{k}, 'BlockType');
        LOAD_BLOCK = possible_loads{k};
        fprintf('  Found load block: %s\n', LOAD_BLOCK);
        break;
    catch; end
end

% Get original load power for restoration later
if ~isempty(LOAD_BLOCK)
    try
        orig_P = get_param(LOAD_BLOCK, 'ActivePower');
    catch
        LOAD_BLOCK = '';   % can't set it, skip variation
    end
end

for n = 1:nNorm
    try
        % Vary load ±20% for diversity
        if ~isempty(LOAD_BLOCK)
            scale  = 0.8 + 0.4*rand();   % 0.8 to 1.2
            newP   = num2str(str2double(orig_P) * scale);
            set_param(LOAD_BLOCK, 'ActivePower', newP);
        end

        sim(MODEL_NAME);

        % Extract window from steady-state (random time between 0.1–0.4s)
        t_win = 0.1 + 0.3*rand();
        [IaA,IaB,IaC] = getSignals('IbusA', t_win, WINDOW_LEN);
        [IbA,IbB,IbC] = getSignals('IbusB', t_win, WINDOW_LEN);
        [VbA,VbB,VbC] = getSignals('VbusB', t_win, WINDOW_LEN);

        feats = buildFeatures(IaA,IaB,IaC, IbA,IbB,IbC, VbA,VbB,VbC, ...
                              Fs,F_NOMINAL,Ibase_A,Vbase_V, t_win,1e6,2, USE_VOLTAGE);
        recIdx = recIdx + 1;
        results(recIdx,:) = [feats, 0];

        if mod(n,50)==0, fprintf('  %d/%d normal done\n',n,nNorm); end
    catch ME
        fprintf('  [SKIP] Normal #%d: %s\n', n, ME.message);
    end
end

% Restore original load
if ~isempty(LOAD_BLOCK)
    set_param(LOAD_BLOCK, 'ActivePower', orig_P);
end
fprintf('  Captured: %d normal records\n\n', recIdx);

%% ── 7. Fault records — ONE LONG SIM, MANY WINDOWS ───────────
fprintf('Simulating fault records (1 long sim per config)...\n');
set_param(MODEL_NAME, 'StopTime', num2str(T_SIM));

% Available fault window: T_FAULT_ON+2cycles to T_SIM-2cycles
t_fault_start = T_FAULT_ON + 3/F_NOMINAL;   % skip 3 cycles after fault for transient to develop
t_fault_end   = T_SIM - 2/F_NOMINAL;
t_range       = t_fault_end - t_fault_start;

for ft = 1:nFT
    ftype  = FAULT_TYPES(ft);
    ftCode = ft;

    for ri = 1:nRf
        Rf     = FAULT_RESISTANCES(ri);
        secLbl = SECTION_LABELS(ri);

        % Apply fault — stays ON for entire simulation
        set_param(FAULT_BLOCK,'FaultA',          onoff(ftype.A));
        set_param(FAULT_BLOCK,'FaultB',          onoff(ftype.B));
        set_param(FAULT_BLOCK,'FaultC',          onoff(ftype.C));
        set_param(FAULT_BLOCK,'GroundFault',     onoff(ftype.G));
        set_param(FAULT_BLOCK,'SwitchTimes',     ...
                  ['[' num2str(T_FAULT_ON) ' 999]']);   % ON at 0.1s, never turns off
        set_param(FAULT_BLOCK,'FaultResistance',  num2str(Rf));
        set_param(FAULT_BLOCK,'GroundResistance', num2str(max(Rf,0.01)));

        try
            sim(MODEL_NAME);   % ONE simulation

            % Pull all signal data once (efficient)
            [IaA_full, IaB_full, IaC_full, t] = getSignalsFull('IbusA');
            [IbA_full, IbB_full, IbC_full, ~]  = getSignalsFull('IbusB');
            [VbA_full, VbB_full, VbC_full, ~]  = getSignalsFull('VbusB');

            % Extract WINDOWS_PER_SIM random windows from the fault period
            % Random sampling gives diverse inception angles automatically
            t_starts = t_fault_start + rand(1, WINDOWS_PER_SIM) * t_range;

            for w = 1:WINDOWS_PER_SIM
                t_win = t_starts(w);
                [~,i0] = min(abs(t - t_win));
                i1 = min(i0+WINDOW_LEN-1, numel(IbA_full));
                i0 = max(1, i1-WINDOW_LEN+1);
                idx = i0:i1;

                IaA = IaA_full(idx); IaB = IaB_full(idx); IaC = IaC_full(idx);
                IbA = IbA_full(idx); IbB = IbB_full(idx); IbC = IbC_full(idx);
                VbA = VbA_full(idx); VbB = VbB_full(idx); VbC = VbC_full(idx);

                feats = buildFeatures(IaA,IaB,IaC, IbA,IbB,IbC, VbA,VbB,VbC, ...
                                      Fs,F_NOMINAL,Ibase_A,Vbase_V, t_win,Rf,secLbl, USE_VOLTAGE);
                recIdx = recIdx + 1;
                results(recIdx,:) = [feats, ftCode];
            end

            fprintf('  ✓ %s Rf=%.2f — %d windows extracted\n', ...
                    ftype.label, Rf, WINDOWS_PER_SIM);

        catch ME
            fprintf('  [SKIP] %s Rf=%.2f: %s\n', ftype.label, Rf, ME.message);
        end
    end
end

%% ── 8. Save ──────────────────────────────────────────────────
results = results(1:recIdx,:);
T = array2table(results, 'VariableNames', [featureNames,{'fault_class'}]);
writetable(T,'fault_dataset.csv');

nN=sum(results(:,end)==0); nF=sum(results(:,end)>0);
fprintf('\n✓ Saved fault_dataset.csv\n');
fprintf('  Total=%d  Normal=%d  Fault=%d\n\n', recIdx, nN, nF);

%% ── 9. Sanity check plots ────────────────────────────────────
figure('Name','Dataset Quality Check','Color','w');

subplot(1,3,1);
histogram(categorical(results(:,end),0:4,{'Normal','3LG','SLG','LL','DLG'}));
title('Class distribution'); grid on;

subplot(1,3,2);
% Check that features differ between classes
classes = results(:,end);
feat_idx = 4;   % Ib_pos_pu
hold on;
for c = 0:4
    mask = classes==c;
    if sum(mask)>0
        histogram(results(mask,feat_idx), 20, 'DisplayName', ...
            {'Normal','3LG','SLG','LL','DLG'}{c+1});
    end
end
xlabel('Ib\_pos\_pu'); title('Class separation check');
legend; grid on;

subplot(1,3,3);
feat_idx2 = 7;  % Ib_neg_pos (neg/pos ratio — key discriminator)
hold on;
for c = 0:4
    mask = classes==c;
    if sum(mask)>0
        histogram(results(mask,feat_idx2), 20, 'DisplayName', ...
            {'Normal','3LG','SLG','LL','DLG'}{c+1});
    end
end
xlabel('Ib\_neg\_pos ratio'); title('Key discriminating feature');
legend; grid on;

fprintf('Check the plots — classes should show DIFFERENT distributions.\n');
fprintf('If all classes overlap completely, the window extraction is still wrong.\n');

%% ============================================================
%  LOCAL FUNCTIONS
%% ============================================================

function disableFault(block)
    set_param(block,'FaultA','off','FaultB','off','FaultC','off', ...
              'GroundFault','off','SwitchTimes','[99 100]', ...
              'FaultResistance','1e6','GroundResistance','1e6');
end

function s = onoff(tf)
    if tf, s='on'; else, s='off'; end
end

function [X1,X2,X3] = getSignals(prefix, t_start, winLen)
    [d1,d2,d3,t] = getSignalsFull(prefix);
    [~,i0] = min(abs(t - t_start));
    i1 = min(i0+winLen-1, numel(d1));
    i0 = max(1, i1-winLen+1);
    X1=d1(i0:i1); X2=d2(i0:i1); X3=d3(i0:i1);
end

function [d1,d2,d3,t] = getSignalsFull(prefix)
% Read full time-series from base workspace (written by To-Workspace blocks)
    n1 = [prefix '_A']; n2 = [prefix '_B']; n3 = [prefix '_C'];
    r1 = evalin('base', n1);
    r2 = evalin('base', n2);
    r3 = evalin('base', n3);
    [d1,t]  = unwrapSig(r1);
    [d2,~]  = unwrapSig(r2);
    [d3,~]  = unwrapSig(r3);
end

function [data,t] = unwrapSig(raw)
    if isnumeric(raw)
        if size(raw,2)==2
            t=raw(:,1); data=raw(:,2);
        else
            data=raw(:); t=(0:numel(raw)-1)'/3200;
        end
    elseif isstruct(raw)
        t=raw.time(:); data=raw.signals.values(:);
    elseif isa(raw,'timeseries')
        t=raw.Time(:); data=raw.Data(:);
    else
        error('Unknown format: %s', class(raw));
    end
    data=double(data(:)); t=double(t(:));
end

function feats = buildFeatures(IaA,IaB,IaC, IbA,IbB,IbC, VbA,VbB,VbC, ...
                                Fs,f0,Ibase,Vbase, t_win,Rf,secLbl, useV)
    [ir1,ir2,ir3,ip,in_,iz,np,zp,iap,ian,iaz, ...
     id1,id2,id3,ipk1,ipk2,ipk3,ih2,ih5,iwav] = seqFeatures(IbA,IbB,IbC,Fs,f0,Ibase);
    [ar1,ar2,ar3,ap2,an2,az2] = seqMags(IaA,IaB,IaC,Fs,f0,Ibase);

    if useV
        [vr1,vr2,vr3,vp,vn,vz,vnp,vzp,vap,van,vaz] = seqFeatures_V(VbA,VbB,VbC,Fs,f0,Vbase);
        Zpos = vp/(ip+1e-9);
    else
        [vr1,vr2,vr3,vp,vn,vz,vnp,vzp,vap,van,vaz] = deal(0,0,0,0,0,0,0,0,0,0,0);
        Zpos = 0;
    end

    rmsA  = sqrt((ar1^2+ar2^2+ar3^2)/3);
    rmsB  = sqrt((ir1^2+ir2^2+ir3^2)/3);
    ratio = rmsA/(rmsB+1e-9);

    feats = [ir1,ir2,ir3,ip,in_,iz,np,zp,iap,ian,iaz, ...
             id1,id2,id3,ipk1,ipk2,ipk3,ih2,ih5,t_win,iwav, ...
             ar1,ar2,ar3,ap2,an2,az2, ...
             vr1,vr2,vr3,vp,vn,vz,vnp,vzp,vap,van,vaz, ...
             Zpos,ratio,secLbl,Rf];
end

function [rA,rB,rC,pm,nm,zm,np,zp,ap,an,az, ...
          dA,dB,dC,pkA,pkB,pkC,h2,h5,wav] = seqFeatures(Ia,Ib,Ic,Fs,f0,Base)
    eps_s=1e-9; N=numel(Ia);
    rA=rms(Ia)/Base; rB=rms(Ib)/Base; rC=rms(Ic)/Base;
    k1=round(f0*N/Fs)+1;
    Fa=(2/N)*fft(Ia); Pa=Fa(k1);
    Fb=(2/N)*fft(Ib); Pb=Fb(k1);
    Fc=(2/N)*fft(Ic); Pc=Fc(k1);
    a=exp(1j*2*pi/3); a2=a^2;
    Ip=(Pa+a*Pb+a2*Pc)/3; In=(Pa+a2*Pb+a*Pc)/3; Iz=(Pa+Pb+Pc)/3;
    pm=abs(Ip)/Base; nm=abs(In)/Base; zm=abs(Iz)/Base;
    np=nm/(pm+eps_s); zp=zm/(pm+eps_s);
    ap=rad2deg(angle(Ip)); an=rad2deg(angle(In)); az=rad2deg(angle(Iz));
    dA=rms(diff(Ia)*Fs)/Base; dB=rms(diff(Ib)*Fs)/Base; dC=rms(diff(Ic)*Fs)/Base;
    pkA=max(abs(Ia))/Base; pkB=max(abs(Ib))/Base; pkC=max(abs(Ic))/Base;
    k2=round(2*f0*N/Fs)+1; k5=round(5*f0*N/Fs)+1;
    h2=abs(Fa(k2))/(abs(Fa(k1))+eps_s); h5=abs(Fa(k5))/(abs(Fa(k1))+eps_s);
    try [~,cD]=dwt(Ia,'db4'); wav=sum(cD.^2)/(Base^2*numel(cD));
    catch; wav=sum(abs(Fa(floor(N/2):end)).^2)/Base^2; end
end

function [rA,rB,rC,pm,nm,zm,np,zp,vap,van,vaz] = seqFeatures_V(Va,Vb,Vc,Fs,f0,Vbase)
    eps_s=1e-9; N=numel(Va);
    rA=rms(Va)/Vbase; rB=rms(Vb)/Vbase; rC=rms(Vc)/Vbase;
    k1=round(f0*N/Fs)+1;
    Fa=(2/N)*fft(Va); Pa=Fa(k1);
    Fb=(2/N)*fft(Vb); Pb=Fb(k1);
    Fc=(2/N)*fft(Vc); Pc=Fc(k1);
    a=exp(1j*2*pi/3); a2=a^2;
    Vp=(Pa+a*Pb+a2*Pc)/3; Vn=(Pa+a2*Pb+a*Pc)/3; Vz=(Pa+Pb+Pc)/3;
    pm=abs(Vp)/Vbase; nm=abs(Vn)/Vbase; zm=abs(Vz)/Vbase;
    np=nm/(pm+eps_s); zp=zm/(pm+eps_s);
    vap=rad2deg(angle(Vp)); van=rad2deg(angle(Vn)); vaz=rad2deg(angle(Vz));
end

function [rA,rB,rC,pm,nm,zm] = seqMags(Ia,Ib,Ic,Fs,f0,Base)
    eps_s=1e-9; N=numel(Ia);
    rA=rms(Ia)/Base; rB=rms(Ib)/Base; rC=rms(Ic)/Base;
    k1=round(f0*N/Fs)+1;
    Pa=(2/N)*fft(Ia); Pa=Pa(k1);
    Pb=(2/N)*fft(Ib); Pb=Pb(k1);
    Pc=(2/N)*fft(Ic); Pc=Pc(k1);
    a=exp(1j*2*pi/3); a2=a^2;
    Ip=(Pa+a*Pb+a2*Pc)/3; In=(Pa+a2*Pb+a*Pc)/3; Iz=(Pa+Pb+Pc)/3;
    pm=abs(Ip)/Base; nm=abs(In)/Base; zm=abs(Iz)/Base;
end