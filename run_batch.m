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
check_requirements();
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
    [r, detail] = empty_record(f.relpath, ids{i});
    t0 = tic;
    try
        [G, RGB] = read_gray(f.path);
    catch err
        nErr = nErr + 1;
        r.error = ['读取失败: ' csv_clean(err.message)];
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
        [r, detail] = fill_record(r, detail, res, size(G), toc(t0), ovRel, mkRel);
        dg = res.diag;
        logmsg(lf, sprintf('[%d/%d] %s  %s  裂纹数=%d  方向=%.1f°  栅距=%.1fpx  有效区=%.0f%%  %.1fs %s', ...
            i, numel(files), f.relpath, res.status, res.nCracks, dg.fingerAngleDeg, dg.pitchFullPx, ...
            100 * dg.validFrac, r.runtime_s, r.review_reason));
    catch err
        nErr = nErr + 1;
        r.status = '处理失败'; r.status_code = 'error';
        r.error = ['处理失败: ' csv_clean(err.message)];
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
write_defects_json(fullfile(outDir, 'defects.json'), method, info, details);
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

function s = cell_str(c)
s = ['{''' strjoin(c, ''', ''') '''}'];
end

function logmsg(fid, s)
fprintf('%s\n', s);
if fid > 0
    fwrite(fid, unicode2native([s sprintf('\n')], 'UTF-8'));
end
end
