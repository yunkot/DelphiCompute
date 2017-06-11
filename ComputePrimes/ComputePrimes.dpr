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
program ComputePrimes;
{$APPTYPE CONSOLE}
{$R *.res}

uses
  Winapi.D3D11, Winapi.Windows, System.SysUtils, System.Math, System.Threading, System.Classes,
  Resources in '..\Resources.pas';

const
  ElementCount = 4194304;
  ThreadCount = 32;
  ElementsPerThread = ElementCount div ThreadCount;

var
  // Direct3D 11 context that facilitates common functionality.
  Context: TContext;

  // Element Buffers and their views.
  PrimeCounter: ID3D11Buffer = nil;
  PrimeCounterUAV: ID3D11UnorderedAccessView = nil;
  PrimeCounterRead: ID3D11Buffer = nil;

  // Compute Shaders.
  ComputeShader: ID3D11ComputeShader = nil;

function IsPrime(const Value: Cardinal): Cardinal;
var
  I, Limit: Cardinal;
begin
  if Value <= 3 then
  begin
    if Value > 1 then
      Result := 1
    else
      Result := 0;
    Exit;
  end
  else if ((Value mod 2) = 0) or ((Value mod 3) = 0) then
    Exit(0)
  else
  begin
    Limit := Floor(Sqrt(Value));
    I := 5;
    while I <= Limit do
    begin
      if ((Value mod I) = 0) or ((Value mod (I + 2)) = 0) then
        Exit(0);
      Inc(I, 6);
    end;
  end;
  Result := 1;
end;

type
  TPrimeThread = class(TThread)
  private
    FThreadIndex: Integer;
  public
    constructor Create(const AThreadIndex: Integer);
    procedure Execute; override;
  class var
    PrimeCount: Integer;
  end;

constructor TPrimeThread.Create(const AThreadIndex: Integer);
begin
  inherited Create(False);
  FThreadIndex := AThreadIndex;
end;

procedure TPrimeThread.Execute;
var
  I, StartIndex, EndIndex, LocalCount: Integer;
begin
  LocalCount := 0;
  StartIndex := FThreadIndex * ElementsPerThread;
  EndIndex := StartIndex + ElementsPerThread;

  for I := StartIndex to EndIndex do
    Inc(LocalCount, IsPrime(I));

  AtomicIncrement(PrimeCount, LocalCount);
end;

function ComputePrimesCPU_Threads: Cardinal;
var
  Threads: array[0..ThreadCount - 1] of TPrimeThread;
  I: Integer;
begin
  TPrimeThread.PrimeCount := 0;

  for I := 0 to ThreadCount - 1 do
    Threads[I] := TPrimeThread.Create(I);

  for I := 0 to ThreadCount - 1 do
  begin
    Threads[I].WaitFor;
    Threads[I].Free;
  end;

  Result := TPrimeThread.PrimeCount;
end;

function ComputePrimesCPU_PPL: Cardinal;
var
  Res: Cardinal;
begin
  Res := 0;
  TParallel.&For(1, ElementCount - 1, procedure(I: Integer)
    begin
      if IsPrime(Cardinal(I)) <> 0 then
        AtomicIncrement(Res);
    end);

  Result := Res;
end;

function CreateBuffersGPU: Boolean;
var
  BufferDesc: D3D11_BUFFER_DESC;
  AccessViewDesc: D3D11_UNORDERED_ACCESS_VIEW_DESC;
begin
  // Create Prime Counter buffer.
  FillChar(BufferDesc, SizeOf(D3D11_BUFFER_DESC), 0);
  BufferDesc.ByteWidth := SizeOf(Cardinal);
  BufferDesc.BindFlags := D3D11_BIND_UNORDERED_ACCESS or D3D11_BIND_SHADER_RESOURCE;
  BufferDesc.MiscFlags := Ord(D3D11_RESOURCE_MISC_BUFFER_STRUCTURED);
  BufferDesc.StructureByteStride := SizeOf(Cardinal);

  if Failed(Context.Device.CreateBuffer(BufferDesc, nil, PrimeCounter)) then
    Exit(False);

  // UAV for Prime Counter buffer.
  FillChar(AccessViewDesc, SizeOf(D3D11_UNORDERED_ACCESS_VIEW_DESC), 0);
  AccessViewDesc.ViewDimension := D3D11_UAV_DIMENSION_BUFFER;
  AccessViewDesc.Buffer.NumElements := 1;

  if Failed(Context.Device.CreateUnorderedAccessView(PrimeCounter, @AccessViewDesc, PrimeCounterUAV)) then
    Exit(False);

  // Create Primer Counter "Reader" buffer.
  FillChar(BufferDesc, SizeOf(D3D11_BUFFER_DESC), 0);
  BufferDesc.ByteWidth := Sizeof(Cardinal);
  BufferDesc.Usage := D3D11_USAGE_STAGING;
  BufferDesc.CPUAccessFlags := D3D11_CPU_ACCESS_READ;
  BufferDesc.StructureByteStride := SizeOf(Cardinal);

  if Failed(Context.Device.CreateBuffer(BufferDesc, nil, PrimeCounterRead)) then
    Exit(False);

  Result := True;
end;

procedure DestroyBuffersGPU;
begin
  PrimeCounterRead := nil;
  PrimeCounterUAV := nil;
  PrimeCounter := nil;
end;

procedure CreateResourcesGPU;
var
  ShaderPath: string;
begin
  if not CreateBuffersGPU then
    raise Exception.Create('Could not create Direct3D 11 buffers.');

  ShaderPath := ExtractFilePath(ParamStr(0)) + 'shaders\';

  ComputeShader := Context.CreateShaderFromFile(ShaderPath + 'ComputePrimes.cs.bin');
  if ComputeShader = nil then
    raise Exception.Create('Could not create Bitonic compute shader.');
end;

procedure DestroyResourcesGPU;
begin
  ComputeShader := nil;
  DestroyBuffersGPU;
end;

function ComputePrimesGPU: Cardinal;
var
  Mapped: D3D11_MAPPED_SUBRESOURCE;
begin
  // Init shared prime counter to zero.
  Result := 0;
  Context.ImmediateContext.UpdateSubresource(PrimeCounter, 0, nil, @Result, 0, 0);

  // Execute 128 thread groups, each having 512 threads.
  Context.ImmediateContext.CSSetUnorderedAccessViews(0, 1, PrimeCounterUAV, nil);
  Context.ImmediateContext.CSSetShader(ComputeShader, nil, 0);
  Context.ImmediateContext.Dispatch(128, 1, 1);

  // Copy shared prime counter into system memory.
  Context.ImmediateContext.CopySubresourceRegion(PrimeCounterRead, 0, 0, 0, 0, PrimeCounter, 0, nil);

  // Retrieve shared prime counter.
  FillChar(Mapped, SizeOf(D3D11_MAPPED_SUBRESOURCE), 0);
  if Failed(Context.ImmediateContext.Map(PrimeCounterRead, 0, D3D11_MAP_READ, 0, Mapped)) then
    raise Exception.Create('Could not map Read-Back buffer.');

  Move(Mapped.pData^, Result, SizeOf(Cardinal));
  Context.ImmediateContext.Unmap(PrimeCounterRead, 0);
end;

var
  PrimeCount, InitTicks, TicksCPU_Threads, TicksCPU_PPL, TicksGPU: Cardinal;

begin
  try
    SetExceptionMask(exAllArithmeticExceptions);

    WriteLn('Prime calculation, CPU vs GPU performance benchmark.');
    WriteLn('Applying prime test for numbers between 1 and ' + (ElementCount - 1).ToString + '.');
    WriteLn;

    WriteLn('1. Prime calculation on CPU, multi-threaded using PPL.');

    InitTicks := GetStartTickCount;
    PrimeCount := ComputePrimesCPU_PPL;
    TicksCPU_PPL := GetStartTickCount - InitTicks;

    WriteLn('Primes = ' + PrimeCount.ToString + ', total time: ' + TicksCPU_PPL.ToString + ' ms.');
    WriteLn;

    WriteLn('2. Prime calculation on CPU, multi-threaded using TThread.');

    InitTicks := GetStartTickCount;
    PrimeCount := ComputePrimesCPU_Threads;
    TicksCPU_Threads := GetStartTickCount - InitTicks;

    WriteLn('Primes = ' + PrimeCount.ToString + ', total time: ' + TicksCPU_Threads.ToString + ' ms.');
    WriteLn;

    WriteLn('3. Prime calculation on GPU.');

    Context := TContext.Create;
    try
      CreateResourcesGPU;
      try
        InitTicks := GetStartTickCount;
        PrimeCount := ComputePrimesGPU;

        TicksGPU := GetStartTickCount - InitTicks;
      finally
        DestroyResourcesGPU;
      end;
    finally
      Context.Free;
    end;

    WriteLn('Primes = ' + PrimeCount.ToString + ', total time: ' + TicksGPU.ToString + ' ms.');
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
