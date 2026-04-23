% load_validation_example.m
% 说明：比较仿真与实测冷热负荷曲线，计算 MBE(%) 与 CVRMSE(%)，并绘图输出。
% 用法：直接运行本脚本。若 data/ 下存在 CSV 文件则读取，否则生成示例数据。

clear;
clc;

simFile = fullfile('data', 'simulated_load.csv');
measFile = fullfile('data', 'measured_load.csv');

if exist(simFile, 'file') == 2 && exist(measFile, 'file') == 2
    simTable = readtable(simFile);
    measTable = readtable(measFile);

    [timeVector, coolingSim, heatingSim] = extractLoads(simTable);
    [~, coolingMeas, heatingMeas] = extractLoads(measTable);
else
    [timeVector, coolingSim, heatingSim, coolingMeas, heatingMeas] = generateExampleData();
end

minLength = min([numel(timeVector), numel(coolingSim), numel(heatingSim), numel(coolingMeas), numel(heatingMeas)]);
timeVector = timeVector(1:minLength);
coolingSim = coolingSim(1:minLength);
heatingSim = heatingSim(1:minLength);
coolingMeas = coolingMeas(1:minLength);
heatingMeas = heatingMeas(1:minLength);

coolingMetrics = calcMetrics(coolingSim, coolingMeas);
heatingMetrics = calcMetrics(heatingSim, heatingMeas);

fprintf('Cooling MBE(%%): %.2f, CVRMSE(%%): %.2f\n', coolingMetrics.MBE, coolingMetrics.CVRMSE);
fprintf('Heating MBE(%%): %.2f, CVRMSE(%%): %.2f\n', heatingMetrics.MBE, heatingMetrics.CVRMSE);

figure('Name', 'Load Comparison', 'Color', 'w');

subplot(2, 1, 1);
plot(timeVector, coolingMeas, 'k-', 'LineWidth', 1.2);
hold on;
plot(timeVector, coolingSim, 'r--', 'LineWidth', 1.2);
hold off;
grid on;
title('Cooling Load');
legend({'Measured', 'Simulated'}, 'Location', 'best');
ylabel('kW');

subplot(2, 1, 2);
plot(timeVector, heatingMeas, 'k-', 'LineWidth', 1.2);
hold on;
plot(timeVector, heatingSim, 'r--', 'LineWidth', 1.2);
hold off;
grid on;
title('Heating Load');
legend({'Measured', 'Simulated'}, 'Location', 'best');
xlabel('Time');
ylabel('kW');

if ~exist('output', 'dir')
    mkdir('output');
end
saveas(gcf, fullfile('output', 'load_comparison.png'));

function [timeVector, coolingLoad, heatingLoad] = extractLoads(dataTable)
    variableNames = lower(string(dataTable.Properties.VariableNames));
    timeIdx = find(contains(variableNames, "time") | contains(variableNames, "date"), 1);
    coolIdx = find(contains(variableNames, "cool"), 1);
    heatIdx = find(contains(variableNames, "heat"), 1);

    if isempty(coolIdx) || isempty(heatIdx)
        error('输入文件需包含 cooling 与 heating 负荷列。');
    end

    coolingLoad = dataTable{:, coolIdx};
    heatingLoad = dataTable{:, heatIdx};

    if isempty(timeIdx)
        timeVector = (1:numel(coolingLoad))';
    else
        timeVector = dataTable{:, timeIdx};
        if ~isdatetime(timeVector)
            if iscellstr(timeVector) || isstring(timeVector) || ischar(timeVector)
                timeVector = datetime(timeVector);
            elseif isnumeric(timeVector) && all(timeVector > 50000)
                timeVector = datetime(timeVector, 'ConvertFrom', 'datenum', 'Format', 'yyyy-MM-dd HH:mm');
            end
        end
    end
end

function metrics = calcMetrics(simulated, measured)
    simulated = simulated(:);
    measured = measured(:);
    n = min(numel(simulated), numel(measured));
    simulated = simulated(1:n);
    measured = measured(1:n);

    diffSeries = simulated - measured;
    sumMeasured = sum(measured);
    meanMeasured = mean(measured);

    mbe = 100 * sum(diffSeries) / max(sumMeasured, eps);
    cvrmse = 100 * sqrt(sum(diffSeries .^ 2) / max(n - 1, 1)) / max(meanMeasured, eps);

    metrics = struct('MBE', mbe, 'CVRMSE', cvrmse);
end

function [timeVector, coolingSim, heatingSim, coolingMeas, heatingMeas] = generateExampleData()
    hourIndex = (0:23)';
    timeVector = datetime(2026, 1, 1, 0, 0, 0) + hours(hourIndex);

    baseCooling = max(0, 2 + 3 * sin(2 * pi * (hourIndex - 6) / 24));
    baseHeating = max(0, 3 + 2 * sin(2 * pi * (hourIndex + 6) / 24));

    coolingSim = baseCooling;
    heatingSim = baseHeating;

    coolingMeas = baseCooling .* (1 + 0.05 * cos(2 * pi * hourIndex / 24));
    heatingMeas = baseHeating .* (1 - 0.04 * sin(2 * pi * hourIndex / 24));
end
