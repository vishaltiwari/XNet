#!~/.conda/envs/myenv_vis/bin/python

from read_ts_file import *
import matplotlib
matplotlib.use('agg')
import matplotlib.pyplot as plt

def main():
  file_name = '../NSE_Tests/alpha_test/tss/ts_tnsn_alpha_1'
  zz, aa, xmf, time, temperature, density, timestep, edot, flx_end, flx = read_ts_file(file_name)
  print(build_isotope_symbol(zz,aa))
  pdb.set_trace()

if __name__ == "__main__":
  main()
