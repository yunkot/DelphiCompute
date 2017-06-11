/*
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
 */

// Total number of elements to be tested for primes.
static const uint ElementCount = 4194304;

// Total number of thread blocks.
static const uint BlockCount = 128;

// Total number of worker threads.
static const uint ThreadCount = 512;

// Number of elements tested in each thread.
static const uint ElementsPerWorker = ElementCount / (BlockCount * ThreadCount);

// Buffer that holds total number of primes. Should start at zero.
RWStructuredBuffer<uint> primeCounter: register(u0);

// Determines whether the given value is a prime number.
uint isPrime(uint value)
{
  if (value <= 3)
    return value > 1 ? 1 : 0;
  else if (((value % 2) == 0) || ((value % 3) == 0))
    return 0;
  else
  {
  	const uint limit = (uint)floor(sqrt(value));
  	for (uint i = 5; i <= limit; i += 6)
			if ((value % i) == 0 || (value % (i + 2)) == 0)
        return 0;
	}
  return 1;
}

[numthreads(ThreadCount, 1, 1)]
void computePrimes(uint3 DTid: SV_DispatchThreadID)
{
  const uint elementStart = DTid.x * ElementsPerWorker;
  const uint elementEnd = elementStart + ElementsPerWorker;
  uint localCount = 0;

  for (uint i = elementStart; i < elementEnd; ++i)
    localCount += isPrime(i);

  InterlockedAdd(primeCounter[0], localCount);
}
