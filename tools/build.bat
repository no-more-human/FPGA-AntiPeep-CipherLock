@echo off
chcp 65001 > nul
echo ============================================================
echo   一键执行安路 FPGA 全流程综合与布局布线 (Synthesis + P&R)
echo ============================================================
echo.

echo [1/3] 正在清理历史临时标记...
del /q /f lock_Runs\syn_1\.*.f lock_Runs\phy_1\.*.f 2>nul

echo [2/3] 正在执行 RTL 综合与门级网表优化 (syn_1)...
cd lock_Runs\syn_1
"D:\TD\bin\td_commands_prompt.exe" test_syn.tcl
if %ERRORLEVEL% neq 0 (
    echo [错误] 综合失败！请检查错误日志 lock_Runs\syn_1\run.log。
    cd ..\..
    pause
    exit /b 1
)
cd ..\..

echo [3/3] 正在执行物理布局布线与比特流生成 (phy_1)...
cd lock_Runs\phy_1
"D:\TD\bin\td_commands_prompt.exe" test_phy.tcl
if %ERRORLEVEL% neq 0 (
    echo [错误] 布局布线失败！请检查错误日志 lock_Runs\phy_1\run.log。
    cd ..\..
    pause
    exit /b 1
)
cd ..\..

copy /y lock_Runs\phy_1\lock.bit lock_Runs\best_result\lock.bit >nul

echo.
echo ============================================================
echo [成功] 全流程编译完成！生成比特流：lock_Runs\phy_1\lock.bit
echo ============================================================
echo.
pause
