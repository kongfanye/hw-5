function files = list_images(inputDirs, recursive)
%LIST_IMAGES  扫描输入目录中的图像（扩展名大小写不敏感）。
%   排除：题目截图 {GUID}.png、预览图、程序输出（overlay/mask/debug/outputs 目录等）。
%   返回结构数组：path（绝对路径）、relpath（"目录名/文件名"）、name、stem、ext。
if nargin < 2, recursive = false; end
if ischar(inputDirs), inputDirs = {inputDirs}; end
exts = {'.jpg', '.jpeg', '.png', '.bmp', '.tif', '.tiff'};
skipDirs = {'outputs', 'output', 'overlays', 'masks', 'debug', 'baseline', '.git'};
files = struct('path', {}, 'relpath', {}, 'name', {}, 'stem', {}, 'ext', {});
for d = 1:numel(inputDirs)
    files = scan_dir(inputDirs{d}, files, exts, skipDirs, recursive);
end
% 按相对路径排序，保证每次处理顺序一致
if ~isempty(files)
    [~, o] = sort(lower({files.relpath}));
    files = files(o);
end
end

function files = scan_dir(dirPath, files, exts, skipDirs, recursive)
if exist(dirPath, 'dir') ~= 7, return; end
L = dir(dirPath);
[~, dname] = fileparts(strip_sep(dirPath));
for i = 1:numel(L)
    nm = L(i).name;
    if any(strcmp(nm, {'.', '..'})), continue; end
    full = fullfile(dirPath, nm);
    if L(i).isdir
        if recursive && ~any(strcmpi(nm, skipDirs))
            files = scan_dir(full, files, exts, skipDirs, recursive);
        end
        continue;
    end
    [~, stem, ext] = fileparts(nm);
    if ~any(strcmpi(ext, exts)), continue; end
    if is_excluded(stem), continue; end
    k = numel(files) + 1;
    files(k).path = full;
    files(k).relpath = [dname '/' nm];
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
     ~isempty(strfind(s, 'thumb'));
end

function p = strip_sep(p)
while numel(p) > 1 && (p(end) == '/' || p(end) == '\')
    p = p(1:end-1);
end
end
