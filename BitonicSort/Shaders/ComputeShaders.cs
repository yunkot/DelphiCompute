/*
 * Original source code copyright (c) 2017 Microsoft Corporation. All rights reserved.
 * Modifications and refactoring are copyright (c) 2017 Yuriy Kotsarenko.
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
 */

// Data type of individual elements.
typedef float ElementType;

// Shared buffer size of for bitonic sort.
static const uint BitonicBlockSize = 1024;

// Shared buffer length for matrix transpose shader.
static const uint TransposeBlockLength = 32;

// Constant buffer provided by application.
cbuffer ConstantBuffer: register(b0)
{
  uint level;
  uint levelMask;
  uint width;
  uint height;
};

// Buffer of elements to be sorted.
RWStructuredBuffer<ElementType> elementBuffer: register(u0);

// Input matrix for transpose shader.
StructuredBuffer<ElementType> inputMatrix: register(t0);

// Data buffer shared among bitonic sort threads.
groupshared ElementType bitonicBuffer[BitonicBlockSize];

// elementBuffer buffer shared among matrix transpose threads.
groupshared ElementType transposeBuffer[TransposeBlockLength * TransposeBlockLength];

[numthreads(BitonicBlockSize, 1, 1)]
void bitonicSort(uint3 Gid: SV_GroupID, uint3 DTid: SV_DispatchThreadID, uint3 GTid: SV_GroupThreadID,
  uint GI: SV_GroupIndex)
{
  bitonicBuffer[GI] = elementBuffer[DTid.x];
  GroupMemoryBarrierWithGroupSync();

  for (uint i = level >> 1; i > 0; i >>= 1)
  {
    ElementType result = ((bitonicBuffer[GI & ~i] <= bitonicBuffer[GI | i]) == (bool)(levelMask & DTid.x)) ?
      bitonicBuffer[GI ^ i] : bitonicBuffer[GI];
    GroupMemoryBarrierWithGroupSync();
    bitonicBuffer[GI] = result;
    GroupMemoryBarrierWithGroupSync();
  }

  elementBuffer[DTid.x] = bitonicBuffer[GI];
}

[numthreads(TransposeBlockLength, TransposeBlockLength, 1)]
void matrixTranspose(uint3 Gid: SV_GroupID, uint3 DTid: SV_DispatchThreadID, uint3 GTid: SV_GroupThreadID,
  uint GI: SV_GroupIndex)
{
  transposeBuffer[GI] = inputMatrix[DTid.y * width + DTid.x];
  GroupMemoryBarrierWithGroupSync();
  uint2 XY = DTid.yx - GTid.yx + GTid.xy;
  elementBuffer[XY.y * height + XY.x] = transposeBuffer[GTid.x * TransposeBlockLength + GTid.y];
}
