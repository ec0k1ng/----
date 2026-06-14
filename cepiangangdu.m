%% calc_cornering_stiffness_v3.m
% 从 Excel 二维表读取轮胎侧向力数据，计算不同载荷下的侧偏刚度。
% 表格形式：第一行（第2列起）为载荷，第一列（第2行起）为侧偏角，内部为侧向力。
% 支持单侧或双侧侧偏角数据（如仅有正侧偏角）。

clear; clc;

% ===================== 用户输入 =====================
filename = 'tire_data.xlsx';   % Excel 文件名，请确保文件在当前路径下
sheet    = 1;                  % 工作表编号或名称
% ===================================================

% 读取数值矩阵
try
    data = readmatrix(filename, 'Sheet', sheet);
catch
    error('读取文件失败，请检查文件名、路径和工作表名称是否正确。');
end

if isempty(data)
    error('Excel 文件中未读取到任何数据，请检查文件内容。');
end

% 根据布局提取数据
Fz_vec    = data(1, 2:end);          % 载荷（行向量）
alpha_vec = data(2:end, 1);          % 侧偏角（列向量）
Fy_mat    = data(2:end, 2:end);      % 侧向力，行对应侧偏角，列对应载荷

% 转换为列向量
Fz_vec = Fz_vec(:);
nLoads = length(Fz_vec);

% 维度检查
if size(Fy_mat,1) ~= length(alpha_vec) || size(Fy_mat,2) ~= nLoads
    error('数据维度不匹配，请确认表格布局：首行-载荷，首列-侧偏角。');
end

% 按侧偏角升序排列（同时调整 Fy_mat 行顺序）
[alpha_vec, sort_idx] = sort(alpha_vec);
Fy_mat = Fy_mat(sort_idx, :);

% 显示读取概况
fprintf('成功读取数据：%d 个载荷，侧偏角范围 %.2f° ~ %.2f°\n', ...
    nLoads, min(alpha_vec), max(alpha_vec));

% ===================== 拟合参数 =====================
max_alpha_fit = 4;       % 硬界限：允许拟合的最大侧偏角绝对值 [deg]
R2_threshold  = 0.99;    % 决定系数阈值，低于此值认为线性度变差
min_points    = 3;       % 最少拟合点数（包含零点附近点）

C_deg = zeros(nLoads, 1);  % 侧偏刚度 (N/deg)
C_rad = zeros(nLoads, 1);  % 侧偏刚度 (N/rad)

% 准备绘图
figure('Name', '侧向力与线性拟合', 'NumberTitle', 'off');
cols = ceil(sqrt(nLoads));
rows = ceil(nLoads / cols);

for i = 1:nLoads
    Fy_curve = Fy_mat(:, i);   % 当前载荷下的侧向力
    
    % 找到最接近零的侧偏角索引（假设零点存在）
    [~, i0] = min(abs(alpha_vec));
    
    % 确定可扩展的方向
    can_left  = (i0 > 1);            % 左侧还有数据
    can_right = (i0 < length(alpha_vec));  % 右侧还有数据
    
    % 逐次增加窗口点数（向有数据的一侧扩展）
    best_k = NaN;
    idx_fit = [];
    alpha_fit = [];
    Fy_fit = [];
    
    % 初始窗口：至少包含 i0 及其一侧的 min_points-1 个点
    if can_right
        % 优先尝试向右扩展（适合大多数情况）
        w = min_points - 1;   % 向右增加 w 个点
        while (i0 + w) <= length(alpha_vec)
            idx = i0 : (i0 + w);   % 仅向右取点
            a = alpha_vec(idx);
            f = Fy_curve(idx);
            
            if max(abs(a)) > max_alpha_fit
                break;   % 超过硬界限
            end
            
            % 无截距线性回归
            k = sum(a .* f) / sum(a.^2);
            f_pred = k * a;
            SS_res = sum((f - f_pred).^2);
            SS_tot = sum(f.^2);
            R2 = 1 - SS_res / SS_tot;
            
            if R2 < R2_threshold
                break;   % 线性度下降
            end
            
            % 保存当前最优结果
            best_k = k;
            idx_fit = idx;
            alpha_fit = a;
            Fy_fit = f;
            
            w = w + 1;   % 继续向右扩展
        end
    elseif can_left
        % 如果只有左侧数据（理论上不会发生，但保留逻辑完整性）
        w = min_points - 1;
        while (i0 - w) >= 1
            idx = (i0 - w) : i0;
            a = alpha_vec(idx);
            f = Fy_curve(idx);
            
            if max(abs(a)) > max_alpha_fit
                break;
            end
            
            k = sum(a .* f) / sum(a.^2);
            f_pred = k * a;
            SS_res = sum((f - f_pred).^2);
            SS_tot = sum(f.^2);
            R2 = 1 - SS_res / SS_tot;
            
            if R2 < R2_threshold
                break;
            end
            
            best_k = k;
            idx_fit = idx;
            alpha_fit = a;
            Fy_fit = f;
            
            w = w + 1;
        end
    end
    
    % 检查是否成功拟合
    if isnan(best_k)
        warning('载荷 %.0f N 下未能找到有效的线性区，请调整 max_alpha_fit 或 R2_threshold。', Fz_vec(i));
        C_deg(i) = NaN;
        C_rad(i) = NaN;
        continue;
    end
    
    C_deg(i) = best_k;           % N/deg
    C_rad(i) = best_k * 180/pi;  % N/rad
    
    % 命令行输出拟合信息
    fprintf('载荷 = %8.0f N  →  侧偏刚度 = %8.2f N/deg (%8.2f N/rad)', ...
        Fz_vec(i), C_deg(i), C_rad(i));
    fprintf('   |  拟合点数: %d, 侧偏角范围: [%.2f, %.2f]°\n', ...
        length(idx_fit), min(alpha_fit), max(alpha_fit));
    
    % 绘图
    subplot(rows, cols, i);
    plot(alpha_vec, Fy_curve, 'b.-', 'DisplayName', '原始数据'); hold on;
    alpha_line = linspace(min(alpha_fit), max(alpha_fit), 50)';
    plot(alpha_line, best_k * alpha_line, 'r--', 'LineWidth', 1.5, 'DisplayName', '线性拟合');
    plot(alpha_fit, Fy_fit, 'ro', 'MarkerSize', 6, 'DisplayName', '拟合点');
    xlabel('侧偏角 (deg)'); ylabel('侧向力 (N)');
    title(sprintf('Fz = %.0f N', Fz_vec(i)));
    legend('Location', 'best'); grid on; hold off;
end

% 生成结果表
ResultTable = table(Fz_vec, C_deg, C_rad, ...
    'VariableNames', {'Load_N', 'CorneringStiffness_N_per_deg', 'CorneringStiffness_N_per_rad'});
disp(ResultTable);

% 保存结果
writetable(ResultTable, 'cornering_stiffness_results.xlsx');
fprintf('\n结果已保存至 cornering_stiffness_results.xlsx\n');