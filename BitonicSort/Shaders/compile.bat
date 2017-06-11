@echo off
REM  This batch file invokes (re)compilation of ComputePrimes shader binary and assembly listings.
REM  Please ensure that Microsoft Shader Compiler "fxc.exe" is installed, with path to its executable
REM  defined in system's environment "PATH" variable. The compiler is part of Windows SDK.
del /Q BitonicSort.cs.bin 2>NUL
del /Q BitonicSort.cs.lst 2>NUL
del /Q MatrixTranspose.cs.bin 2>NUL
del /Q MatrixTranspose.cs.lst 2>NUL
fxc.exe /nologo /Ges /O3 /T cs_5_0 /E bitonicSort /Fo BitonicSort.cs.bin /Fc BitonicSort.cs.lst /D ComputeShaders.cs
fxc.exe /nologo /Ges /O3 /T cs_5_0 /E matrixTranspose /Fo MatrixTranspose.cs.bin /Fc MatrixTranspose.cs.lst ComputeShaders.cs