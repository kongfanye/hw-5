function write_defects_json(path, method, info, details)
%WRITE_DEFECTS_JSON  写 defects.json：方法、坐标约定、运行环境与逐图结果（details 为元胞数组）。
J = struct();
J.method = method;
J.coordinate_system = ['原图像素坐标：左上角像素中心为 (1,1)，x 为列向右，y 为行向下；' ...
    'bbox = [x_min, y_min, x_max, y_max]（含两端）；points 为中心线采样点 [x, y]'];
J.generated = info.time;
J.environment = [info.platform '; ' info.imageToolbox];
J.config_file = 'run_config.json';
J.images = details;
write_json(path, J);
end
