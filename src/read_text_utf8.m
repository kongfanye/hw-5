function txt = read_text_utf8(path)
%READ_TEXT_UTF8  以 UTF-8 读取文本文件（去掉 BOM），MATLAB/Octave 通用。
fid = fopen(path, 'r');
if fid < 0, error('无法打开 %s', path); end
b = fread(fid, Inf, '*uint8')';
fclose(fid);
if numel(b) >= 3 && all(b(1:3) == [239 187 191])
    b = b(4:end);
end
txt = native2unicode(b, 'UTF-8');
end
