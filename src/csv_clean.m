function s = csv_clean(s)
%CSV_CLEAN  CSV 字段内不出现英文逗号与换行。
s = strrep(strrep(strrep(s, ',', '；'), sprintf('\n'), ' '), sprintf('\r'), ' ');
end
