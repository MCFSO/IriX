@echo off
REM Rust 备份模块编译脚本
REM 编译 Rust FFI 库并复制到 Flutter 应用目录

echo Compiling Rust backup module...

cd rust

REM 编译 Release 版本
cargo build --release

if %ERRORLEVEL% NEQ 0 (
    echo Rust compilation failed!
    exit /b 1
)

REM 复制 DLL 到 Flutter 应用目录
echo Copying DLL to Flutter app...
copy /Y target\release\xmc_backup.dll ..\windows\runner\

echo Done! DLL copied to windows\runner\
pause