function files = list_images(inputPaths, recursive)
%LIST_IMAGES  扫描输入路径中的图像（支持单个图像文件、目录或二者混合的元胞数组）。
%   排除目录扫描中的：题目截图 {GUID}.png、预览图、程序输出（overlay/mask/debug/outputs 目录等）。
%   显式传入的单个图像文件不受文件名过滤限制。
%   返回结构数组：path（绝对路径）、relpath（"目录名/文件名"）、name、stem、ext。
if nargin < 2, recursive = false; end
if ischar(inputPaths), inputPaths = {inputPaths}; end
exts = {'.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff'};
skipDirs = {'outputs', 'output', 'overlays', 'masks', 'debug', 'baseline', 'evaluation', 'inspect', '.git'};
files = struct('path', {}, 'relpath', {}, 'name', {}, 'stem', {}, 'ext', {});
for d = 1:numel(inputPaths)
    p = inputPaths{d};
    if isempty(p), continue; end
    if exist(p, 'file') == 2 && exist(p, 'dir') ~= 7
        files = add_single_file(p, files, exts);
    elseif exist(p, 'dir') == 7
        [~, baseName] = fileparts(strip_sep(resolve_dir(p)));
        if isempty(baseName), baseName = 'input'; end
        files = scan_dir(p, baseName, files, exts, skipDirs, recursive);
    end
end
% 按相对路径排序并去重，保证每次处理顺序一致
if ~isempty(files)
    [~, uniqIdx] = unique({files.path}, 'stable');
    files = files(uniqIdx);
    [~, o] = sort(lower({files.relpath}));
    files = files(o);
end
end

function files = add_single_file(filePath, files, exts)
[fdir, stem, ext] = fileparts(filePath);
if ~any(strcmpi(ext, exts)), return; end
if isempty(fdir), fdir = pwd; end
fdirAbs = resolve_dir(fdir);
[~, dname] = fileparts(strip_sep(fdirAbs));
if isempty(dname), dname = 'input'; end
nm = [stem ext];
k = numel(files) + 1;
files(k).path = fullfile(fdirAbs, nm);
files(k).relpath = [dname '/' nm];
files(k).name = nm;
files(k).stem = stem;
files(k).ext = ext;
end

function files = scan_dir(dirPath, relPrefix, files, exts, skipDirs, recursive)
if exist(dirPath, 'dir') ~= 7, return; end
L = dir(dirPath);
for i = 1:numel(L)
    nm = L(i).name;
    if any(strcmp(nm, {'.', '..'})), continue; end
    full = fullfile(dirPath, nm);
    if L(i).isdir
        if recursive && ~any(strcmpi(nm, skipDirs))
            files = scan_dir(full, [relPrefix '/' nm], files, exts, skipDirs, recursive);
        end
        continue;
    end
    [~, stem, ext] = fileparts(nm);
    if ~any(strcmpi(ext, exts)), continue; end
    if is_excluded(stem), continue; end
    k = numel(files) + 1;
    files(k).path = full;
    files(k).relpath = [relPrefix '/' nm];
    files(k).name = nm;
    files(k).stem = stem;
    files(k).ext = ext;
end
end

function tf = is_excluded(stem)
s = lower(stem);
tf = ~isempty(regexp(stem, '^\{[0-9A-Fa-f-]+\}$', 'once')) || ...
     ~isempty(strfind(s, 'preview')) || ~isempty(strfind(s, '_overlay')) || ...
     ~isempty(strfind(s, '_mask')) || ~isempty(strfind(s, '_debug')) || ...
     ~isempty(strfind(s, '00_montage')) || ~isempty(strfind(s, 'thumb'));
end

function p = resolve_dir(p)
if strcmp(p, '.')
    p = pwd;
end
end

function p = strip_sep(p)
while numel(p) > 1 && (p(end) == '/' || p(end) == '\')
    p = p(1:end-1);
end
end
