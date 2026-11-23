function [r, detail] = fill_record(r, detail, res, imgSize, runtime, ovRel, mkRel)
%FILL_RECORD  用检测结果 res 填写结果记录（run_batch 与 crack_app 导出共用）。
%   imgSize = [高 宽]；runtime 为秒；ovRel / mkRel 为标注图、掩膜相对输出目录的路径。
r.status = res.status; r.status_code = res.statusCode;
r.n_cracks = res.nCracks;
r.review_reason = csv_clean(strjoin(res.reviewReasons, '；'));
r.notes = csv_clean(strjoin(res.notes, '；'));
r.overlay = ovRel; r.mask = mkRel;
r.height = imgSize(1); r.width = imgSize(2);
r.finger_angle_deg = res.diag.fingerAngleDeg;
r.pitch_px = res.diag.pitchFullPx;
r.valid_frac = res.diag.validFrac;
r.bright_frac = res.diag.brightFrac;
r.runtime_s = runtime;
r.error = '';
detail.status = res.status; detail.status_code = res.statusCode;
detail.image_size = [imgSize(2), imgSize(1)];
detail.n_cracks = res.nCracks;
detail.review_reasons = res.reviewReasons;
detail.notes = res.notes;
dg = res.diag;
detail.diagnostics = struct('finger_angle_deg', dg.fingerAngleDeg, 'grid_ok', dg.gridOk, ...
    'grid_periodicity', round(dg.periodicity * 1000) / 1000, 'pitch_px', round(dg.pitchFullPx * 100) / 100, ...
    'work_scale', round(dg.workScale * 10000) / 10000, 'valid_frac', round(dg.validFrac * 1000) / 1000, ...
    'bright_frac', round(dg.brightFrac * 1000) / 1000, 'n_candidates', dg.nCandidates, ...
    'runtime_s', round(runtime * 10) / 10);
detail.overlay = ovRel; detail.mask = mkRel;
detail.cracks = crack_list(res.cracks);
detail.error = '';
end
