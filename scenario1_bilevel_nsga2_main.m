function result = scenario1_bilevel_nsga2_main()
% 场景1：PV-天然气锅炉-ASHP-电池-太阳能集热器-蓄热罐
% 双层优化：上层NSGA-II（容量）+ 下层LP（典型日逐时调度）
% 数据路径：D:\optimized\data\cooling_load.csv / heating_load.csv / electric_load.csv

clc; clear; close all;

%% ========================= 1) 读取数据 =========================
dataDir = fullfile('D:','optimized','data');
cool8760 = read8760(fullfile(dataDir,'cooling_load.csv'));
heat8760 = read8760(fullfile(dataDir,'heating_load.csv'));
elec8760 = read8760(fullfile(dataDir,'electric_load.csv'));

assert(numel(cool8760)>=8760 && numel(heat8760)>=8760 && numel(elec8760)>=8760, ...
    '负荷数据长度不足8760，请检查CSV文件');

% 典型日：冬15天、春秋105天、夏196天
dayIdx = [15,105,196];
dayName = {'Winter_D15','SpringAutumn_D105','Summer_D196'};
daysWeight = [90,183,92]; % 冬/春秋/夏权重天数

typical = cell(1,3);
for k = 1:3
    h = (dayIdx(k)-1)*24 + (1:24);
    typical{k}.elec = elec8760(h);
    typical{k}.heat = heat8760(h);
    typical{k}.cool = cool8760(h);
    typical{k}.name = dayName{k};
end

%% ========================= 2) 参数（已替换为给定参数） =========================
p = struct();

% ---- 设备经济与排放参数 ----
% 投资年化系数（寿命15年，利率5%）
p.interest = 0.05;
p.lifetime = 15;
p.crf = p.interest * (1+p.interest)^p.lifetime / ((1+p.interest)^p.lifetime - 1);

% 设备投资单价（元/单位）
% x = [PV_kW, GasBoiler_kW_th, ASHP_ele_kW, Batt_E_kWh, Batt_P_kW, SC_kW_th, TES_E_kWh, TES_P_kW]
p.cost_PV   = 5000;   % 元/kWp
p.cost_SC   = 1500;   % 元/m^2
p.cost_BAT  = 2000;   % 元/kWh
p.cost_TES  = 800;    % 元/kWh
p.cost_ASHP = 4000;   % 元/kW(电输入)
p.cost_GB   = 1000;   % 元/kW(热输出)

% 将SC按kW_th处理时，需面积-功率换算。默认1 m^2≈1 kW_th峰值，可按项目修改。
p.sc_m2_per_kw = 1.0;

% 维护成本（元/kWh 输出）
p.maint_PV   = 0.01;   % 按光伏发电量
p.maint_SC   = 0.005;  % 按集热器产热量
p.maint_BAT  = 0.02;   % 按电池放电量
p.maint_TES  = 0.005;  % 按蓄热放热量
p.maint_ASHP = 0.015;  % 按热泵产热+产冷量
p.maint_GB   = 0.01;   % 按锅炉产热量

% 能源价格与碳排放因子
p.price_grid = 0.8;    % 元/kWh
p.price_gas  = 3.5;    % 元/m^3
p.gas_LHV    = 9.0;    % kWh/m^3
p.eff_GB     = 0.9;    % 燃气锅炉效率（热输出/燃料低位热值）

p.emit_grid = 0.55;    % kg CO2 / kWh
p.emit_gas  = 2.0;     % kg CO2 / m^3

% 设备效率参数
p.etaBch  = 0.95;
p.etaBdis = 0.95;
p.etaTch  = 0.95;
p.etaTdis = 0.95;

% ASHP性能（可按温度模型替换为分时）
p.COP_h = 3.0*ones(24,1);  % 供热COP
p.EER_c = 3.2*ones(24,1);  % 制冷EER

% 缺供惩罚（保证LP可行）
p.bigM_e = 10; p.bigM_h = 10; p.bigM_c = 10;

% 容量投资向量（与x一致）
p.capex = [ ...
    p.cost_PV, ...
    p.cost_GB, ...
    p.cost_ASHP, ...
    p.cost_BAT, ...
    0, ...                 % 电池功率不单独计投资（避免重复计入）
    p.cost_SC*p.sc_m2_per_kw, ...
    p.cost_TES, ...
    0 ...                  % TES功率不单独计投资（避免重复计入）
    ];

p.typical = typical;
p.daysWeight = daysWeight;

% 太阳能资源（若有辐照数据请替换）
pu_winter = max(0, sin(((1:24)'-7)/24*pi))*0.75;
pu_spring = max(0, sin(((1:24)'-6.5)/24*pi))*0.95;
pu_summer = max(0, sin(((1:24)'-6)/24*pi))*1.05;
p.pvPU = {pu_winter, pu_spring, pu_summer};
p.scPU = {0.9*pu_winter, 0.95*pu_spring, 1.0*pu_summer};

%% ========================= 3) 上层NSGA-II =========================
nvars = 8;
lb = [0, 0, 0, 0, 0, 0, 0, 0];
ub = [120, 80, 60, 250, 80, 100, 400, 120];  % 可按工程范围调整

obj = @(x) upperObj(x,p);

opts = optimoptions('gamultiobj', ...
    'PopulationSize', 80, ...
    'MaxGenerations', 80, ...
    'CrossoverFraction', 0.85, ...
    'Display', 'iter', ...
    'UseParallel', false);

[X,F] = gamultiobj(obj,nvars,[],[],[],[],lb,ub,opts);
% F(:,1)=年总成本, F(:,2)=年碳排放

%% ========================= 4) 结果输出与保存 =========================
[~,iCost] = min(F(:,1));
[~,iCO2]  = min(F(:,2));

fprintf('\n===== 场景1优化结果 =====\n');
fprintf('最小年总成本解: Cost=%.2f, CO2=%.2f\n',F(iCost,1),F(iCost,2));
fprintf('容量[kW/kWh] = [%s]\n',num2str(X(iCost,:), '%.2f '));
fprintf('最小年碳排放解: Cost=%.2f, CO2=%.2f\n',F(iCO2,1),F(iCO2,2));
fprintf('容量[kW/kWh] = [%s]\n',num2str(X(iCO2,:), '%.2f '));

paretoMat = [X F];
writematrix(paretoMat,'scenario1_pareto_capacity_cost_co2.csv');

figure('Color','w');
scatter(F(:,1),F(:,2),25,'filled'); grid on;
xlabel('Annual Total Cost (CNY)');
ylabel('Annual CO_2 Emission (kg)');
title('Scenario 1 Pareto Front');
saveas(gcf,'scenario1_pareto_front.png');

% 选取折中解（归一化最小距离）
fn = (F - min(F,[],1)) ./ (max(F,[],1)-min(F,[],1)+1e-9);
[~,iknee] = min(sum(fn.^2,2));
xKnee = X(iknee,:);

% 输出典型日设备出力（折中解）
dispatch = cell(1,3);
for s = 1:3
    [~,~,out] = lowerLP(xKnee,p,s);
    dispatch{s} = out;
    exportDispatch(out, sprintf('scenario1_%s_dispatch.csv', p.typical{s}.name));
    plotDispatch(out, p.typical{s}.name);
end

save('scenario1_result.mat','X','F','xKnee','dispatch','p');
result.X = X; result.F = F; result.xKnee = xKnee; result.dispatch = dispatch;
end

%% ========================= 上层目标 =========================
function f = upperObj(x,p)
capAnnual = p.crf * sum(p.capex .* x);

opAnnual = 0; co2Annual = 0;
for s = 1:3
    [dayCost,dayCO2] = lowerLP(x,p,s);
    opAnnual  = opAnnual  + p.daysWeight(s)*dayCost;
    co2Annual = co2Annual + p.daysWeight(s)*dayCO2;
end

f = [capAnnual + opAnnual, co2Annual];
end

%% ========================= 下层LP =========================
function [dayCost,dayCO2,out] = lowerLP(x,p,s)
% x=[PV, GB, ASHPele, BattE, BattP, SC, TESE, TESP]
PV=x(1); GB=x(2); HPelCap=x(3); BE=x(4); BP=x(5); SC=x(6); TE=x(7); TP=x(8);

elec = p.typical{s}.elec(:);
heat = p.typical{s}.heat(:);
cool = p.typical{s}.cool(:);
pvPU = p.pvPU{s}(:);
scPU = p.scPU{s}(:);
COP  = p.COP_h(:);
EER  = p.EER_c(:);

T=24;
ix = @(k) (k-1)*T + (1:T);

iPg=ix(1); iPvUse=ix(2); iPvCurt=ix(3);
iBch=ix(4); iBdis=ix(5); iBsoc=ix(6);
iGasH=ix(7); iHP_h=ix(8); iHP_c=ix(9); iHP_e=ix(10);
iSC_h=ix(11); iTch=ix(12); iTdis=ix(13); iTsoc=ix(14);
iSe=ix(15); iSh=ix(16); iSc=ix(17);
N=17*T;

f=zeros(N,1);

% 购能成本
f(iPg)=p.price_grid;
% 锅炉热功率->燃气体积：Vgas = Qheat/(eff*LHV)
f(iGasH)=p.price_gas/(p.eff_GB*p.gas_LHV);

% 维护成本（按输出量）
f(iPvUse)=f(iPvUse)+p.maint_PV;
f(iSC_h)=f(iSC_h)+p.maint_SC;
f(iBdis)=f(iBdis)+p.maint_BAT;
f(iTdis)=f(iTdis)+p.maint_TES;
f(iHP_h)=f(iHP_h)+p.maint_ASHP;
f(iHP_c)=f(iHP_c)+p.maint_ASHP;
f(iGasH)=f(iGasH)+p.maint_GB;

% 缺供惩罚
f(iSe)=p.bigM_e; f(iSh)=p.bigM_h; f(iSc)=p.bigM_c;

lb=zeros(N,1); ub=inf(N,1);

ub(iPvUse)=PV*pvPU; ub(iPvCurt)=PV*pvPU;
ub(iBch)=BP; ub(iBdis)=BP; ub(iBsoc)=BE;
ub(iGasH)=GB;
ub(iHP_h)=HPelCap*COP; ub(iHP_c)=HPelCap*EER; ub(iHP_e)=HPelCap;
ub(iSC_h)=SC*scPU;
ub(iTch)=TP; ub(iTdis)=TP; ub(iTsoc)=TE;

Aeq=[]; beq=[];

% 1) PV分配：pv_use + pv_curt + bch = pv_gen
for t=1:T
    r=zeros(1,N);
    r(iPvUse(t))=1; r(iPvCurt(t))=1; r(iBch(t))=1;
    Aeq=[Aeq; r]; beq=[beq; PV*pvPU(t)];
end

% 2) 电平衡：grid + pv_use + bdis + se = elec + hp_e
for t=1:T
    r=zeros(1,N);
    r(iPg(t))=1; r(iPvUse(t))=1; r(iBdis(t))=1; r(iSe(t))=1;
    r(iHP_e(t))=-1;
    Aeq=[Aeq; r]; beq=[beq; elec(t)];
end

% 3) 热平衡：gas + hp_h + sc + tdis + sh = heat + tch
for t=1:T
    r=zeros(1,N);
    r(iGasH(t))=1; r(iHP_h(t))=1; r(iSC_h(t))=1; r(iTdis(t))=1; r(iSh(t))=1;
    r(iTch(t))=-1;
    Aeq=[Aeq; r]; beq=[beq; heat(t)];
end

% 4) 冷平衡：hp_c + sc = cool
for t=1:T
    r=zeros(1,N);
    r(iHP_c(t))=1; r(iSc(t))=1;
    Aeq=[Aeq; r]; beq=[beq; cool(t)];
end

% 5) HP电功率耦合：hp_e = hp_h/COP + hp_c/EER
for t=1:T
    r=zeros(1,N);
    r(iHP_e(t))=1; r(iHP_h(t))=-1/COP(t); r(iHP_c(t))=-1/EER(t);
    Aeq=[Aeq; r]; beq=[beq; 0];
end

% 6) 电池SOC
soc0=0.5*BE;
for t=1:T
    r=zeros(1,N);
    r(iBsoc(t))=1; r(iBch(t))=-p.etaBch; r(iBdis(t))=1/p.etaBdis;
    if t>1, r(iBsoc(t-1))=-1; b=0; else, b=soc0; end
    Aeq=[Aeq; r]; beq=[beq; b];
end
r=zeros(1,N); r(iBsoc(T))=1; Aeq=[Aeq; r]; beq=[beq; soc0];

% 7) 蓄热SOC
ts0=0.5*TE;
for t=1:T
    r=zeros(1,N);
    r(iTsoc(t))=1; r(iTch(t))=-p.etaTch; r(iTdis(t))=1/p.etaTdis;
    if t>1, r(iTsoc(t-1))=-1; b=0; else, b=ts0; end
    Aeq=[Aeq; r]; beq=[beq; b];
end
r=zeros(1,N); r(iTsoc(T))=1; Aeq=[Aeq; r]; beq=[beq; ts0];

opts = optimoptions('linprog','Display','none');
[z,~,flag] = linprog(f,[],[],Aeq,beq,lb,ub,opts);

if flag<=0
    dayCost=1e12; dayCO2=1e12; out=[];
    return;
end

gridUse = z(iPg);
gasHeat = z(iGasH);

% 日成本与日碳排
% gasHeat是热输出量(kWh_th)，折算天然气体积 m3 = Q/(eff*LHV)
gasVol = gasHeat./(p.eff_GB*p.gas_LHV);
dayCost = f'*z;
dayCO2  = p.emit_grid*sum(gridUse) + p.emit_gas*sum(gasVol);

out = table((1:T)',...
    z(iPg),z(iPvUse),z(iPvCurt),z(iBch),z(iBdis),z(iBsoc),...
    z(iGasH),z(iHP_h),z(iHP_c),z(iHP_e),z(iSC_h),...
    z(iTch),z(iTdis),z(iTsoc),z(iSe),z(iSh),z(iSc),...
    'VariableNames',{'Hour','Grid','PV_use','PV_curt','Bat_ch','Bat_dis','Bat_SOC',...
    'Gas_heat','HP_heat','HP_cool','HP_elec','SC_heat','TES_ch','TES_dis','TES_SOC',...
    'Short_e','Short_h','Short_c'});
end

%% ========================= 工具函数 =========================
function v = read8760(fp)
raw = readmatrix(fp);
raw = raw(~all(isnan(raw),2),:);
if isvector(raw)
    v = raw(:);
else
    col = 1;
    for c = 1:size(raw,2)
        if nnz(~isnan(raw(:,c)))>0, col=c; break; end
    end
    v = raw(:,col);
    v = v(~isnan(v));
end
end

function exportDispatch(tab,filename)
writetable(tab,filename);
end

function plotDispatch(tab,tag)
figure('Color','w');
subplot(3,1,1);
plot(tab.Hour,tab.Grid,'-k',tab.Hour,tab.PV_use,'-y',tab.Hour,tab.Bat_dis,'-b',tab.Hour,tab.Bat_ch,'--b','LineWidth',1.1);
grid on; legend('Grid','PV use','Bat dis','Bat ch'); title([tag ' - Electric side']);

subplot(3,1,2);
plot(tab.Hour,tab.Gas_heat,'-r',tab.Hour,tab.HP_heat,'-m',tab.Hour,tab.SC_heat,'-g',tab.Hour,tab.TES_dis,'-c',tab.Hour,tab.TES_ch,'--c','LineWidth',1.1);
grid on; legend('Gas heat','HP heat','SC heat','TES dis','TES ch'); title([tag ' - Heat side']);

subplot(3,1,3);
plot(tab.Hour,tab.HP_cool,'-b','LineWidth',1.2); hold on;
plot(tab.Hour,tab.HP_elec,'-k','LineWidth',1.2);
grid on; legend('HP cool','HP elec'); title([tag ' - Cooling / HP power']);
xlabel('Hour');

saveas(gcf,['scenario1_' tag '_dispatch.png']);
end
