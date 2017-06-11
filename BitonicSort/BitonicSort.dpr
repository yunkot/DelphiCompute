(*
 * Copyright (c) 2017 Yuriy Kotsarenko.
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
program BitonicSort;
{$APPTYPE CONSOLE}
{$R *.res}

uses
  Winapi.D3D11, Winapi.D3DCommon, Winapi.Windows, System.SysUtils, System.Math, System.Threading, System.Classes,
  System.Generics.Collections, Resources in '..\Resources.pas';

type
  TConstantBuffer = record
    Level: Cardinal;
    LevelMask: Cardinal;
    Width: Cardinal;
    Height: Cardinal;
  end;

  TBufferElement = Single;

const
  BitonicBlockSize = 1024;
  NumElements = BitonicBlockSize * BitonicBlockSize;
  TransposeBlockSize = 32;
  MatrixWidth = BitonicBlockSize;
  MatrixHeight = NumElements div BitonicBlockSize;

var
  // Direct3D 11 context that facilitates common functionality.
  Context: TContext;

  // Buffers containing actual elements to be sorted, these are used in ping-pong fashion.
  Buffer1: ID3D11Buffer = nil;
  Buffer1SRV: ID3D11ShaderResourceView = nil;
  Buffer1UAV: ID3D11UnorderedAccessView = nil;

  Buffer2: ID3D11Buffer = nil;
  Buffer2SRV: ID3D11ShaderResourceView = nil;
  Buffer2UAV: ID3D11UnorderedAccessView = nil;

  // Constant Buffer.
  ConstantBuffer: ID3D11Buffer = nil;
  // Read-Back Buffer.
  ReadBackBuffer: ID3D11Buffer = nil;

  // Bitonic Sort shader.
  ComputeBitonicSort: ID3D11ComputeShader = nil;
  // Matrix Transpose shader (used in combination with Bitonic Sort).
  ComputeMatrixTranspose: ID3D11ComputeShader = nil;

  // Data Buffers.
  Values: TArray<TBufferElement>;
  Results: TArray<TBufferElement>;

procedure InitValues;
var
  I: Integer;
begin
  Randomize;

  SetLength(Values, NumElements);
  SetLength(Results, NumElements);

  for I := 0 to NumElements - 1 do
    Values[I] := Random;
end;

function CreateBuffersGPU: Boolean;
var
  BufferDesc: D3D11_BUFFER_DESC;
  ResViewDesc: D3D11_SHADER_RESOURCE_VIEW_DESC;
  AccessViewDesc: D3D11_UNORDERED_ACCESS_VIEW_DESC;
begin
  // Constant Buffer.
  FillChar(BufferDesc, SizeOf(D3D11_BUFFER_DESC), 0);
  BufferDesc.ByteWidth := SizeOf(TConstantBuffer);
  BufferDesc.BindFlags := D3D11_BIND_CONSTANT_BUFFER;

  if Failed(Context.Device.CreateBuffer(BufferDesc, nil, ConstantBuffer)) then
    Exit(False);

  // ReadBack Buffer.
  FillChar(BufferDesc, SizeOf(D3D11_BUFFER_DESC), 0);
  BufferDesc.ByteWidth := NumElements * SizeOf(TBufferElement);
  BufferDesc.Usage := D3D11_USAGE_STAGING;
  BufferDesc.CPUAccessFlags := D3D11_CPU_ACCESS_READ;
  BufferDesc.StructureByteStride := SizeOf(TBufferElement);

  if Failed(Context.Device.CreateBuffer(BufferDesc, nil, ReadBackBuffer)) then
    Exit(False);

  // Element Buffers.
  FillChar(BufferDesc, SizeOf(D3D11_BUFFER_DESC), 0);
  BufferDesc.ByteWidth := NumElements * SizeOf(TBufferElement);
  BufferDesc.BindFlags := D3D11_BIND_UNORDERED_ACCESS or D3D11_BIND_SHADER_RESOURCE;
  BufferDesc.MiscFlags := Ord(D3D11_RESOURCE_MISC_BUFFER_STRUCTURED);
  BufferDesc.StructureByteStride := SizeOf(TBufferElement);

  if Failed(Context.Device.CreateBuffer(BufferDesc, nil, Buffer1)) then
    Exit(False);

  if Failed(Context.Device.CreateBuffer(BufferDesc, nil, Buffer2)) then
    Exit(False);

  // Resource Views for Element Buffers.
  FillChar(ResViewDesc, SizeOf(D3D11_SHADER_RESOURCE_VIEW_DESC), 0);
  ResViewDesc.ViewDimension := D3D11_SRV_DIMENSION_BUFFER;
  ResViewDesc.Buffer.ElementWidth := NumElements;

  if Failed(Context.Device.CreateShaderResourceView(Buffer1, @ResViewDesc, Buffer1SRV)) then
    Exit(False);

  if Failed(Context.Device.CreateShaderResourceView(Buffer2, @ResViewDesc, Buffer2SRV)) then
    Exit(False);

  // Access Views for Element Buffers.
  FillChar(AccessViewDesc, SizeOf(D3D11_UNORDERED_ACCESS_VIEW_DESC), 0);
  AccessViewDesc.ViewDimension := D3D11_UAV_DIMENSION_BUFFER;
  AccessViewDesc.Buffer.NumElements := NumElements;

  if Failed(Context.Device.CreateUnorderedAccessView(Buffer1, @AccessViewDesc, Buffer1UAV)) then
    Exit(False);

  if Failed(Context.Device.CreateUnorderedAccessView(Buffer2, @AccessViewDesc, Buffer2UAV)) then
    Exit(False);

  Result := True;
end;

procedure DestroyBuffersGPU;
begin
  ReadBackBuffer := nil;
  ConstantBuffer := nil;
  Buffer2UAV := nil;
  Buffer2SRV := nil;
  Buffer2 := nil;
  Buffer1UAV := nil;
  Buffer1SRV := nil;
  Buffer1 := nil;
end;

procedure CreateResourcesGPU;
var
  ShaderPath: string;
begin
  if not CreateBuffersGPU then
    raise Exception.Create('Could not create Direct3D 11 buffers.');

  ShaderPath := ExtractFilePath(ParamStr(0)) + 'shaders\';

  ComputeBitonicSort := Context.CreateShaderFromFile(ShaderPath + 'BitonicSort.cs.bin');
  if ComputeBitonicSort = nil then
    raise Exception.Create('Could not create Bitonic compute shader.');

  ComputeMatrixTranspose := Context.CreateShaderFromFile(ShaderPath + 'MatrixTranspose.cs.bin');
  if ComputeMatrixTranspose = nil then
    raise Exception.Create('Could not create Transpose compute shader.');
end;

procedure DestroyResourcesGPU;
begin
  ComputeMatrixTranspose := nil;
  ComputeBitonicSort := nil;
  DestroyBuffersGPU;
end;

procedure UpdateConstantBuffer(const Level, LevelMask, Width, Height: Cardinal);
var
  LBuffer: TConstantBuffer;
begin
  LBuffer.Level := Level;
  LBuffer.LevelMask := LevelMask;
  LBuffer.Width := Width;
  LBuffer.Height := Height;

  Context.ImmediateContext.UpdateSubresource(ConstantBuffer, 0, nil, @LBuffer, 0, 0);
  Context.ImmediateContext.CSSetConstantBuffers(0, 1, ConstantBuffer);
end;

procedure BitonicSortGPU;
const
  NullView: ID3D11ShaderResourceView = nil;
var
  Level: Cardinal;
  Mapped: D3D11_MAPPED_SUBRESOURCE;
begin
  // Upload initial values to GPU memory.
  Context.ImmediateContext.UpdateSubresource(Buffer1, 0, nil, @Values[0], 0, 0);

  // Sort the rows for the levels smaller than block size.
  Level := 2;

  while Level <= BitonicBlockSize do
  begin
    UpdateConstantBuffer(Level, Level, MatrixHeight, MatrixWidth);

    // Sort the row data
    Context.ImmediateContext.CSSetUnorderedAccessViews(0, 1, Buffer1UAV, nil);
    Context.ImmediateContext.CSSetShader(ComputeBitonicSort, nil, 0);
    Context.ImmediateContext.Dispatch(NumElements div BitonicBlockSize, 1, 1);

    Level := Level * 2;
  end;

  // Sort the rows and columns for the levels bigger than the block size.
  Level := BitonicBlockSize * 2;

  while Level <= NumElements do
  begin
    // Transpose the matrix.
    UpdateConstantBuffer(Level div BitonicBlockSize, (Level and (not NumElements)) div BitonicBlockSize, MatrixWidth,
      MatrixHeight);

    Context.ImmediateContext.CSSetShaderResources(0, 1, NullView);
    Context.ImmediateContext.CSSetUnorderedAccessViews(0, 1, Buffer2UAV, nil);
    Context.ImmediateContext.CSSetShaderResources(0, 1, Buffer1SRV);
    Context.ImmediateContext.CSSetShader(ComputeMatrixTranspose, nil, 0);
    Context.ImmediateContext.Dispatch(MatrixWidth div TransposeBlockSize, MatrixHeight div TransposeBlockSize, 1);

    // Sort the columns.
    Context.ImmediateContext.CSSetShader(ComputeBitonicSort, nil, 0);
    Context.ImmediateContext.Dispatch(NumElements div BitonicBlockSize, 1, 1);

    // Transpose the matrix into another buffer.
    UpdateConstantBuffer(BitonicBlockSize, Level, MatrixHeight, MatrixWidth);

    Context.ImmediateContext.CSSetShaderResources(0, 1, NullView);
    Context.ImmediateContext.CSSetUnorderedAccessViews(0, 1, Buffer1UAV, nil);
    Context.ImmediateContext.CSSetShaderResources(0, 1, Buffer2SRV);
    Context.ImmediateContext.CSSetShader(ComputeMatrixTranspose, nil, 0);
    Context.ImmediateContext.Dispatch(MatrixHeight div TransposeBlockSize, MatrixWidth div TransposeBlockSize, 1);

    // Sort the rows.
    Context.ImmediateContext.CSSetShader(ComputeBitonicSort, nil, 0);
    Context.ImmediateContext.Dispatch(NumElements div BitonicBlockSize, 1, 1);

    Level := Level * 2;
  end;

  // Retrieve resulting values.
  Context.ImmediateContext.CopySubresourceRegion(ReadBackBuffer, 0, 0, 0, 0, Buffer1, 0, nil);

  FillChar(Mapped, SizeOf(D3D11_MAPPED_SUBRESOURCE), 0);
  if Failed(Context.ImmediateContext.Map(ReadBackBuffer, 0, D3D11_MAP_READ, 0, Mapped)) then
    raise Exception.Create('Could not map Read-Back buffer.');

  Move(Mapped.pData^, Results[0], NumElements * SizeOf(TBufferElement));
  Context.ImmediateContext.Unmap(ReadBackBuffer, 0);
end;

procedure QuicksortCPU;
begin
  TArray.Sort<Single>(Values);
end;

function CompareResults: Boolean;
var
  I: Integer;
begin
  for I := 0 to NumElements - 1 do
    if Values[I] <> Results[I] then
      Exit(False);

  Result := True;
end;

var
  InitTicks, TicksCPU, TicksGPU: Cardinal;

begin
  try
    SetExceptionMask(exAllArithmeticExceptions);

    WriteLn('Bitonic Sort, CPU vs GPU performance benchmark.');
    WriteLn('Sorting ' + NumElements.ToString + ' elements.');
    WriteLn;

    InitValues;

    WriteLn('1. Running BitonicSort on GPU.');

    Context := TContext.Create;
    try
      CreateResourcesGPU;
      try
        InitTicks := GetStartTickCount;
        BitonicSortGPU;

        TicksGPU := GetStartTickCount - InitTicks;

        WriteLn('Total time: ' + TicksGPU.ToString + ' ms.');
        WriteLn;
      finally
        DestroyResourcesGPU;
      end;
    finally
      Context.Free;
    end;

    WriteLn('2. Running Quicksort on CPU.');

    InitTicks := GetStartTickCount;
    QuicksortCPU;

    TicksCPU := GetStartTickCount - InitTicks;

    WriteLn('Total time: ' + TicksCPU.ToString + ' ms.');
    WriteLn;

    if not CompareResults then
      WriteLn('WARNING! Resulting arrays DO NOT MATCH.')
    else
      WriteLn('Resulting arrays between CPU and GPU sorts match.');

    WriteLn;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
