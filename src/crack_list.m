function C = crack_list(cr)
%CRACK_LIST  把裂纹结构数组整理成写入 defects.json 的元胞数组（坐标为原图像素）。
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
