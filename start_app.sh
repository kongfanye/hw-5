#!/usr/bin/env bash
# 启动光伏电池片隐裂检测小程序（macOS / Linux）：bash start_app.sh
# 优先使用 MATLAB；找不到时使用 GNU Octave。
cd "$(dirname "$0")" || exit 1
HERE="$(pwd)"
HERE_Q="${HERE//\'/\'\'}"        # MATLAB 字符串中的单引号需写成两个

M="$(command -v matlab 2>/dev/null)"
if [ -z "$M" ]; then
    for c in /Applications/MATLAB_R20*.app/bin/matlab /usr/local/MATLAB/R20*/bin/matlab /opt/MATLAB/R20*/bin/matlab; do
        [ -x "$c" ] && M="$c"
    done
fi
if [ -n "$M" ]; then
    echo "使用 MATLAB 启动：$M（窗口出现可能需要 20–60 秒）"
    exec "$M" -nosplash -r "cd('$HERE_Q'); crack_app"
fi

O="$(command -v octave 2>/dev/null)"
if [ -z "$O" ]; then
    for c in /Applications/Octave-*.app/Contents/Resources/usr/bin/octave /opt/homebrew/bin/octave /usr/local/bin/octave; do
        [ -x "$c" ] && O="$c"
    done
fi
if [ -n "$O" ]; then
    echo "使用 GNU Octave 启动：$O"
    exec "$O" --no-gui --persist --eval "cd('$HERE_Q'); crack_app"
fi

echo "没有找到 MATLAB 或 GNU Octave。"
echo "  MATLAB：打开 MATLAB，把“当前文件夹”切换到 $HERE，然后输入 crack_app"
echo "  Octave：从 https://octave.org/download 安装后再运行本脚本"
exit 1
