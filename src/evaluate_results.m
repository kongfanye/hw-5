function E = evaluate_results(root, methodDirs, outDir, tolList)
%EVALUATE_RESULTS  用参考标签与位置标注评估检测结果（只在评估阶段读取标签）。
%   E = evaluate_results(root, {'outputs', 'outputs/baseline'}, 'outputs/evaluation', [25 50])
%   图像级：TP/FP/TN/FN、准确率、查准率、召回率、F1、无隐裂样本误报张数；
%           待复核单独计数，指标分母为已判定的图像，另给出"待复核按有隐裂计"的口径。
%   位置级：参考折线与预测掩膜的双向邻域覆盖率（容差 tol 像素）：
%           参考覆盖率 = 参考折线采样点中距预测掩膜 <= tol 的比例；
%           预测精度   = 预测掩膜像素中距参考折线 <= tol 的比例；
%           区域内比例 = 预测掩膜像素落在参考折线 tol 邻域或参考区域框内的比例。
if nargin < 4, tolList = [25 50]; end
labels = read_csv_simple(fullfile(root, 'data', 'labels.csv'));
A = jsondecode(read_text_utf8(fullfile(root, 'data', 'annotations.json')));
ann = A.images;
if isstruct(ann), ann = num2cell(ann); end
annFiles = cellfun(@(a) a.file, ann, 'UniformOutput', false);
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end
E = struct();
md = {};
md{end + 1} = '# 检测结果评估';
md{end + 1} = '';
md{end + 1} = sprintf('生成时间：%s。参考标签：`data/labels.csv`；位置标注：`data/annotations.json`（人工折线，标注精度约 %d px）。', ...
    datestr(now, 'yyyy-mm-dd HH:MM'), A.annotation_precision_px);
md{end + 1} = '';
perImg = {};
for m = 1:numel(methodDirs)
    mdir = fullfile(root, methodDirs{m});
    R = read_csv_simple(fullfile(mdir, 'results.csv'));
    rf = {R.file};
    name = methodDirs{m};
    if ~isempty(regexp(name, 'baseline$', 'once'))
        title = sprintf('基线（`%s`）', name);
    else
        title = sprintf('改进法（`%s`）', name);
    end
    % ---------- 图像级 ----------
    tp = 0; fp = 0; tn = 0; fn = 0; rvP = 0; rvN = 0; er = 0;
    rows = {};
    for i = 1:numel(labels)
        L = labels(i);
        y = str2double(L.label);
        k = find(strcmp(rf, L.file), 1);
        if isempty(k)
            code = 'missing'; st = '缺失';
        else
            code = R(k).status_code; st = R(k).status;
        end
        switch code
            case 'crack', if y == 1, tp = tp + 1; o = 'TP'; else, fp = fp + 1; o = 'FP'; end
            case 'no_crack', if y == 1, fn = fn + 1; o = 'FN'; else, tn = tn + 1; o = 'TN'; end
            case 'review', if y == 1, rvP = rvP + 1; else, rvN = rvN + 1; end; o = '待复核';
            otherwise, er = er + 1; o = '错误';
        end
        rows{end + 1} = struct('file', L.file, 'label', y, 'status', st, 'outcome', o, ...
            'group', L.shoot_group, 'conditions', L.conditions, 'k', k); %#ok<AGROW>
    end
    nDec = tp + fp + tn + fn;
    M = metrics(tp, fp, tn, fn);
    M2 = metrics(tp + rvP, fp + rvN, tn, fn);   % 待复核按"有隐裂"计
    S.tp = tp; S.fp = fp; S.tn = tn; S.fn = fn; S.reviewPos = rvP; S.reviewNeg = rvN; S.errors = er;
    S.decided = nDec; S.metrics = M; S.metricsReviewAsCrack = M2;
    nNeg = nnz(cellfun(@(r) r.label == 0, rows));
    md{end + 1} = ['## ' title];
    md{end + 1} = '';
    md{end + 1} = '### 图像级判定';
    md{end + 1} = '';
    md{end + 1} = '| TP | FP | TN | FN | 待复核(有隐裂/无隐裂) | 错误 | 已判定张数 |';
    md{end + 1} = '|---|---|---|---|---|---|---|';
    md{end + 1} = sprintf('| %d | %d | %d | %d | %d / %d | %d | %d |', tp, fp, tn, fn, rvP, rvN, er, nDec);
    md{end + 1} = '';
    md{end + 1} = '| 口径 | 准确率 | 查准率 | 召回率 | F1 | 无隐裂样本误报 |';
    md{end + 1} = '|---|---|---|---|---|---|';
    md{end + 1} = sprintf('| 已判定图像（分母 %d） | %s | %s | %s | %s | %d / %d |', nDec, pct(M.accuracy), pct(M.precision), pct(M.recall), pct(M.f1), fp, nNeg - rvN);
    md{end + 1} = sprintf('| 待复核计为有隐裂（分母 %d） | %s | %s | %s | %s | %d / %d |', nDec + rvP + rvN, pct(M2.accuracy), pct(M2.precision), pct(M2.recall), pct(M2.f1), fp + rvN, nNeg);
    md{end + 1} = '';
    % ---------- 位置级 ----------
    md{end + 1} = '### 位置评估（有隐裂图像，参考折线）';
    md{end + 1} = '';
    hdr = '| 图像 | 判定 | 预测裂纹数 | 参考折线数';
    sep = '|---|---|---|---';
    for t = tolList
        hdr = [hdr sprintf(' | 参考覆盖率@%d', t) sprintf(' | 预测精度@%d', t)]; %#ok<AGROW>
        sep = [sep '|---|---']; %#ok<AGROW>
    end
    hdr = [hdr sprintf(' | 区域内比例@%d |', tolList(end))];
    sep = [sep '|---|'];
    md{end + 1} = hdr; md{end + 1} = sep;
    loc = struct('file', {}, 'refCov', {}, 'predPrec', {}, 'inRegion', {});
    pooledRef = zeros(numel(tolList), 2); pooledPred = zeros(numel(tolList), 2); pooledReg = [0 0];
    for i = 1:numel(rows)
        r = rows{i};
        a = find(strcmp(annFiles, r.file), 1);
        if r.label ~= 1 || isempty(a) || isempty(r.k), continue; end
        if ~any(strcmp(R(r.k).status_code, {'crack', 'no_crack', 'review'}))
            md{end + 1} = sprintf('| %s | %s | — | — | 未评估（处理失败，无掩膜） |', r.file, r.status); %#ok<AGROW>
            continue;
        end
        an = ann{a};
        pl = an.polylines;
        if isempty(pl), continue; end
        if isstruct(pl), pl = num2cell(pl); end
        maskPath = fullfile(mdir, R(r.k).mask);
        nPred = str2double(R(r.k).n_cracks);
        H = str2double(R(r.k).height); W = str2double(R(r.k).width);
        if exist(maskPath, 'file') == 2
            pm = imread(maskPath) > 0;
        else
            pm = false(H, W);
        end
        [cov, prec, inReg, nRefPts, nPredPx] = loc_metrics(pm, pl, an.regions, tolList);
        line = sprintf('| %s | %s | %d | %d', r.file, r.status, nPred, numel(pl));
        for t = 1:numel(tolList)
            line = [line sprintf(' | %s | %s', pct(cov(t)), pct(prec(t)))]; %#ok<AGROW>
            pooledRef(t, :) = pooledRef(t, :) + [cov(t) * nRefPts, nRefPts];
            if nPredPx > 0
                pooledPred(t, :) = pooledPred(t, :) + [prec(t) * nPredPx, nPredPx];
            end
        end
        if nPredPx > 0, pooledReg = pooledReg + [inReg * nPredPx, nPredPx]; end
        md{end + 1} = [line sprintf(' | %s |', pct(inReg))]; %#ok<AGROW>
        loc(end + 1) = struct('file', r.file, 'refCov', cov, 'predPrec', prec, 'inRegion', inReg); %#ok<AGROW>
    end
    line = '| **合计（按点/像素汇总）** | | | ';
    for t = 1:numel(tolList)
        line = [line sprintf(' | %s | %s', pct(pooledRef(t, 1) / max(pooledRef(t, 2), 1)), ...
            pct(ratio(pooledPred(t, :))))]; %#ok<AGROW>
    end
    md{end + 1} = [line sprintf(' | %s |', pct(ratio(pooledReg)))];
    md{end + 1} = '';
    md{end + 1} = '说明：参考折线只覆盖目视确认的主要裂纹，网状裂纹的细小分支未逐条描线，因此"预测精度"偏保守；"区域内比例"把落在参考区域框内的预测也计为合理位置。';
    md{end + 1} = '';
    % ---------- 无隐裂图像的误检面积 ----------
    md{end + 1} = '### 逐张结果';
    md{end + 1} = '';
    md{end + 1} = '| 图像 | 参考 | 判定 | 结果 | 拍摄组 | 样本条件 | 复核原因/备注 |';
    md{end + 1} = '|---|---|---|---|---|---|---|';
    for i = 1:numel(rows)
        r = rows{i};
        note = '';
        if ~isempty(r.k)
            note = strjoin(setdiff({R(r.k).review_reason, R(r.k).notes, R(r.k).error}, {''}), '；');
        end
        md{end + 1} = sprintf('| %s | %s | %s | %s | %s | %s | %s |', r.file, lab_name(r.label), r.status, ...
            r.outcome, r.group, strrep(r.conditions, ';', '、'), note); %#ok<AGROW>
        perImg{end + 1} = sprintf('%s,%s,%d,%s,%s', name, r.file, r.label, r.status, r.outcome); %#ok<AGROW>
    end
    md{end + 1} = '';
    % ---------- 按条件分组 ----------
    md{end + 1} = '### 按样本条件汇总';
    md{end + 1} = '';
    md{end + 1} = '| 条件 | 张数 | 正确 | 错误(FP/FN) | 待复核 |';
    md{end + 1} = '|---|---|---|---|---|';
    tags = {};
    for i = 1:numel(rows), tags = [tags, strsplit(rows{i}.conditions, ';')]; end %#ok<AGROW>
    tags = unique(tags);
    for t = 1:numel(tags)
        sel = cellfun(@(r) any(strcmp(strsplit(r.conditions, ';'), tags{t})), rows);
        oc = cellfun(@(r) r.outcome, rows(sel), 'UniformOutput', false);
        md{end + 1} = sprintf('| %s | %d | %d | %d | %d |', tags{t}, nnz(sel), nnz(strcmp(oc, 'TP') | strcmp(oc, 'TN')), ...
            nnz(strcmp(oc, 'FP') | strcmp(oc, 'FN')), nnz(strcmp(oc, '待复核'))); %#ok<AGROW>
    end
    md{end + 1} = '';
    S.localization = loc;
    S.pooledRefCoverage = pooledRef(:, 1) ./ max(pooledRef(:, 2), 1);
    E.(matlab_name(name)) = S;
end
fid = fopen(fullfile(outDir, 'evaluation.md'), 'w');
fwrite(fid, unicode2native(strjoin(md, sprintf('\n')), 'UTF-8'));
fclose(fid);
fid = fopen(fullfile(outDir, 'evaluation_per_image.csv'), 'w');
fwrite(fid, uint8([239 187 191]));
fwrite(fid, unicode2native(['method,file,label,status,outcome' sprintf('\n') strjoin(perImg, sprintf('\n')) sprintf('\n')], 'UTF-8'));
fclose(fid);
write_json(fullfile(outDir, 'evaluation.json'), E);
fprintf('评估结果已写入 %s\n', outDir);
end

function M = metrics(tp, fp, tn, fn)
M.accuracy = (tp + tn) / max(tp + fp + tn + fn, 1);
M.precision = NaN; M.recall = NaN; M.f1 = NaN;
if tp + fp > 0, M.precision = tp / (tp + fp); end
if tp + fn > 0, M.recall = tp / (tp + fn); end
if M.precision + M.recall > 0, M.f1 = 2 * M.precision * M.recall / (M.precision + M.recall); end
end

function s = pct(x)
if isnan(x), s = '—'; else, s = sprintf('%.1f%%', 100 * x); end
end

function r = ratio(v)
if v(2) == 0, r = NaN; else, r = v(1) / v(2); end
end

function s = lab_name(y)
if y == 1, s = '有隐裂'; else, s = '无隐裂'; end
end

function n = matlab_name(s)
n = regexprep(s, '[^A-Za-z0-9]', '_');
if isempty(regexp(n, '^[A-Za-z]', 'once')), n = ['m_' n]; end
end

function [cov, prec, inReg, nRef, nPred] = loc_metrics(pm, pl, regions, tolList)
[H, W] = size(pm);
% 参考折线栅格化（每 2 px 采样）
pts = zeros(0, 2);
for i = 1:numel(pl)
    P = pl{i}.points;
    for j = 1:size(P, 1) - 1
        n = max(2, ceil(norm(P(j + 1, :) - P(j, :)) / 2));
        t = linspace(0, 1, n)';
        pts = [pts; P(j, :) + t .* (P(j + 1, :) - P(j, :))]; %#ok<AGROW>
    end
end
pts = round(pts);
pts = pts(pts(:, 1) >= 1 & pts(:, 1) <= W & pts(:, 2) >= 1 & pts(:, 2) <= H, :);
nRef = size(pts, 1);
refMask = false(H, W);
refMask(sub2ind([H W], pts(:, 2), pts(:, 1))) = true;
dPred = bwdist(pm);
dRef = bwdist(refMask);
[py, px] = find(pm);
nPred = numel(py);
regMask = false(H, W);
if ~isempty(regions)
    for r = 1:size(regions, 1)
        b = regions(r, :);
        regMask(max(1, b(2)):min(H, b(4)), max(1, b(1)):min(W, b(3))) = true;
    end
end
cov = zeros(1, numel(tolList)); prec = nan(1, numel(tolList));
dp = dPred(sub2ind([H W], pts(:, 2), pts(:, 1)));
for t = 1:numel(tolList)
    cov(t) = mean(dp <= tolList(t));
    if nPred > 0
        prec(t) = mean(dRef(pm) <= tolList(t));
    end
end
if nPred > 0
    inReg = mean(dRef(pm) <= tolList(end) | regMask(pm));
else
    inReg = NaN;
end
end
