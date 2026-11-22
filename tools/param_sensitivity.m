function param_sensitivity(part, nParts)
%PARAM_SENSITIVITY  参数敏感性检查：关键参数逐个上下浮动，统计 20 张图的判定变化。
%   param_sensitivity()            顺序处理全部图像并写出报告
%   param_sensitivity(k, n)        只处理第 k 份（共 n 份），写出分块结果，可多进程并行
%   param_sensitivity('merge', n)  合并 n 份分块结果并写出报告
%   每张图只计算一次 crack_response（前端与暗线响应），各参数变体只重跑 segment_cracks 的判定部分。
%   结果写入 outputs/evaluation/param_sensitivity.md / .csv；需要 data/labels.csv（仅用于统计）。
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root, 'src'));
if exist('OCTAVE_VERSION', 'builtin') ~= 0
    pkg load image
end
outDir = fullfile(root, 'outputs', 'evaluation');
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end
V = variants();
if nargin == 2 && ischar(part) && strcmp(part, 'merge')
    lines = {};
    for k = 1:nParts
        t = read_text_utf8(fullfile(outDir, sprintf('param_sensitivity_part%d.csv', k)));
        L = regexp(t, '\r?\n', 'split');
        lines = [lines, L(~cellfun(@isempty, L))]; %#ok<AGROW>
    end
    write_report(root, outDir, V, lines);
    return;
end
if nargin < 1, part = 1; nParts = 1; end
files = list_images({fullfile(root, 'cracked'), fullfile(root, 'uncracked')}, false);
sel = part:nParts:numel(files);
lines = {};
for i = sel
    G = read_gray(files(i).path);
    base = crack_config();
    Rs = crack_response(G, base);
    for v = 1:numel(V)
        cfg = base;
        o = V{v}{2};
        for k = 1:2:numel(o), cfg.(o{k}) = o{k + 1}; end
        res = segment_cracks(Rs, [], cfg, false);
        lines{end + 1} = sprintf('%s,%d,%s,%d', files(i).relpath, v, res.statusCode, res.nCracks); %#ok<AGROW>
    end
    fprintf('%s done\n', files(i).relpath);
end
if nParts == 1
    write_report(root, outDir, V, lines);
else
    fid = fopen(fullfile(outDir, sprintf('param_sensitivity_part%d.csv', part)), 'w');
    fwrite(fid, unicode2native([strjoin(lines, sprintf('\n')) sprintf('\n')], 'UTF-8'));
    fclose(fid);
end
end

function V = variants()
V = {{'默认参数', {}}, ...
     {'zHigh = 4.0', {'zHigh', 4.0}}, {'zHigh = 5.0', {'zHigh', 5.0}}, {'zHigh = 5.5', {'zHigh', 5.5}}, ...
     {'zLow = 2.0', {'zLow', 2.0}}, {'zLow = 3.0', {'zLow', 3.0}}, ...
     {'minLength = 2.5', {'minLength', 2.5}}, {'minLength = 4.0', {'minLength', 4.0}}, ...
     {'minCross = 1.5', {'minCross', 1.5}}, {'minCross = 3.0', {'minCross', 3.0}}, ...
     {'minMeanZ = 2.5', {'minMeanZ', 2.5}}, {'minMeanZ = 3.5', {'minMeanZ', 3.5}}, ...
     {'linkGapLong = 1.5（不做长距离连接）', {'linkGapLong', 1.5}}, ...
     {'maxBusbarFrac = 1.0（不排除汇流条带候选）', {'maxBusbarFrac', 1.0}}};
end

function write_report(root, outDir, V, lines)
labels = read_csv_simple(fullfile(root, 'data', 'labels.csv'));
lf = {labels.file};
fid = fopen(fullfile(outDir, 'param_sensitivity.csv'), 'w');
fwrite(fid, unicode2native(['file,variant,status_code,n_cracks' sprintf('\n') strjoin(lines, sprintf('\n')) sprintf('\n')], 'UTF-8'));
fclose(fid);
md = {'# 参数敏感性（逐个参数改变，其余保持默认）', '', ...
      '| 参数设置 | TP | FN | TN | FP | 待复核 | 判定改变的图像 |', '|---|---|---|---|---|---|---|'};
for v = 1:numel(V)
    tp = 0; fn = 0; tn = 0; fp = 0; rv = 0; bad = {};
    for i = 1:numel(lines)
        c = regexp(lines{i}, ',', 'split');
        if str2double(c{2}) ~= v, continue; end
        k = find(strcmp(lf, c{1}), 1);
        if isempty(k), continue; end
        y = str2double(labels(k).label);
        [~, stem] = fileparts(c{1});
        switch c{3}
            case 'crack'
                if y == 1, tp = tp + 1; else, fp = fp + 1; bad{end + 1} = [stem '(FP)']; end %#ok<AGROW>
            case 'no_crack'
                if y == 0, tn = tn + 1; else, fn = fn + 1; bad{end + 1} = [stem '(FN)']; end %#ok<AGROW>
            otherwise
                rv = rv + 1; bad{end + 1} = [stem '(待复核)']; %#ok<AGROW>
        end
    end
    md{end + 1} = sprintf('| %s | %d | %d | %d | %d | %d | %s |', V{v}{1}, tp, fn, tn, fp, rv, strjoin(bad, '、')); %#ok<AGROW>
end
fid = fopen(fullfile(outDir, 'param_sensitivity.md'), 'w');
fwrite(fid, unicode2native(strjoin(md, sprintf('\n')), 'UTF-8'));
fclose(fid);
fprintf('参数敏感性结果已写入 %s\n', outDir);
end
