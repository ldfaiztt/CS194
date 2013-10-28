__kernel void update(__global int *in_zeroes,
         __global int *in_ones
		     __global int *block_zeroes,
         __global int *block_ones,
		     int n)
{
  size_t idx = get_global_id(0);
  size_t tid = get_local_id(0);
  size_t dim = get_local_size(0);
  size_t gid = get_group_id(0);

  if(idx < n && gid > 0)
    {
      in_zeroes[idx] = in_zeroes[idx] + block_zeroes[gid-1];
      in_ones[idx] = in_ones[idx] + block_ones[gid - 1];
    }
}

__kernel void scan(__global int *in_zeroes,
       __global int *in_ones,
		   __global int *zeroes,
       __global int *ones, 
		   __global int *bzeros,
       __global int *bones,
		   /* dynamically sized local (private) memory */
		   __local int *zeroes_buf,
       __local int *ones_buf 
		   int v,
		   int k,
		   int n)
{
  size_t idx = get_global_id(0);
  size_t tid = get_local_id(0);
  size_t dim = get_local_size(0);
  size_t gid = get_group_id(0);
  int t, r = 0, w = dim;

  if(idx<n){
    z = in_zeroes[idx];
    o = in_ones[idx];
    /* CS194: v==-1 used to signify 
     * a "normal" additive scan
     * used to update the partial scans */
    z = (v==-1) ? z : (v==((z>>k)&0x1)); 
    o = (v==-1) ? o : (v!=((o>>k)&0x1)); 

    zeroes_buf[tid] = z;
    ones_buf[tid] = o;
  }
  else{
    zeroes_buf[tid] = 0;
    ones_buf[tid] = 0;
  }
  
  barrier(CLK_LOCAL_MEM_FENCE);

  /* CS194: Your scan code from HW 5 goes here */

  //the first sweep up reduction step
  int offset = 1;
  for (int d = dim >> 1; d > 0; d >>= 1)
  {
    if(tid < d){
      zeroes_buf[offset * (2 * tid + 2) - 1] += zeroes_buf[offset * (2 * tid + 1) - 1];
      ones_buf[offset * (2 * tid + 2) - 1] += ones_buf[offset * (2 * tid + 1) - 1];
    }
    offset <<= 1;
    barrier(CLK_LOCAL_MEM_FENCE);
  }

  // at the last value in the local buffer to the other array for 
  //the update kernel so that this value can be added into the rest
  // of the values in the output array after this index.
  bzeros[gid] = zeroes_buf[dim - 1];
  bones[gid] = ones_buf[dim - 1];

  barrier(CLK_LOCAL_MEM_FENCE | CLK_GLOBAL_MEM_FENCE);

  // assigned last value in the calculated sweep up reduction step to 0
  zeroes_buf[dim - 1] = 0;
  ones_buf[dim - 1] = 0;

  // the final sweep down step
  for(int d = 1; d < dim; d <<= 1){
    offset >>= 1;
    barrier(CLK_LOCAL_MEM_FENCE);

    if(tid < d){
      int a = offset * (2 * tid + 1) - 1;
      int b = offset * (2 * tid +  2) - 1;

      int temp0 = zeroes_buf[a];
      int temp1 = ones_buf[a];

      zeroes_buf[a] = zeroes_buf[b];
      ones_buf[a] = ones_buf[b];

      zeroes_buf[b] += temp0;
      ones_buf[b] += temp1;
    }
  }

  barrier(CLK_LOCAL_MEM_FENCE);

  // put the values back into the output array from the local buffer with
  // a one index shift. The last value the from the other array that was 
  // previously stored.
  if(idx < n){
    if(tid == dim - 1){
      out[idx] = bout[gid];
    }else{
      out[idx] = buf[tid + 1];
    }
  }

  /* CS194: Store partial scans */
  /*
  if(idx < n)
    {
      out[idx] = buf[r+tid];
    }
  */
  /* CS194: one work-item stores the
   * work group's total partial
   * "reduction" */
  /*
  if(tid==0)
    {
      bout[gid] = buf[r+dim-1];
    }
  */
}

__kernel void reassemble(__global int *in, __global int *out, __global int *zeroes, __global int *ones, __local int *temp_buf,/* __local int *zeros_buf, __local int *ones_buf,*/ int k, int n){
  size_t idx = get_global_id(0);
  size_t tid = get_local_id(0);
  size_t dim = get_local_size(0);
  size_t gid = get_group_id(0);

  int offset;
  if (idx < n){
    temp_buf[tid] = ((in[idx] >> k) & 0x1);
    //zeroes_buf[tid] = zeroes[idx];
    //ones_buf[tid] = ones[idx];
  }
  
  if(temp_buf[tid]){
    offset = zeroes[n - 1] + ones[idx] - 1;
  }else{
    offset = zeroes[idx] - 1;
  }
  out[offset] = in[idx];
  barrier(CLK_GLOBAL_MEM_FENCE);
}
