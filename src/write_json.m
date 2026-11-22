function write_json(path, data)
%WRITE_JSON  把结构/元胞/数值/字符串写成带缩进的 UTF-8 JSON（MATLAB/Octave 通用实现）。
%   数值矩阵按行写成嵌套数组；空数组写成 []；逻辑值写成 true/false。
txt = enc(data, 0);
fid = fopen(path, 'w');
if fid < 0, error('无法写入 %s', path); end
fwrite(fid, unicode2native(txt, 'UTF-8'));
fclose(fid);
end

function s = enc(x, lv)
ind = repmat(' ', 1, 2 * (lv + 1));
ind0 = repmat(' ', 1, 2 * lv);
if ischar(x)
    s = ['"' esc(x) '"'];
elseif isstruct(x)
    if numel(x) ~= 1
        parts = cell(1, numel(x));
        for i = 1:numel(x), parts{i} = [ind enc(x(i), lv + 1)]; end
        if isempty(parts), s = '[]'; else, s = sprintf('[\n%s\n%s]', strjoin(parts, sprintf(',\n')), ind0); end
        return;
    end
    f = fieldnames(x);
    if isempty(f), s = '{}'; return; end
    parts = cell(1, numel(f));
    for i = 1:numel(f)
        parts{i} = sprintf('%s"%s": %s', ind, f{i}, enc(x.(f{i}), lv + 1));
    end
    s = sprintf('{\n%s\n%s}', strjoin(parts, sprintf(',\n')), ind0);
elseif iscell(x)
    if isempty(x), s = '[]'; return; end
    parts = cell(1, numel(x));
    for i = 1:numel(x), parts{i} = [ind enc(x{i}, lv + 1)]; end
    s = sprintf('[\n%s\n%s]', strjoin(parts, sprintf(',\n')), ind0);
elseif islogical(x) && isscalar(x)
    if x, s = 'true'; else, s = 'false'; end
elseif isnumeric(x) || islogical(x)
    x = double(x);
    if isempty(x)
        s = '[]';
    elseif isscalar(x)
        s = num(x);
    elseif isvector(x) && (size(x, 1) == 1 || size(x, 2) == 1)
        s = ['[' strjoin(arrayfun(@num, x(:)', 'UniformOutput', false), ', ') ']'];
    else
        rows = cell(1, size(x, 1));
        for r = 1:size(x, 1)
            rows{r} = ['[' strjoin(arrayfun(@num, x(r, :), 'UniformOutput', false), ', ') ']'];
        end
        s = ['[' strjoin(rows, ', ') ']'];
    end
else
    s = 'null';
end
end

function s = num(v)
if isnan(v) || isinf(v)
    s = 'null';
elseif v == round(v) && abs(v) < 1e15
    s = sprintf('%d', v);
else
    s = sprintf('%.4g', v);
end
end

function s = esc(t)
s = strrep(t, '\', '\\');
s = strrep(s, '"', '\"');
s = strrep(s, sprintf('\n'), '\n');
s = strrep(s, sprintf('\r'), '\r');
s = strrep(s, sprintf('\t'), '\t');
end
