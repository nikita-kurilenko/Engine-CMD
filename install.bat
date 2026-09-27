@echo off
setlocal enabledelayedexpansion

REM  _____   ____  __ ___ ___ _____ ___  ___  _  _ 
REM / __\ \ / /  \/  | _ )_ _|_   _| _ \/ _ \| \| |
REM \__ \\ V /| |\/| | _ \| |  | | |   / (_) | .` |
REM |___/ |_| |_|  |_|___/___| |_| |_|_\\___/|_|\_|
REM Incremental Build Script                                           


REM ── Architecture selection (%1 = 32bit -> x86, default = x64) ──────────────
set "ARCH=64"
if /i "%~1"=="32bit" set "ARCH=32"
set "CONFIG_FILE=installer_config.txt"
set "HASH_FILE=object_hashes.txt"
set "BIN_DIR=bin!ARCH!"
set "EXE_DIR=exe!ARCH!"


REM ── Generate default config if missing ─────────────────────────────────────
if not exist "!CONFIG_FILE!" call :GenerateDefaultConfig


REM ── Parse config file (KEY=VALUE, # = comment) ────────────────────────────
for /f "usebackq eol=# tokens=1,* delims==" %%a in ("!CONFIG_FILE!") do (
    if not "%%a"=="" set "CFG_%%a=%%b"
)


REM ── Toolchain and Language ────────────────────────────────────────────────
set "TOOLCHAIN=msvc"
if defined CFG_COMPILER set "TOOLCHAIN=!CFG_COMPILER!"
set "LANG=c++"
if defined CFG_LANGUAGE set "LANG=!CFG_LANGUAGE!"


REM ── Build source file list from config ────────────────────────────────────
set "ALL_SOURCES="
if defined CFG_SOURCE_FILES set "ALL_SOURCES=!CFG_SOURCE_FILES!"
if defined CFG_SOURCE_FOLDERS (
    for %%d in (!CFG_SOURCE_FOLDERS!) do (
        for %%e in (cpp c) do (
            for /f "delims=" %%f in ('dir /b "%%d\*.%%e" 2^>nul') do (
                set "ALL_SOURCES=!ALL_SOURCES! %%d\%%f"
            )
        )
    )
)
if not defined ALL_SOURCES (
    echo [ERROR] No source files. Set SOURCE_FILES or SOURCE_FOLDERS in !CONFIG_FILE!
    exit /b 1
)


REM ── Quick check: skip build if everything is up to date ───────────────────
set "NEEDS_BUILD=0"
if not exist "!HASH_FILE!" set "NEEDS_BUILD=1"

set "LINK_TARGET=output.exe"
if defined CFG_RUN_TARGET set "LINK_TARGET=!CFG_RUN_TARGET!"

if !NEEDS_BUILD!==0 (
    if not exist "!EXE_DIR!\!LINK_TARGET!" set "NEEDS_BUILD=1"
)

if !NEEDS_BUILD!==0 (
    for %%f in (!ALL_SOURCES!) do (
        call :QuickHashCheck "%%f" || set "NEEDS_BUILD=1"
    )
)

if !NEEDS_BUILD!==0 (
    cls
    if defined CFG_RUN_TARGET (
        !EXE_DIR!\!CFG_RUN_TARGET!
    ) else (
        echo All files up to date.
    )
    exit /b 0
)


REM ── Initialize compiler toolchain ─────────────────────────────────────────
if /i "!TOOLCHAIN!"=="msvc" call :InitMSVC
if /i not "!TOOLCHAIN!"=="msvc" call :InitGCC
if errorlevel 1 exit /b 1

echo Starting incremental build...

if not exist "!BIN_DIR!" mkdir "!BIN_DIR!"
if not exist "!EXE_DIR!" mkdir "!EXE_DIR!"
if not exist "!HASH_FILE!" type nul > "!HASH_FILE!"

echo [CONFIG] compile: !COMPILE_DISPLAY!
echo [CONFIG] link:    !LINK_DISPLAY!


REM ── Compilation ───────────────────────────────────────────────────────────
for %%f in (!ALL_SOURCES!) do (
    call :CheckAndCompile "%%f" "!BIN_DIR!\%%~nf.obj"
)


REM ── Linking ───────────────────────────────────────────────────────────────
echo Linking...
set "ALL_OBJS="
for %%f in (!ALL_SOURCES!) do (
    set "ALL_OBJS=!ALL_OBJS! !BIN_DIR!\%%~nf.obj"
)
call :DoLink "!EXE_DIR!\!LINK_TARGET!"

echo Build complete!
goto :eof



REM ═══════════════════════════════════════════════════════════════════════════
REM  Compiler Setup
REM ═══════════════════════════════════════════════════════════════════════════

:InitMSVC
if "!ARCH!"=="32" (set "VCVARS_PATH=!CFG_VCVARS32!") else (set "VCVARS_PATH=!CFG_VCVARS64!")

if defined VCVARS_PATH if not exist "!VCVARS_PATH!" (
    echo Configured vcvars path is invalid, searching for a replacement...
    set "VCVARS_PATH="
)

if not defined VCVARS_PATH (
    set "VCVAR_NAME=vcvars!ARCH!"
    echo Searching for !VCVAR_NAME!.bat...
    for /f "delims=" %%f in ('dir /s /b "C:\Program Files\Microsoft Visual Studio\!VCVAR_NAME!.bat" 2^>nul') do (
        set "VCVARS_PATH=%%f"
    )
    if not defined VCVARS_PATH (
        echo [ERROR] Could not find !VCVAR_NAME!.bat. Install Visual Studio with C++ tools.
        exit /b 1
    )
    call :UpdateConfig "VCVARS!ARCH!" "!VCVARS_PATH!"
)

if not exist "!VCVARS_PATH!" (
    echo [ERROR] vcvars path invalid: !VCVARS_PATH!
    exit /b 1
)

echo Using: !VCVARS_PATH!
call "!VCVARS_PATH!"

REM Build compile flags
set "CL_FLAGS=/nologo /c"
if /i "!LANG!"=="c" (set "CL_FLAGS=!CL_FLAGS! /TC") else (set "CL_FLAGS=!CL_FLAGS! /TP")
for %%K in (MSVC_OPTIMIZATION MSVC_STANDARD MSVC_EXCEPTIONS MSVC_FLOATING_POINT MSVC_RUNTIME MSVC_WARNINGS MSVC_DEBUG MSVC_DEFINES MSVC_EXTRA) do (
    if defined CFG_%%K set "CL_FLAGS=!CL_FLAGS! !CFG_%%K!"
)

REM Build link flags
set "LINK_FLAGS=/NOLOGO"
if defined CFG_MSVC_SUBSYSTEM    set "LINK_FLAGS=!LINK_FLAGS! /SUBSYSTEM:!CFG_MSVC_SUBSYSTEM!"
if defined CFG_MSVC_ENTRY        set "LINK_FLAGS=!LINK_FLAGS! /ENTRY:!CFG_MSVC_ENTRY!"
if defined CFG_MSVC_EXTRA_LINK   set "LINK_FLAGS=!LINK_FLAGS! !CFG_MSVC_EXTRA_LINK!"
set "LINK_LIBS="
if defined CFG_MSVC_LIBS set "LINK_LIBS=!CFG_MSVC_LIBS!"

set "COMPILE_DISPLAY=cl !CL_FLAGS!"
set "LINK_DISPLAY=link !LINK_FLAGS! !LINK_LIBS!"
goto :eof


:InitGCC
set "CC=!CFG_COMPILER_PATH!"
if not defined CC (
    if /i "!TOOLCHAIN!"=="gcc" (
        if /i "!LANG!"=="c" (set "CC=gcc") else (set "CC=g++")
    )
    if /i "!TOOLCHAIN!"=="clang" (
        if /i "!LANG!"=="c" (set "CC=clang") else (set "CC=clang++")
    )
)
if not defined CC set "CC=!TOOLCHAIN!"

REM Verify compiler exists
where "!CC!" >nul 2>nul
if errorlevel 1 (
    if not exist "!CC!" (
        echo [ERROR] Compiler not found: !CC!
        echo         Set COMPILER_PATH in !CONFIG_FILE! or add it to PATH
        exit /b 1
    )
)

REM Build compile flags
set "CC_FLAGS="
for %%K in (GCC_OPTIMIZATION GCC_STANDARD GCC_WARNINGS GCC_DEBUG GCC_DEFINES GCC_EXTRA) do (
    if defined CFG_%%K set "CC_FLAGS=!CC_FLAGS! !CFG_%%K!"
)

REM Build link flags
set "LD_FLAGS="
if defined CFG_GCC_EXTRA_LINK set "LD_FLAGS=!CFG_GCC_EXTRA_LINK!"
set "LINK_LIBS="
if defined CFG_GCC_LIBS set "LINK_LIBS=!CFG_GCC_LIBS!"

set "COMPILE_DISPLAY=!CC! !CC_FLAGS!"
set "LINK_DISPLAY=!CC! !LD_FLAGS! !LINK_LIBS!"
goto :eof



REM ═══════════════════════════════════════════════════════════════════════════
REM  Build Operations
REM ═══════════════════════════════════════════════════════════════════════════

:DoCompile
if /i "!TOOLCHAIN!"=="msvc" (
    cl !CL_FLAGS! /showIncludes "%~1" /Fo"%~2" > "%~2.build.log" 2>&1
    set "BUILD_ERR=!errorlevel!"

    REM Extract include paths to .dep file
    type nul > "%~2.dep"
    for /f "usebackq delims=" %%L in ("%~2.build.log") do (
        set "LINE=%%L"
        set "LINE_CHECK=!LINE:Note: including file:=!"
        if not "!LINE_CHECK!"=="!LINE!" (
            set "INC_PATH=!LINE:*including file:=!"
            for /f "tokens=*" %%P in ("!INC_PATH!") do echo %%P>> "%~2.dep"
        )
    )

    REM Show non-include output (compiler messages, errors)
    findstr /V /B /C:"Note: including file:" "%~2.build.log"
    del "%~2.build.log" >nul 2>nul

    if !BUILD_ERR! neq 0 (
        del "%~2.dep" >nul 2>nul
        del "%~2" >nul 2>nul
    )
) else (
    "!CC!" -c !CC_FLAGS! -MMD -MF "%~2.dep.tmp" "%~1" -o "%~2"
    REM Convert Makefile dep format to simple one-path-per-line
    type nul > "%~2.dep"
    if exist "%~2.dep.tmp" (
        for /f "usebackq delims=" %%L in ("%~2.dep.tmp") do (
            set "DLINE=%%L"
            if "!DLINE:~-1!"=="\" set "DLINE=!DLINE:~0,-1!"
            for %%T in (!DLINE!) do (
                set "TK=%%T"
                if not "!TK:~-1!"==":" if exist "%%T" echo %%T>> "%~2.dep"
            )
        )
        del "%~2.dep.tmp" >nul 2>nul
    )
)
goto :eof


:DoLink
if /i "!TOOLCHAIN!"=="msvc" (
    link !LINK_FLAGS! /OUT:"%~1" !ALL_OBJS! !LINK_LIBS!
) else (
    "!CC!" -o "%~1" !ALL_OBJS! !LD_FLAGS! !LINK_LIBS!
)
goto :eof


:ComputeFullHash
REM %1 = source file, %2 = object file
REM Sets FULL_HASH on return (source MD5 + dependency metadata MD5)
set "CFH_SRC=%~1"
set "CFH_DEP=%~2.dep"

set "CFH_SRC_HASH="
for /f "skip=1 delims=" %%i in ('certutil -hashfile "!CFH_SRC!" MD5 2^>nul') do (
    if not defined CFH_SRC_HASH set "CFH_SRC_HASH=%%i"
)
set "CFH_SRC_HASH=!CFH_SRC_HASH: =!"

set "CFH_DEP_HASH=NODEPS"
if exist "!CFH_DEP!" (
    type nul > "_dep_meta.tmp"
    for /f "usebackq delims=" %%h in ("!CFH_DEP!") do (
        if exist "%%h" (
            for %%A in ("%%h") do echo %%~zA %%~tA>> "_dep_meta.tmp"
        )
    )
    set "CFH_DEP_HASH="
    for /f "skip=1 delims=" %%i in ('certutil -hashfile "_dep_meta.tmp" MD5 2^>nul') do (
        if not defined CFH_DEP_HASH set "CFH_DEP_HASH=%%i"
    )
    set "CFH_DEP_HASH=!CFH_DEP_HASH: =!"
    del "_dep_meta.tmp" >nul 2>nul
)

set "FULL_HASH=!CFH_SRC_HASH!_!CFH_DEP_HASH!"
goto :eof


:CheckAndCompile
set "SOURCE_FILE=%~1"
set "OBJECT_FILE=%~2"
set "DEP_FILE=%~2.dep"

if not exist "!OBJECT_FILE!" (
    echo [COMPILE] !SOURCE_FILE! ^(object missing^)
    call :DoCompile "!SOURCE_FILE!" "!OBJECT_FILE!"
    call :ComputeFullHash "!SOURCE_FILE!" "!OBJECT_FILE!"
    goto :update_hash
)

if not exist "!DEP_FILE!" (
    echo [COMPILE] !SOURCE_FILE! ^(deps missing^)
    call :DoCompile "!SOURCE_FILE!" "!OBJECT_FILE!"
    call :ComputeFullHash "!SOURCE_FILE!" "!OBJECT_FILE!"
    goto :update_hash
)

call :ComputeFullHash "!SOURCE_FILE!" "!OBJECT_FILE!"

set "STORED_HASH="
for /f "tokens=2" %%a in ('findstr /C:"!TOOLCHAIN!:!ARCH!:!SOURCE_FILE!" "!HASH_FILE!" 2^>nul') do set "STORED_HASH=%%a"

if "!FULL_HASH!"=="!STORED_HASH!" (
    echo [  OK  ] !SOURCE_FILE! is up to date
    goto :eof
)

echo [COMPILE] !SOURCE_FILE! ^(changed^)
call :DoCompile "!SOURCE_FILE!" "!OBJECT_FILE!"
call :ComputeFullHash "!SOURCE_FILE!" "!OBJECT_FILE!"

:update_hash
findstr /V /C:"!TOOLCHAIN!:!ARCH!:!SOURCE_FILE!" "!HASH_FILE!" > "temp_hashes.txt" 2>nul
>> "temp_hashes.txt" echo !TOOLCHAIN!:!ARCH!:!SOURCE_FILE! !FULL_HASH!
move /Y "temp_hashes.txt" "!HASH_FILE!" > nul
goto :eof



REM ═══════════════════════════════════════════════════════════════════════════
REM  Hash Check / Config Update
REM ═══════════════════════════════════════════════════════════════════════════

:QuickHashCheck
set "QHC_SOURCE=%~1"
set "QHC_OBJ=!BIN_DIR!\%~n1.obj"

call :ComputeFullHash "!QHC_SOURCE!" "!QHC_OBJ!"

set "QHC_STORED="
for /f "tokens=2" %%a in ('findstr /C:"!TOOLCHAIN!:!ARCH!:!QHC_SOURCE!" "!HASH_FILE!" 2^>nul') do set "QHC_STORED=%%a"

if "!FULL_HASH!"=="!QHC_STORED!" exit /b 0
exit /b 1


:UpdateConfig
set "UC_KEY=%~1"
set "UC_VAL=%~2"
findstr /V /B /C:"!UC_KEY!=" "!CONFIG_FILE!" > "temp_config.txt" 2>nul
>> "temp_config.txt" echo !UC_KEY!=!UC_VAL!
move /Y "temp_config.txt" "!CONFIG_FILE!" > nul
goto :eof



REM ═══════════════════════════════════════════════════════════════════════════
REM  Default Config Generator
REM ═══════════════════════════════════════════════════════════════════════════

:GenerateDefaultConfig
echo Generating default build config...
set "CF=!CONFIG_FILE!"

set "DET32="
set "DET64="
for /f "delims=" %%f in ('dir /s /b "C:\Program Files\Microsoft Visual Studio\vcvars32.bat" 2^>nul') do (
    if not defined DET32 set "DET32=%%f"
)
for /f "delims=" %%f in ('dir /s /b "C:\Program Files\Microsoft Visual Studio\vcvars64.bat" 2^>nul') do (
    if not defined DET64 set "DET64=%%f"
)

 > "!CF!" echo # ============================================================
>> "!CF!" echo # Build Configuration
>> "!CF!" echo # ============================================================
>> "!CF!" echo # Lines starting with # are comments. Do not add spaces around =
>> "!CF!" echo # Usage: install.bat         (64-bit)
>> "!CF!" echo #        install.bat 32bit   (32-bit)
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Compiler Toolchain ----------------------------------------
>> "!CF!" echo #  msvc   = Microsoft Visual C++ (auto uses vcvars)
>> "!CF!" echo #  gcc    = GCC / MinGW
>> "!CF!" echo #  clang  = Clang / LLVM
>> "!CF!" echo COMPILER=msvc
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Language --------------------------------------------------
>> "!CF!" echo #  c    = compile as C    (MSVC: /TC, GCC: gcc, Clang: clang)
>> "!CF!" echo #  c++  = compile as C++  (MSVC: /TP, GCC: g++, Clang: clang++)
>> "!CF!" echo LANGUAGE=c++
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Compiler Path (gcc/clang only) ----------------------------
>> "!CF!" echo #  Full path to compiler executable. Ignored when COMPILER=msvc.
>> "!CF!" echo #  Leave empty to auto-detect from PATH.
>> "!CF!" echo #  Example: C:\msys64\mingw64\bin\g++.exe
>> "!CF!" echo COMPILER_PATH=
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- MSVC Paths (auto-detected, used when COMPILER=msvc) -------
>> "!CF!" echo VCVARS32=C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars32.bat
>> "!CF!" echo VCVARS64=C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Source Files -----------------------------------------------
>> "!CF!" echo #  Specific .cpp/.c files to compile (space-separated)
>> "!CF!" echo #  Example: TRAINING\poly.cpp CHAPTER_1\cpC.cpp
>> "!CF!" echo SOURCE_FILES=
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Source Folders ---------------------------------------------
>> "!CF!" echo #  Auto-compile ALL .cpp/.c files found in these folders
>> "!CF!" echo #  (space-separated folder names, non-recursive)
>> "!CF!" echo SOURCE_FOLDERS=core core\console core\input core\clock core\sound core\render core\render\tinyrenderer-master core\ui
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Run Target -------------------------------------------------
>> "!CF!" echo #  Exe to auto-run when everything is up to date (from exe folder)
>> "!CF!" echo #  Leave empty to just print "up to date"
>> "!CF!" echo RUN_TARGET=main.exe
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # ============================================================
>> "!CF!" echo #  MSVC FLAGS  (used when COMPILER=msvc)
>> "!CF!" echo # ============================================================
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Optimization -----------------------------------------------
>> "!CF!" echo #  /O1  = minimize size          /O2  = maximize speed
>> "!CF!" echo #  /Od  = disable (debug)         /Ox  = full optimization
>> "!CF!" echo #  /Ob2 = inline expansion        /Oi  = enable intrinsics
>> "!CF!" echo MSVC_OPTIMIZATION=/O2
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Language Standard ------------------------------------------
>> "!CF!" echo #  C:   /std:c11   /std:c17
>> "!CF!" echo #  C++: /std:c++14  /std:c++17  /std:c++20  /std:c++latest
>> "!CF!" echo MSVC_STANDARD=/std:c++17
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Exception Handling -----------------------------------------
>> "!CF!" echo #  /EHsc = C++ only   /EHa = C++ + SEH   (empty = none)
>> "!CF!" echo MSVC_EXCEPTIONS=/EHsc
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Floating Point ---------------------------------------------
>> "!CF!" echo #  /fp:fast  /fp:precise  /fp:strict
>> "!CF!" echo MSVC_FLOATING_POINT=/fp:fast
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Runtime Library --------------------------------------------
>> "!CF!" echo #  /MD  = DLL release    /MDd = DLL debug
>> "!CF!" echo #  /MT  = static release /MTd = static debug
>> "!CF!" echo MSVC_RUNTIME=/MT
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Warning Level ----------------------------------------------
>> "!CF!" echo #  /W0=off  /W1  /W2  /W3  /W4=max  /Wall=all  /WX=errors
>> "!CF!" echo MSVC_WARNINGS=/W3
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Debug Info -------------------------------------------------
>> "!CF!" echo #  /Zi = PDB debug   /Z7 = embedded   (empty = none)
>> "!CF!" echo MSVC_DEBUG=
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Preprocessor Defines ---------------------------------------
>> "!CF!" echo #  Space-separated: /DTESTING /DBEST /DNDEBUG /DUNICODE
>> "!CF!" echo MSVC_DEFINES=/DTESTING /DBEST
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Extra Compiler Flags ---------------------------------------
>> "!CF!" echo #  Any additional cl.exe flags
>> "!CF!" echo #  /GS-         = disable buffer security check
>> "!CF!" echo #  /Gs          = control stack probes
>> "!CF!" echo #  /Gy          = function-level linking
>> "!CF!" echo #  /GL          = whole program optimization
>> "!CF!" echo #  /favor:AMD64 = optimize for AMD64
>> "!CF!" echo #  /arch:SSE2   = SSE2 instructions (32-bit)
>> "!CF!" echo #  /arch:AVX2   = AVX2 instructions
>> "!CF!" echo MSVC_EXTRA=/wd4244
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Subsystem --------------------------------------------------
>> "!CF!" echo #  CONSOLE  WINDOWS  (empty = linker default)
>> "!CF!" echo MSVC_SUBSYSTEM=CONSOLE
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Entry Point ------------------------------------------------
>> "!CF!" echo #  Custom entry (skips CRT startup). Leave empty for default.
>> "!CF!" echo #  Examples: main  wmain  WinMain  wWinMain
>> "!CF!" echo #  WARNING: custom entry skips CRT init (no printf, new, etc.)
>> "!CF!" echo MSVC_ENTRY=
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Linker Libraries -------------------------------------------
>> "!CF!" echo #  Space-separated .lib files to link
>> "!CF!" echo #  kernel32.lib  user32.lib  gdi32.lib   shell32.lib
>> "!CF!" echo #  advapi32.lib  ole32.lib   ws2_32.lib  ntdll.lib
>> "!CF!" echo MSVC_LIBS=user32.lib
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Extra Linker Flags -----------------------------------------
>> "!CF!" echo #  /DEBUG           = generate debug info
>> "!CF!" echo #  /LTCG            = link-time code generation
>> "!CF!" echo #  /OPT:REF         = remove unreferenced functions
>> "!CF!" echo #  /OPT:ICF         = fold identical COMDATs
>> "!CF!" echo #  /MANIFEST:NO     = no manifest file
>> "!CF!" echo #  /DYNAMICBASE:NO  = disable ASLR
>> "!CF!" echo #  /NXCOMPAT:NO     = disable DEP
>> "!CF!" echo MSVC_EXTRA_LINK=
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # ============================================================
>> "!CF!" echo #  GCC / CLANG FLAGS  (used when COMPILER=gcc or clang)
>> "!CF!" echo # ============================================================
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Optimization -----------------------------------------------
>> "!CF!" echo #  -O0=none  -O1=some  -O2=default  -O3=aggressive
>> "!CF!" echo #  -Os=size  -Ofast=fast  -Og=debug-friendly
>> "!CF!" echo GCC_OPTIMIZATION=-O2
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Language Standard ------------------------------------------
>> "!CF!" echo #  C:   -std=c11  -std=c17  -std=c23  -std=gnu17
>> "!CF!" echo #  C++: -std=c++14  -std=c++17  -std=c++20  -std=c++23  -std=gnu++17
>> "!CF!" echo GCC_STANDARD=-std=c++17
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Warnings ---------------------------------------------------
>> "!CF!" echo #  -Wall         = common warnings
>> "!CF!" echo #  -Wextra       = extra warnings
>> "!CF!" echo #  -Wpedantic    = strict ISO compliance
>> "!CF!" echo #  -Werror       = treat warnings as errors
>> "!CF!" echo GCC_WARNINGS=-Wall -Wextra
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Debug Info -------------------------------------------------
>> "!CF!" echo #  -g   = debug symbols   -g0 = none   -g3 = max debug
>> "!CF!" echo GCC_DEBUG=
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Preprocessor Defines ---------------------------------------
>> "!CF!" echo #  Space-separated: -DTESTING -DBEST -DNDEBUG
>> "!CF!" echo GCC_DEFINES=-DTESTING -DBEST
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Extra Compiler Flags ---------------------------------------
>> "!CF!" echo #  -fno-exceptions      = disable C++ exceptions
>> "!CF!" echo #  -fno-rtti            = disable RTTI
>> "!CF!" echo #  -nostartfiles        = skip CRT startup (minimal binary)
>> "!CF!" echo #  -fstack-protector    = stack canary
>> "!CF!" echo #  -march=native        = optimize for current CPU
>> "!CF!" echo #  -masm=intel          = use Intel asm syntax
>> "!CF!" echo GCC_EXTRA=
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Linker Libraries -------------------------------------------
>> "!CF!" echo #  Space-separated: -lkernel32  -luser32  -lgdi32  -lws2_32
>> "!CF!" echo GCC_LIBS=-lkernel32
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo.
>> "!CF!" echo # -- Extra Linker Flags -----------------------------------------
>> "!CF!" echo #  -s                   = strip symbols (smaller binary)
>> "!CF!" echo #  -static              = static linking
>> "!CF!" echo #  -mconsole            = console subsystem
>> "!CF!" echo #  -mwindows            = windows subsystem (no console)
>> "!CF!" echo #  -Wl,--entry,main     = custom entry point
>> "!CF!" echo #  -nostdlib            = no standard library
>> "!CF!" echo GCC_EXTRA_LINK=

echo Default config generated: !CF!
goto :eof
