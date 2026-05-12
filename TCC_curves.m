
clc;
clear;
close all;

%% =========================================================
% IEC Standard Inverse IDMT Parameters
%% =========================================================
k = 0.14;
alpha = 0.02;

%% =========================================================
% Relay Settings
%% =========================================================
Ip = 150;          % Pickup current (A)

TMS_R1 = 0.075;    % Upstream relay
TMS_R2 = 0.050;    % Downstream relay

%% =========================================================
% Fault Currents
%% =========================================================
Isc_B1 = 450.8;    % Fault current at Bus 1 (A)
Isc_B2 = 262.6;    % Fault current at Bus 2 (A)

%% =========================================================
% Current Range for TCC Curves
%% =========================================================
I = logspace(log10(120), log10(2500), 500);

%% =========================================================
% IDMT Equation
%% =========================================================
idmt = @(I,TMS) ...
    TMS .* k ./ ((I./Ip).^alpha - 1);

%% =========================================================
% Relay Operating Times
%% =========================================================
t_R1 = idmt(I, TMS_R1);
t_R2 = idmt(I, TMS_R2);

%% =========================================================
% Operating Times at Fault Locations
%% =========================================================
t_R1_B1 = idmt(Isc_B1, TMS_R1);

t_R2_B2 = idmt(Isc_B2, TMS_R2);
t_R1_B2 = idmt(Isc_B2, TMS_R1);

CTI = t_R1_B2 - t_R2_B2;

%% =========================================================
% Transformer Inrush Region
%% =========================================================
Irated = 122.4;

inrushLow  = 5  * Irated;
inrushHigh = 15 * Irated;

%% =========================================================
% ANSI Damage Curve
%% =========================================================
I_damage = 150:20:2500;

M = I_damage ./ Irated;

t_damage = 10 ./ (M.^2);

%% =========================================================
% Plotting
%% =========================================================
figure('Color','w');

loglog(I, t_R1, 'b', 'LineWidth', 2);
hold on;

loglog(I, t_R2, 'g', 'LineWidth', 2);

%% Inrush Region
xline(inrushLow, '--r', 'LineWidth', 1.5);
xline(inrushHigh, '--r', 'LineWidth', 1.5);

%% ANSI Damage Curve
loglog(I_damage, t_damage, '--', ...
    'Color', [0.8 0.5 0], 'LineWidth', 1.5);

%% Fault Points
plot(Isc_B1, t_R1_B1, 'ob', ...
    'MarkerFaceColor','b', ...
    'MarkerSize',8);

plot(Isc_B2, t_R2_B2, 'og', ...
    'MarkerFaceColor','g', ...
    'MarkerSize',8);

plot(Isc_B2, t_R1_B2, '^b', ...
    'MarkerFaceColor','b', ...
    'MarkerSize',8);

%% CTI Bracket
plot([Isc_B2 Isc_B2], ...
     [t_R2_B2 t_R1_B2], ...
     ':', ...
     'Color',[0.8 0.5 0], ...
     'LineWidth',2);

%% =========================================================
% Labels and Formatting
%% =========================================================
grid on;

xlabel('Current (A)');
ylabel('Operating Time (s)');

title('IDMT Relay TCC Coordination Curves');

legend( ...
    'R1 Upstream (TMS = 0.075)', ...
    'R2 Downstream (TMS = 0.05)', ...
    'Inrush Region', ...
    'ANSI Damage Curve', ...
    'Location','southwest');

%% =========================================================
% Axis Limits
%% =========================================================
xlim([120 2500]);
ylim([0.05 15]);

%% =========================================================
% Text Annotations
%% =========================================================
text(Isc_B2*1.05, ...
     sqrt(t_R1_B2*t_R2_B2), ...
     sprintf('CTI = %.3f s', CTI));

text(Isc_B1*1.05, ...
     t_R1_B1, ...
     sprintf('t_{R1,B1} = %.3f s', t_R1_B1));

text(Isc_B2*1.05, ...
     t_R2_B2, ...
     sprintf('t_{R2,B2} = %.3f s', t_R2_B2));

text(Isc_B2*1.05, ...
     t_R1_B2, ...
     sprintf('t_{R1,B2} = %.3f s', t_R1_B2));

%% =========================================================
% Display Results
%% =========================================================
fprintf('==============================\n');
fprintf('Relay Coordination Results\n');
fprintf('==============================\n');

fprintf('R2 pickup current = %.1f A\n', Ip);
fprintf('R1 pickup current = %.1f A\n', Ip);

fprintf('Fault current at Bus 2 = %.1f A\n', Isc_B2);

fprintf('R2 operating time at Bus 2 = %.3f s\n', ...
    t_R2_B2);

fprintf('R1 backup time at Bus 2 = %.3f s\n', ...
    t_R1_B2);

fprintf('Coordination Time Interval = %.3f s\n', ...
    CTI);
