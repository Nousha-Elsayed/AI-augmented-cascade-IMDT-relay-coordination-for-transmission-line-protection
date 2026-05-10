I = linspace(1.1, 20, 200); % multiples of pickup

Ip = 3; % pickup
k = 0.14; alpha = 0.02;

TMS1 = 0.1; % downstream
TMS2 = 0.3; % upstream

t1 = TMS1 * (k ./ ((I/Ip).^alpha - 1));
t2 = TMS2 * (k ./ ((I/Ip).^alpha - 1));

loglog(I, t1, 'r', 'LineWidth', 2); hold on;
loglog(I, t2, 'b', 'LineWidth', 2);

grid on;
xlabel('Current (Multiple of Pickup)');
ylabel('Operating Time (sec)');
legend('Relay B (Downstream)', 'Relay A (Upstream)');
title('Protection Coordination Curve');