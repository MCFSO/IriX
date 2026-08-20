@echo off
rem Build xmc_simd.dll + bench.exe with MSVC (x64).
rem Requires: Visual Studio installed; vcvars64.bat path below may need editing.

setlocal
cd /d "%~dp0"
rem 若 cl 已在 PATH（如 CI 的 msvc-dev-cmd 环境）则跳过 vcvars
where cl >nul 2>&1
if %ERRORLEVEL% EQU 0 goto compile
set VCVARS=D:\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat
if exist "%VCVARS%" goto have_vcvars
set VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat
if exist "%VCVARS%" goto have_vcvars
echo vcvars64.bat not found. Edit VCVARS in build.bat.
exit /b 1
:have_vcvars
call "%VCVARS%" >nul 2>&1
cd /d "%~dp0"
:compile

set SRC=src
set OUT=build
if not exist %OUT% mkdir %OUT%

echo === compiling variants ===
cl /nologo /O2 /GL /utf-8 /c %SRC%\cpuid.c        /Fo%OUT%\cpuid.obj        || goto :err
cl /nologo /O2 /GL /utf-8 /c %SRC%\base64_scalar.c /Fo%OUT%\base64_scalar.obj || goto :err
cl /nologo /O2 /GL /utf-8 /c %SRC%\base64_sse2.c   /Fo%OUT%\base64_sse2.obj   || goto :err
cl /nologo /O2 /GL /utf-8 /arch:AVX2 /c %SRC%\base64_avx2.c /Fo%OUT%\base64_avx2.obj || goto :err
cl /nologo /O2 /GL /utf-8 /c %SRC%\base64_decode_scalar.c /Fo%OUT%\base64_decode_scalar.obj || goto :err
cl /nologo /O2 /GL /utf-8 /c %SRC%\base64_decode_ssse3.c   /Fo%OUT%\base64_decode_ssse3.obj   || goto :err
cl /nologo /O2 /GL /utf-8 /arch:AVX2 /c %SRC%\base64_decode_avx2.c /Fo%OUT%\base64_decode_avx2.obj || goto :err
cl /nologo /O2 /GL /utf-8 /c %SRC%\crc32.c         /Fo%OUT%\crc32.obj         || goto :err
cl /nologo /O2 /GL /utf-8 /c %SRC%\crc32c.c        /Fo%OUT%\crc32c.obj        || goto :err
cl /nologo /O2 /GL /utf-8 /c %SRC%\simd_dll.c      /Fo%OUT%\simd_dll.obj      || goto :err

echo === linking xmc_simd.dll ===
link /nologo /DLL /OUT:%OUT%\xmc_simd.dll ^
    %OUT%\cpuid.obj %OUT%\base64_scalar.obj %OUT%\base64_sse2.obj %OUT%\base64_avx2.obj ^
    %OUT%\base64_decode_scalar.obj %OUT%\base64_decode_ssse3.obj %OUT%\base64_decode_avx2.obj ^
    %OUT%\crc32.obj %OUT%\crc32c.obj %OUT%\simd_dll.obj || goto :err

echo === building bench.exe ===
cl /nologo /O2 /GL /utf-8 /c %SRC%\bench.c /Fo%OUT%\bench.obj || goto :err
link /nologo /OUT:%OUT%\bench.exe ^
    %OUT%\cpuid.obj %OUT%\base64_scalar.obj %OUT%\base64_sse2.obj %OUT%\base64_avx2.obj ^
    %OUT%\base64_decode_scalar.obj %OUT%\base64_decode_ssse3.obj %OUT%\base64_decode_avx2.obj ^
    %OUT%\crc32.obj %OUT%\crc32c.obj %OUT%\simd_dll.obj %OUT%\bench.obj || goto :err

echo.
echo OK: %OUT%\xmc_simd.dll  %OUT%\bench.exe
exit /b 0

:err
echo BUILD FAILED
exit /b 1
