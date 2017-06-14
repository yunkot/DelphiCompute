(*
 * Copyright (c) 2017 Yuriy Kotsarenko. All rights reserved.
 * This software is subject to The MIT License.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
 * associated documentation files (the "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
 * following conditions:
 *
 *   The above copyright notice and this permission notice shall be included in all copies or substantial
 *   portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
 * LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *)
unit Resources;

interface

{$SCOPEDENUMS ON}

uses
  Winapi.D3D11, System.SysUtils;

type
  // Type of Direct3D context.
  TContextType = (
    // Hardware-accelerated context.
    Hardware,

    // Software rasterization using WARP device.
    Software,

    // Reference implementation (very slow).
    Reference);

  // Context-related exception.
  ContextException = class(Exception);

  // Context that has interfaces to important Direct3D interfaces.
  TContext = record
  private
    FDevice: ID3D11Device;
    FImmediateContext: ID3D11DeviceContext;

    class function TryCreate(out Context: TContext; const ContextType: TContextType;
      const DebugMode: Boolean): HResult; static;
  public
    // Creates Direct3D device and its immediate context for the specified context type and debug mode.
    class function Create(const ContextType: TContextType;
      const DebugMode: Boolean = False): TContext; overload; static;

    { In an automatic fashion, attempts to create hardware-accelerated context and if that fails, a WARP device, and
      finally, a reference device, if any other option fails. Debug mode is enabled when compiled for Debug target.
      When "TryWARPFirst" is set to True, the function tries creating WARP device before hardware-accelerated context. }
    class function Create(const TryWARPFirst: Boolean = False): TContext; overload; static;

    // Releases contained interfaces.
    procedure Free;

    // Creates Compute shader from external file.
    function CreateShaderFromFile(const FileName: string): ID3D11ComputeShader;

    // Reference to Direct3D 11 device.
    property Device: ID3D11Device read FDevice;

    // Reference to Direct3D 11 immediate context.
    property ImmediateContext: ID3D11DeviceContext read FImmediateContext;
  end;

// Calculates number of milliseconds that passed since application startup.
function GetStartTickCount: Cardinal;

implementation

uses
  Winapi.Windows, Winapi.D3DCommon, Winapi.D3D11_1, System.Classes;

var
  PerfFrequency: Int64 = 0;
  PerfCounterStart: Int64 = 0;

function GetStartTickCount: Cardinal;
var
  Counter: Int64;
begin
  if PerfFrequency = 0 then
  begin
    QueryPerformanceFrequency(PerfFrequency);
    QueryPerformanceCounter(PerfCounterStart);
  end;

  QueryPerformanceCounter(Counter);
  Result := ((Counter - PerfCounterStart) * 1000) div PerfFrequency;
end;

class function TContext.TryCreate(out Context: TContext; const ContextType: TContextType;
  const DebugMode: Boolean): HResult;
const
  FeatureLevels: array[0..1] of D3D_FEATURE_LEVEL = (D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0);
  DriverTypes: array[TContextType] of D3D_DRIVER_TYPE = (D3D_DRIVER_TYPE_HARDWARE, D3D_DRIVER_TYPE_WARP,
    D3D_DRIVER_TYPE_REFERENCE);
var
  DeviceCreationFlags: Cardinal;
begin
  DeviceCreationFlags := 0;
  if DebugMode then
    DeviceCreationFlags := DeviceCreationFlags or Cardinal(D3D11_CREATE_DEVICE_DEBUG);

  Result := D3D11CreateDevice(nil, DriverTypes[ContextType], 0, DeviceCreationFlags, @FeatureLevels[0], 2,
    D3D11_SDK_VERSION, Context.FDevice, PCardinal(nil)^, Context.FImmediateContext);
end;

class function TContext.Create(const ContextType: TContextType; const DebugMode: Boolean): TContext;
var
  Res: HResult;
begin
  Res := TryCreate(Result, ContextType, DebugMode);
  if Failed(Res) then
    raise ContextException.Create(SysErrorMessage(Res));
end;

class function TContext.Create(const TryWARPFirst: Boolean): TContext;
const
  DebugMode: Boolean = {$IFDEF DEBUG} True {$ELSE} False {$ENDIF};
var
  Res, SecondRes: HResult;
begin
  if not TryWARPFirst then
  begin // Attempt to create hardware-accelerated Direct3D 11.x device and if such fails, try WARP device instead.
    Res := TryCreate(Result, TContextType.Hardware, DebugMode);
    if Failed(Res) then
    begin
      SecondRes := TryCreate(Result, TContextType.Software, DebugMode);
      if Succeeded(SecondRes) then
        Res := SecondRes;
    end;
  end
  else
  begin // Attempt to create WARP Direct3D 11.x device first and if this fails, try hardware-accelerated one.
    Res := TryCreate(Result, TContextType.Software, DebugMode);
    if Failed(Res) then
    begin
      SecondRes := TryCreate(Result, TContextType.Hardware, DebugMode);
      if Succeeded(SecondRes) then
        Res := SecondRes;
    end;
  end;

  // If device creation failed, try creating a reference device.
  if Failed(Res) then
  begin
    SecondRes := TryCreate(Result, TContextType.Reference, DebugMode);
    if Succeeded(SecondRes) then
      Res := SecondRes;
  end;

  if Failed(Res) then
    raise ContextException.Create(SysErrorMessage(Res));
end;

procedure TContext.Free;
begin
  FImmediateContext := nil;
  FDevice := nil;
end;

function TContext.CreateShaderFromFile(const FileName: string): ID3D11ComputeShader;
var
  MemStream: TMemoryStream;
  FileStream: TFileStream;
  Res: HResult;
begin
  MemStream := TMemoryStream.Create;
  try
    FileStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      MemStream.LoadFromStream(FileStream);
    finally
      FileStream.Free;
    end;
    Res := FDevice.CreateComputeShader(MemStream.Memory, MemStream.Size, nil, Result);
  finally
    MemStream.Free;
  end;
  if Failed(Res) then
    raise ContextException.Create(SysErrorMessage(Res));
end;

end.
