@echo off
REM Rust 模块编译脚本 (workspace: backup + downloader + file_ops + logger + http_client + db_client + vector_store + orchestrator)
REM 编译 Rust FFI 库并复制到 Flutter 应用目录

echo Compiling Rust workspace (backup + downloader + file_ops + logger + http_client + db_client + vector_store + orchestrator)...

cd rust

REM 编译 Release 版本 (workspace 一次编译所有成员)
cargo build --release

if %ERRORLEVEL% NEQ 0 (
    echo Rust compilation failed!
    exit /b 1
)

REM 复制 DLL 到 Flutter 应用目录
echo Copying DLLs to Flutter app...
copy /Y target\release\xmc_backup.dll ..\windows\runner\
copy /Y target\release\xmc_downloader.dll ..\windows\runner\
copy /Y target\release\xmc_file_ops.dll ..\windows\runner\
copy /Y target\release\xmc_logger.dll ..\windows\runner\
copy /Y target\release\xmc_http_client.dll ..\windows\runner\
copy /Y target\release\xmc_db_client.dll ..\windows\runner\
copy /Y target\release\xmc_vector_store.dll ..\windows\runner\
copy /Y target\release\xmc_orchestrator.dll ..\windows\runner\
copy /Y target\release\xmc_backup.dll ..\
copy /Y target\release\xmc_downloader.dll ..\
copy /Y target\release\xmc_file_ops.dll ..\
copy /Y target\release\xmc_logger.dll ..\
copy /Y target\release\xmc_http_client.dll ..\
copy /Y target\release\xmc_db_client.dll ..\
copy /Y target\release\xmc_vector_store.dll ..\
copy /Y target\release\xmc_orchestrator.dll ..\

echo Done! DLLs copied to windows\runner\
pause
