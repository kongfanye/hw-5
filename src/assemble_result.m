function res = assemble_result(method, statusCode, cracks, out, prep, reasons)
%ASSEMBLE_RESULT  组装单图检测结果（基线与改进法共用）。
names = struct('crack', '有隐裂', 'no_crack', '无隐裂', 'review', '待复核');
res.method = method;
res.statusCode = statusCode;
res.status = names.(statusCode);
res.nCracks = numel(cracks);
res.cracks = cracks;
res.mask = out.mask;
res.centerline = out.Lfull > 0;
res.reviewReasons = reasons;
res.notes = prep.notes;
res.diag.imageSize = prep.fullSize;
res.diag.fingerAngleDeg = prep.grid.theta;
res.diag.gridOk = prep.grid.ok;
res.diag.periodicity = prep.grid.periodicity;
res.diag.pitchFullPx = prep.grid.pitchFull;
res.diag.workScale = prep.scale;
res.diag.pitchWorkPx = prep.pitch;
res.diag.validFrac = prep.validFrac;
res.diag.brightFrac = prep.brightFrac;
end
