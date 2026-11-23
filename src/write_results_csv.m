function write_results_csv(path, recs)
%WRITE_RESULTS_CSV  写 results.csv（UTF-8 带 BOM）；recs 为含 .rec 字段的结构数组。
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
