function T = read_csv_simple(path)
%READ_CSV_SIMPLE  读取无引号转义的 UTF-8 CSV，返回结构数组（字段名取表头）。
txt = read_text_utf8(path);
lines = regexp(txt, '\r?\n', 'split');
lines = lines(~cellfun(@isempty, strtrim(lines)));
hdr = regexp(lines{1}, ',', 'split');   % 不合并连续逗号，保留空字段
T = struct([]);
for i = 2:numel(lines)
    c = regexp(lines{i}, ',', 'split');
    c(end + 1:numel(hdr)) = {''};
    for j = 1:numel(hdr)
        T(i - 1).(hdr{j}) = c{j};
    end
end
end
