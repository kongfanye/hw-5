function summary = run_batch(inputDirs, outDir, varargin)
%RUN_BATCH  扫描目录、逐图检测并导出结果。
%   summary = run_batch(inputDirs, outDir)
%   summary = run_batch(inputDirs, outDir, 'Method', 'baseline', 'Debug', {'cracked_07'})
%
%   inputDirs : 字符串或元胞数组，图像所在目录（扩展名大小写不敏感）
%   outDir    : 输出目录，写入 results.csv、defects.json、overlays/、masks/、
%               debug/、run_config.json、run_log.txt
%   选项：
%     'Method'    'improved'（默认）或 'baseline'
%     'Config'    参数结构体（默认 crack_config()）
%     'Debug'     需要输出中间结果的文件名（不含扩展名）元胞数组；{'*'} 为全部
%     'Recursive' 是否递归扫描子目录（默认 false）
%   单张图读取或处理失败时记录原因并继续处理其余图像。

root = fileparts(mfilename('fullpath'));
addpath(fullfile(root, 'src'));
if exist('OCTAVE_VERSION', 'builtin') ~= 0
    pkg load image
end
opt = struct('Method', 'improved', 'Config', [], 'Debug', {{}}, 'Recursive', false);
for i = 1:2:numel(varargin)
    opt.(varargin{i}) = varargin{i + 1};
end
cfg = opt.Config;
if isempty(cfg), cfg = crack_config(); end
if ischar(inputDirs), inputDirs = {inputDirs}; end
method = lower(opt.Method);
if ~any(strcmp(method, {'improved', 'baseline'}))
    error('未知方法 %s', method);
end
dirs = {'overlays', 'masks', 'debug'};
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end
for i = 1:numel(dirs)
    if exist(fullfile(outDir, dirs{i}), 'dir') ~= 7, mkdir(fullfile(outDir, dirs{i})); end
end
info = env_info();
files = list_images(inputDirs, opt.Recursive);
% 文件名重复时加目录名前缀
stems = {files.stem};
ids = stems;
for i = 1:numel(files)
    if nnz(strcmp(stems, stems{i})) > 1
        ids{i} = regexprep(strrep(files(i).relpath, '/', '__'), '\.[^.]*$', '');
    end
end

logPath = fullfile(outDir, 'run_log.txt');
lf = fopen(logPath, 'w');
logmsg(lf, '==== 太阳能电池片隐裂检测批处理 ====');
logmsg(lf, sprintf('时间: %s', info.time));
logmsg(lf, sprintf('命令: run_batch(%s, ''%s'', ''Method'', ''%s'')', cell_str(inputDirs), outDir, method));
logmsg(lf, sprintf('运行环境: %s; %s; %s', info.platform, info.imageToolbox, info.computer));
logmsg(lf, sprintf('输入目录: %s', strjoin(inputDirs, '; ')));
logmsg(lf, sprintf('方法: %s; 参数版本 %s（完整参数见 run_config.json）', method, cfg.version));
logmsg(lf, sprintf('找到图像: %d 张', numel(files)));
write_json(fullfile(outDir, 'run_config.json'), struct('method', method, 'environment', info, ...
    'input_dirs', {inputDirs}, 'config', cfg));

recs = struct([]);
nErr = 0;
for i = 1:numel(files)
    f = files(i);
    r = struct('file', f.relpath, 'id', ids{i}, 'status', '读取失败', 'status_code', 'error', ...
        'n_cracks', 0, 'review_reason', '', 'notes', '', 'overlay', '', 'mask', '', ...
        'width', 0, 'height', 0, 'finger_angle_deg', NaN, 'pitch_px', NaN, ...
        'valid_frac', NaN, 'bright_frac', NaN, 'runtime_s', NaN, 'error', '');
    detail = struct('file', f.relpath, 'status', r.status, 'status_code', 'error', ...
        'image_size', [], 'n_cracks', 0, 'review_reasons', {{}}, 'notes', {{}}, ...
        'diagnostics', struct(), 'overlay', '', 'mask', '', 'cracks', {{}}, 'error', '');
    t0 = tic;
    try
        [G, RGB] = read_gray(f.path);
    catch err
        nErr = nErr + 1;
        r.error = ['读取失败: ' clean(err.message)];
        detail.error = r.error;
        logmsg(lf, sprintf('[%d/%d] %s  读取失败: %s', i, numel(files), f.relpath, err.message));
        recs = append_rec(recs, r, detail);
        continue;
    end
    try
        wantDebug = any(strcmp(opt.Debug, '*')) || any(strcmp(opt.Debug, f.stem));
        if strcmp(method, 'improved')
            res = detect_cracks(G, cfg, wantDebug);
        else
            res = detect_baseline(G, cfg, wantDebug);
        end
        O = make_overlay(RGB, res, method);
        ovRel = ['overlays/' ids{i} '.jpg'];
        mkRel = ['masks/' ids{i} '.png'];
        imwrite(O, fullfile(outDir, 'overlays', [ids{i} '.jpg']), 'Quality', cfg.overlayQuality);
        imwrite(res.mask, fullfile(outDir, 'masks', [ids{i} '.png']));
        if wantDebug
            save_debug(res, RGB, O, fullfile(outDir, 'debug'), ids{i}, cfg);
        end
        r.status = res.status; r.status_code = res.statusCode;
        r.n_cracks = res.nCracks;
        r.review_reason = clean(strjoin(res.reviewReasons, '；'));
        r.notes = clean(strjoin(res.notes, '；'));
        r.overlay = ovRel; r.mask = mkRel;
        r.height = size(G, 1); r.width = size(G, 2);
        r.finger_angle_deg = res.diag.fingerAngleDeg;
        r.pitch_px = res.diag.pitchFullPx;
        r.valid_frac = res.diag.validFrac;
        r.bright_frac = res.diag.brightFrac;
        r.runtime_s = toc(t0);
        detail.status = res.status; detail.status_code = res.statusCode;
        detail.image_size = [size(G, 2), size(G, 1)];
        detail.n_cracks = res.nCracks;
        detail.review_reasons = res.reviewReasons;
        detail.notes = res.notes;
        dg = res.diag;
        detail.diagnostics = struct('finger_angle_deg', dg.fingerAngleDeg, 'grid_ok', dg.gridOk, ...
            'grid_periodicity', round(dg.periodicity * 1000) / 1000, 'pitch_px', round(dg.pitchFullPx * 100) / 100, ...
            'work_scale', round(dg.workScale * 10000) / 10000, 'valid_frac', round(dg.validFrac * 1000) / 1000, ...
            'bright_frac', round(dg.brightFrac * 1000) / 1000, 'n_candidates', dg.nCandidates, ...
            'runtime_s', round(r.runtime_s * 10) / 10);
        detail.overlay = ovRel; detail.mask = mkRel;
        detail.cracks = crack_list(res.cracks);
        logmsg(lf, sprintf('[%d/%d] %s  %s  裂纹数=%d  方向=%.1f°  栅距=%.1fpx  有效区=%.0f%%  %.1fs %s', ...
            i, numel(files), f.relpath, res.status, res.nCracks, dg.fingerAngleDeg, dg.pitchFullPx, ...
            100 * dg.validFrac, r.runtime_s, r.review_reason));
    catch err
        nErr = nErr + 1;
        r.status = '处理失败'; r.status_code = 'error';
        r.error = ['处理失败: ' clean(err.message)];
        detail.status = r.status; detail.error = r.error;
        st = err.stack;
        where = '';
        if ~isempty(st), where = sprintf(' (%s:%d)', st(1).name, st(1).line); end
        logmsg(lf, sprintf('[%d/%d] %s  处理失败: %s%s', i, numel(files), f.relpath, err.message, where));
    end
    recs = append_rec(recs, r, detail);
    clear G RGB res O
end

% ---- 汇总输出 ----
write_results_csv(fullfile(outDir, 'results.csv'), recs);
details = {};
for i = 1:numel(recs), details{end + 1} = recs(i).detail; end %#ok<AGROW>
J = struct();
J.method = method;
J.coordinate_system = ['原图像素坐标：左上角像素中心为 (1,1)，x 为列向右，y 为行向下；' ...
    'bbox = [x_min, y_min, x_max, y_max]（含两端）；points 为中心线采样点 [x, y]'];
J.generated = info.time;
J.environment = [info.platform '; ' info.imageToolbox];
J.config_file = 'run_config.json';
J.images = details;
write_json(fullfile(outDir, 'defects.json'), J);
codes = arrayfun(@(x) x.rec.status_code, recs, 'UniformOutput', false);
summary.method = method;
summary.outDir = outDir;
summary.n = numel(recs);
summary.nCrack = nnz(strcmp(codes, 'crack'));
summary.nNoCrack = nnz(strcmp(codes, 'no_crack'));
summary.nReview = nnz(strcmp(codes, 'review'));
summary.nError = nErr;
logmsg(lf, sprintf('完成: 共 %d 张；有隐裂 %d，无隐裂 %d，待复核 %d，错误 %d', summary.n, ...
    summary.nCrack, summary.nNoCrack, summary.nReview, summary.nError));
fclose(lf);
end

function recs = append_rec(recs, r, detail)
k = numel(recs) + 1;
if k == 1
    recs = struct('rec', r, 'detail', detail);
else
    recs(k).rec = r; recs(k).detail = detail;
end
end

function C = crack_list(cr)
C = {};
for i = 1:numel(cr)
    c = cr(i);
    s = struct('id', c.id, 'bbox', c.bbox, 'centroid', round(c.centroid * 10) / 10, ...
        'length_px', round(c.length_px * 10) / 10, 'width_px', round(c.width_px * 10) / 10, ...
        'angle_deg', round(c.angle_deg * 10) / 10);
    if isfield(c, 'mean_z')
        s.mean_z = c.mean_z; s.contrast_pct = c.contrast_pct;
        s.n_fingers_crossed = c.n_fingers_crossed;
    end
    s.endpoints = c.endpoints;
    s.points = c.points;
    C{end + 1} = s; %#ok<AGROW>
end
end

function write_results_csv(path, recs)
fid = fopen(path, 'w');
fwrite(fid, uint8([239 187 191]));     % UTF-8 BOM，便于 Excel 正确显示中文
hdr = {'file', 'status', 'status_code', 'n_cracks', 'review_reason', 'notes', 'overlay', 'mask', ...
    'width', 'height', 'finger_angle_deg', 'pitch_px', 'valid_frac', 'bright_frac', 'runtime_s', 'error'};
put(fid, strjoin(hdr, ','));
for i = 1:numel(recs)
    r = recs(i).rec;
    row = {r.file, r.status, r.status_code, sprintf('%d', r.n_cracks), r.review_reason, r.notes, ...
        r.overlay, r.mask, sprintf('%d', r.width), sprintf('%d', r.height), num(r.finger_angle_deg, 2), ...
        num(r.pitch_px, 2), num(r.valid_frac, 3), num(r.bright_frac, 3), num(r.runtime_s, 1), r.error};
    put(fid, strjoin(row, ','));
end
fclose(fid);
end

function put(fid, s)
fwrite(fid, unicode2native([s sprintf('\n')], 'UTF-8'));
end

function s = num(v, d)
if isnan(v), s = ''; else, s = sprintf(['%.' num2str(d) 'f'], v); end
end

function s = clean(s)
% CSV 字段内不出现英文逗号与换行
s = strrep(strrep(strrep(s, ',', '；'), sprintf('\n'), ' '), sprintf('\r'), ' ');
end

function s = cell_str(c)
s = ['{''' strjoin(c, ''', ''') '''}'];
end

function logmsg(fid, s)
fprintf('%s\n', s);
if fid > 0
    fwrite(fid, unicode2native([s sprintf('\n')], 'UTF-8'));
end
end
