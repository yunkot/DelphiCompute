@echo off
REM  This batch file invokes (re)compilation of ComputePrimes shader binary and assembly listings.
REM  Please ensure that Microsoft Shader Compiler "fxc.exe" is installed, with path to its executable
REM  defined in system's environment "PATH" variable. The compiler is part of Windows SDK.
del /Q ComputePrimes.cs.bin 2>NUL
del /Q ComputePrimes.cs.lst 2>NUL
fxc.exe /nologo /Ges /O3 /T cs_5_0 /E computePrimes /Fo ComputePrimes.cs.bin /Fc ComputePrimes.cs.lst ComputePrimes.cs
