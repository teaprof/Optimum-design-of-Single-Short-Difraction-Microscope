function optimMain
    rng(1);
    Clock = clock;
    pathToSave = sprintf('results/run%4d-%02d-%02d-%02d-%02d-%02d', floor(Clock));
    mkdir(pathToSave);
    
%     assert(vstart < getSpeedOfLight/1.05);

    range = ones(getDim, 2)*NaN; %пока инициализируем NaN'ами
    range(getDim('r1'), :) = [1e-3 2e-3]; %м
    range(getDim('r2_minus_r1'), :) = [1e-4 1e-3]; %м
    range(getDim('EMamplitude'), :) = [1e+5 1e+9]; %В/м
    range(getDim('EMphase'), :) = [0 2*pi]; %рад
    range(getDim('EStart'), :) = [0.6 200]*1e+6; %эВ
%     range(getDim('EStart'), :) = [0.6 0.6]*1e+6; %эВ
    range(getDim('tmax'), :) = [20e-12 100e-12]; %с
    assert(prod(prod(~isnan(range))) == 1); %если ничего не забыли проинициализировать, то NaN быть не должно
    lb = range(:, 1).*getScale;
    ub = range(:, 2).*getScale;
    
    electronsPerParticle = 1e+4;
    
    %Создаём ансамбль частиц, распределённых в цилиндре радиусом 1 и
    %высотой 1. Этот ансамбль будет потом в соответствующих пропорциях
    %сжиматься, чтобы поместиться в волновод. То же самое касается
    %начальной скорости.
    %Если генерить каждый раз новый ансамбль, то в расчётах значения целевой функции будет
    %статистическая погрешность, которая не даст нормально минимизировать
    %её значение традиционными методами.
%     [r0, v0] = createElectronsEnsemble(1, geom.r(1)*0.1, [0 1e-4], 'grid', 5, 5, 19, 19);
%     [r0, v0] = createElectronsEnsemble(1, geom.r(1)*0.1, [0 1e-4], 'regular', 5, 5);
%   [r0, v0] = createElectronsEnsemble(1, geom.r(1)*0.1, [0 1e-4], 'unirandom', 1e+2);
    [r0, v0] = createElectronsEnsemble(1, 1, [0 1e-4], 'normal', 1e+1);
    
    NParticles = size(r0, 2);
    
    charge = NParticles*electronsPerParticle*getElectronCharge;
    fprintf('Charge %f pC\n', charge*1e+12);
    
   
    %Глобальный поиск
    NTrials = 1e+1; %количество статистических испытаний для глобального поиска
    Nbest = min(NTrials, 4); %количество решений, которые будут дожиматься локальным оптимизатором
    f = @(x)targetFcnExtended(x, r0, v0, electronsPerParticle, lb, ub);
    [xx, yy] = optimizator(f, lb, ub, NTrials, Nbest);
%     drawSlices(f, lb, ub, {'vphase', 'E', 'phase0', 'tspan'}) %тут можно вызвать другой визуализатор todo: переписать функцию для многомерного использования, а не только для dim=3    

    
    %Печатаем таблицу лучших решений 
    for n = 1 : min(Nbest, NTrials)
        fprintf('#%d: x = [',  n);
        for k = 1 : size(xx, 1)
            fprintf(' %f', xx(k, n));
        end
        fprintf('], y = %f mm\n', yy(n)*1e+3);
    end

    
%     [y, idx] = min(yy);
%     x = xx(:, idx);
%     fprintf('Minimum length %f mm\n', y*1e+3);
%     fprintf('Compression level %f\n', y/y0);
    save('optimMainSave');
%     return;
%     load('optimMainSave');
    
%     spmd
    numlabs = 8;
    for labindex = 1 : numlabs
        MaxN = min(Nbest, NTrials);
        [start, finish] = getSubJob(MaxN, labindex, numlabs);
        for n = start : finish
            geom.r = 1e-3;
            [EMsolution, r, v, tmax] = XtoStruct(xx(:, n), r0, v0);
            traj = simflight(EMsolution, r, v, tmax, electronsPerParticle);
            suffix = sprintf('%02d', n);
            OutputSolution(EMsolution, geom, traj, xx(:, n), pathToSave, suffix);
        end
    end
%     end
end

function OutputSolution(sol, geom, traj, x, pathToSave, suffix)
    %Пересчитываем траекторию с большей детализацией
    fprintf('Reconstructing optimal config track\n');
%     tspan(2) = tspan(2)*1.5;
%     electronsPerParticle = electronsPerParticle/10;
%     [r0, v0] = createElectronsEnsemble(geom.r(1)*0.1, [0 1e-4], 'random', size(r0, 2)*10);
%     f = @(x)targetFcn(x, geom, sol0, r0, v0, electronsPerParticle);
%     [y, sol, traj] = f(x);
    y0 = getEnsembleLength(traj.Z(:, 1));
    y = getEnsembleLength(traj.Z(:, end));
    fprintf('Initial length %f mm\n', y0*1e+3);
    fprintf('Minimum length %f mm\n', y*1e+3);
    fprintf('Compression level %f\n', y/y0);
    
    v = zeros(numel(traj.t), 1);
    for n = 1 : numel(traj.t)
        v(n) = getEnsembleLength(traj.Z(:, n));
    end
    f = figure;
    plot(traj.t*1e+12, v*1e+3);
    xlabel('t, ps');
    ylabel('length, mm');
    grid on;
    saveas(f, [pathToSave, '/ensembleLength' suffix]);
    
    save([pathToSave, '/optimMainRes' suffix]); %, 'x', 'y', 'sol', 'traj');
    animateFlight2(sol, traj, 'rmax', geom.r(1)*1.1, 'zhalfwidth', max(v), 'gridSize', [40 30], 'figSize', [800 600], 'fileName', [pathToSave '/wangFig' suffix '.avi']);
    
    %Сохраняем результаты в виде текста
    [r0, v0] = XtoPhase(traj.rv(:, 1));
    %[sol, r, v, tmax] = XtoStruct(x, geom, sol, r0, v0);
    [sol, r, v, tmax] = XtoStruct(x, r0, v0);
    Estart = getValue(x, 'EStart');
    f = fopen([pathToSave, '/params', suffix, '.txt'], 'w+');    
    fprintf(f, 'E0 = %g MeV\n', Estart*1e-6);
    fprintf(f, 'V0 = %g *c\n', EnergyToSpeed(Estart)/getSpeedOfLight);
    fprintf(f, 'kz = %g 1/m\n', sol.kz);
    fprintf(f, 'Ez = %g V/m\n', sol.C1(1));
    fprintf(f, 'phase = %f rad\n', sol.phase);
    fprintf(f, 'Initial length %f mm\n', y0*1e+3);
    fprintf(f, 'Minimum length %f mm\n', y*1e+3);
    fprintf(f, 'Compression level %f\n', y/y0);
    fclose(f);    
end

function idx = getDim(name)
    if nargin == 0
        %Общее количество элементов в фазовом пространстве
        idx = 6;
    else
        %Номер размерности для заданного имени
        switch(name)
            case 'r1'
                idx = 1;
            case 'r2_minus_r1'
                idx = 2;
            case 'EMamplitude'
                idx = 3;
            case 'EMphase'
                idx = 4;
            case 'EStart'
                idx = 5;
            case 'tmax'
                idx = 6;
            otherwise
                error('unknown name %s', name);
        end
    end
end

function val = getValue(x, name)
    val = x(getDim(name));
end
    
function scale = getScale
%используется, чтобы привести все переменные, по которым проводится
%оптимизация, к одному порядку величины
    scale = zeros(getDim, 1);
    scale(getDim('r1')) = 1e+3;
    scale(getDim('r2_minus_r1')) = 1e+3;
    scale(getDim('EMamplitude')) = 1e-4;
    scale(getDim('EMphase')) = 1;
    scale(getDim('EStart')) = 1e-6;
    scale(getDim('tmax')) = 1e+12;
    assert(prod(scale) ~= 0); %если ничего не забыли проинициализировать, то нулей быть не должно
end

function [EMsolution, r, v, tmax] = XtoStruct(x, r0, v0)
    x = x./getScale;
    r1 =  getValue(x, 'r1'); %внутренний диаметр волновода
    r2_minus_r1 =  getValue(x, 'r2_minus_r1'); %толщина диэлектрической стенки волновода
    EMamplitude = getValue(x, 'EMamplitude'); %по умолчанию амплитуда Ez равна 1 В/м, этот множитель масштабирует решение в волноводе
    EMphase = getValue(x, 'EMphase'); %фаза волны
    Estart = getValue(x, 'EStart'); %Стартовая энергия электронов
    tmax = getValue(x, 'tmax'); %длительность полёта
    
    r2 = r1 + r2_minus_r1;
    v0norm = EnergyToSpeed(Estart);
    
    
    %Находим нужную моду решения в волноводе
    geom = geometry('none');
    geom = geom.addLayer(5.5, 1, r1);
    geom = geom.addLayer(1, 1, r2);
    w = 2*pi*1e+12;
    m = 0;
    waveguideSolver = WaveguideSolver(geom, w, m);
    
    waveguideSolver = waveguideSolver.solve;
%    for n = 1 : min(numel(waveguideSolver.solutions), 10)
%         waveguidePlot(waveguideSolver.solutions{n});
%     end
    EMsolution = waveguideSolver.sol;
    
    
    EMsolution.C1 = EMsolution.C1*EMamplitude;
    EMsolution.C2 = EMsolution.C2*EMamplitude;
    EMsolution.phase = EMphase;
    
    r = r0;
    r(1, :) = r(1, :)*geom.r(1);
    r(2, :) = r(2, :)*geom.r(1);
    r(3, :) = r(3, :)*1e-4;

    v = v0*v0norm;
%     [r0, v0] = createElectronsEnsemble(Estart, r1, [0 3e-4], 'normal', 1e+2);
%     [r0, v0] = createElectronsEnsemble(geom.r(1)*0.1, [0 1e-4], 'grid', 5, 5, 19, 19);
%     [r0, v0] = createElectronsEnsemble(geom.r(1)*0.1, [0 1e-4], 'regular', 5, 5);
%     [r0, v0] = createElectronsEnsemble(geom.r(1)*0.1, [0 1e-4], 'random', 1e+3);
end

function x = StructToX(r1, dr, EMamplitude, EMphase, tmax)
    x = zeros(3, 1);
    x(getDim('r1')) = r1;
    x(getDim('r2_minus_r1')) = dr;
    x(getDim('EMamplitude')) = EMamplitude;
    x(getDim('EMphase')) = EMphase;
    x(getDim('tmax')) = tmax;
    x = x.*getScale;
end

%function [v, EMsolution, traj] = targetFcnExtended(x, r0, v0, electronsPerParticle)
function v = targetFcnExtended(x, r0, v0, electronsPerParticle, lb, ub)
%fmincon function can violate constrains at intermediate iterations. We
%expand our target function beyond [lb, ub] 
    [EMsolution, r0, v0, tmax] = XtoStruct(x, r0, v0);
    %Check violation of boundaries for tmax only. If tmax < 0 then ode45
    %solver produces inacceptable sequence of points.
    x(x < lb) = lb(x < lb);
    x(x > ub) = ub(x > ub);
    if tmax == 0
        v = getEnsembleLength(r0);
        return;
    end
    %[v, EMsolution, traj] = targetFcn(EMsolution, r0, v0, tmax, electronsPerParticle);
    v = targetFcn(EMsolution, r0, v0, tmax, electronsPerParticle);
end
    
    
%function [v, EMsolution, traj] = targetFcn(EMsolution, r0, v0, tmax, electronsPerParticle)    
function v = targetFcn(EMsolution, r0, v0, tmax, electronsPerParticle)    
    tspan = [0 tmax];
    traj = simElectrons(r0, v0, EMsolution, tspan, electronsPerParticle);
    
    %Результат - это средний размер ансамбля за последнюю p-часть  времени
    v = zeros(numel(traj.t), 1);
    for n = 1 : numel(traj.t)
        v(n) = getEnsembleLength(traj.Z(:, n));
    end
    v = griddedInterpolant(traj.t, v);
    
    p = 0.2;
    t = linspace(tspan(1) + diff(tspan)*(1-p), tspan(2), 1000);
    v = max(v(t));
end

function traj = simflight(EMsolution, r0, v0, tmax, electronsPerParticle)    
    tspan = [0 tmax];
    traj = simElectrons(r0, v0, EMsolution, tspan, electronsPerParticle);
end

function v = getEnsembleLength(Z)
    zz = sort(Z);
%     nOutliers = floor(numel(zz)/10);
    nOutliers = 0; %выбросы недопустимы
    v = abs(zz(end - nOutliers) - zz(1 + nOutliers));
%     zmin = min(Z);
%     zmax = max(Z); 
%     v = zmax - zmin;    
end
