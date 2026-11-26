function robustness_test(part, nParts)
%ROBUSTNESS_TEST  新样本适应性检查：对样本做缩放、旋转、翻转、裁切、欠曝等变换后重新检测改进法。
%   robustness_test()            顺序处理全部变换并写出 outputs/evaluation/robustness.md
%   robustness_test(k, n)        只处理第 k 份（共 n 份），可开多个进程并行
%   robustness_test('merge', n)  合并 n 份分块结果并写出报告
%
%   用来模拟“助教给的全新图像”：分辨率不同（题述原图 2048×1370、更低的 1280×856）、
%   拍摄方向不同（旋转 90°、镜像、任意角度旋转并带黑边）、只拍到局部、曝光偏暗。
%   有隐裂样本的参考折线按同一变换映射到新图，计算参考覆盖率@50（容差按缩放比例换算），
%   用来检查定位是否随变换保持正确。参考折线只在统计时读取，不参与检测。
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'src'));
check_requirements();
outDir = fullfile(root, 'outputs', 'evaluation');
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end
files = {'cracked/cracked_07.jpg', 'cracked/cracked_03.jpg', 'uncracked/uncracked_07.jpg'};
V = variants();
if nargin == 2 && ischar(part) && strcmp(part, 'merge')
    lines = {};
    for k = 1:nParts
        t = read_text_utf8(fullfile(outDir, sprintf('robustness_part%d.csv', k)));
        L = regexp(t, '\r?\n', 'split');
        lines = [lines, L(~cellfun(@isempty, L))]; %#ok<AGROW>
    end
    write_report(outDir, files, V, lines);
    return;
end
if nargin < 1, part = 1; nParts = 1; end
A = jsondecode(read_text_utf8(fullfile(root, 'data', 'annotations.json')));
ann = A.images;
if isstruct(ann), ann = num2cell(ann); end
cfg = crack_config();
jobs = [kron((1:numel(files))', ones(numel(V), 1)), repmat((1:numel(V))', numel(files), 1)];
lines = {};
for j = part:nParts:size(jobs, 1)
    f = files{jobs(j, 1)};
    v = jobs(j, 2);
    G = read_gray(fullfile(root, f));
    P = ref_points(ann, f);
    [G2, P2, k] = V{v}{2}(G, P);
    res = detect_cracks(G2, cfg, false);
    cov = NaN;
    if ~isempty(P2)
        in = P2(:, 1) >= 1 & P2(:, 1) <= size(G2, 2) & P2(:, 2) >= 1 & P2(:, 2) <= size(G2, 1);
        P2 = round(P2(in, :));
        if ~isempty(P2)
            if any(res.mask(:))
                D = bwdist(res.mask);
                cov = mean(D(sub2ind(size(D), P2(:, 2), P2(:, 1))) <= 50 * k);
            else
                cov = 0;
            end
        end
    end
    lines{end + 1} = sprintf('%s,%d,%s,%d,%d,%d,%.4f,%.1f', f, v, res.statusCode, res.nCracks, ...
        size(G2, 2), size(G2, 1), cov, res.diag.runtime_s); %#ok<AGROW>
    fprintf('%s  %s  %s  裂纹数=%d  覆盖率@50=%.3f  %.0fs\n', f, V{v}{1}, res.statusCode, res.nCracks, cov, res.diag.runtime_s);
end
if nParts == 1
    write_report(outDir, files, V, lines);
else
    fid = fopen(fullfile(outDir, sprintf('robustness_part%d.csv', part)), 'w');
    fwrite(fid, unicode2native([strjoin(lines, sprintf('\n')) sprintf('\n')], 'UTF-8'));
    fclose(fid);
end
end

function V = variants()
% 每项：{名称, @(G, P) -> [变换后的图, 映射后的参考点, 长度缩放比例]}
V = {{'原图', @(G, P) deal(G, P, 1)}, ...
     {'缩小到 2048 宽（题述原图分辨率）', @(G, P) scale_to(G, P, 2048)}, ...
     {'缩小到 1280 宽（低分辨率）', @(G, P) scale_to(G, P, 1280)}, ...
     {'旋转 90°（细栅方向互换）', @rot_90}, ...
     {'水平镜像', @flip_lr}, ...
     {'旋转 22° 并带黑边', @(G, P) rot_any(G, P, 22)}, ...
     {'裁切中央 60%（局部）', @crop_center}, ...
     {'欠曝（灰度 × 0.6）', @(G, P) deal(G * 0.6, P, 1)}};
end

function [G2, P2, k] = scale_to(G, P, w)
k = w / size(G, 2);
G2 = resize_img(G, k);                     % 带抗混叠的缩小
k = size(G2, 2) / size(G, 2);
P2 = (P - 0.5) * k + 0.5;
end

function [G2, P2, k] = rot_90(G, P)
W = size(G, 2);
G2 = rot90(G);                              % 逆时针 90°：(x, y) -> (y, W - x + 1)
P2 = [P(:, 2), W - P(:, 1) + 1];
k = 1;
end

function [G2, P2, k] = flip_lr(G, P)
W = size(G, 2);
G2 = fliplr(G);
P2 = [W - P(:, 1) + 1, P(:, 2)];
k = 1;
end

function [G2, P2, k] = rot_any(G, P, a)
[H, W] = size(G);
G2 = imrotate(G, a, 'bilinear', 'loose');   % 旋转后四角为黑色（0）
[H2, W2] = size(G2);
c = [(W + 1) / 2, (H + 1) / 2];
c2 = [(W2 + 1) / 2, (H2 + 1) / 2];
dx = P(:, 1) - c(1); dy = P(:, 2) - c(2);
P2 = [c2(1) + cosd(a) * dx + sind(a) * dy, c2(2) - sind(a) * dx + cosd(a) * dy];
k = 1;
end

function [G2, P2, k] = crop_center(G, P)
[H, W] = size(G);
r0 = round(0.2 * H) + 1; r1 = round(0.8 * H);
c0 = round(0.2 * W) + 1; c1 = round(0.8 * W);
G2 = G(r0:r1, c0:c1);
P2 = [P(:, 1) - c0 + 1, P(:, 2) - r0 + 1];
k = 1;
end

function P = ref_points(ann, f)
% 参考折线按约 2 px 间距加密（原图坐标）；无隐裂样本返回空
P = zeros(0, 2);
for i = 1:numel(ann)
    if ~strcmpi(ann{i}.file, f), continue; end
    pl = ann{i}.polylines;
    if isstruct(pl), pl = num2cell(pl); end
    for q = 1:numel(pl)
        Q = double(pl{q}.points);
        for s = 1:size(Q, 1) - 1
            n = max(2, ceil(norm(Q(s + 1, :) - Q(s, :)) / 2));
            t = linspace(0, 1, n)';
            P = [P; Q(s, :) + t * (Q(s + 1, :) - Q(s, :))]; %#ok<AGROW>
        end
    end
end
end

function write_report(outDir, files, V, lines)
fid = fopen(fullfile(outDir, 'robustness.csv'), 'w');
fwrite(fid, unicode2native(['file,variant,status_code,n_cracks,width,height,coverage50,runtime_s' sprintf('\n') ...
    strjoin(lines, sprintf('\n')) sprintf('\n')], 'UTF-8'));
fclose(fid);
names = struct('crack', '有隐裂', 'no_crack', '无隐裂', 'review', '待复核', 'error', '处理失败');
md = {'# 新样本适应性检查（`tools/robustness_test.m`）', '', ...
      '对样本做变换后用默认参数重新检测（改进法）。参考覆盖率@50 的容差按缩放比例换算，参考折线按同一变换映射；裁切时只统计落在裁切范围内的参考点。', '', ...
      '| 样本 | 变换 | 尺寸 | 判定 | 正确 | 裂纹数 | 参考覆盖率@50 | 用时 (s) |', '|---|---|---|---|---|---|---|---|'};
nOk = 0; nAll = 0;
for i = 1:numel(files)
    for v = 1:numel(V)
        hit = find(strncmp(lines, [files{i} ',' num2str(v) ','], numel(files{i}) + numel(num2str(v)) + 2), 1);
        if isempty(hit), continue; end
        c = regexp(lines{hit}, ',', 'split');
        y = isempty(strfind(files{i}, 'uncracked'));
        ok = (y && strcmp(c{3}, 'crack')) || (~y && strcmp(c{3}, 'no_crack'));
        nOk = nOk + ok; nAll = nAll + 1;
        cv = str2double(c{7});
        if isnan(cv), cs = '—'; else, cs = sprintf('%.1f%%', 100 * cv); end
        st = c{3};
        if isfield(names, st), st = names.(st); end
        okS = '✓'; if ~ok, okS = '✗'; end
        [~, stem] = fileparts(files{i});
        md{end + 1} = sprintf('| %s | %s | %s×%s | %s | %s | %s | %s | %s |', stem, V{v}{1}, c{5}, c{6}, st, okS, c{4}, cs, c{8}); %#ok<AGROW>
    end
end
md{end + 1} = '';
md{end + 1} = sprintf('判定正确 %d / %d。', nOk, nAll);
fid = fopen(fullfile(outDir, 'robustness.md'), 'w');
fwrite(fid, unicode2native(strjoin(md, sprintf('\n')), 'UTF-8'));
fclose(fid);
fprintf('新样本适应性检查结果已写入 %s\n', fullfile(outDir, 'robustness.md'));
end
