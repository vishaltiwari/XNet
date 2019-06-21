#!/usr/bin/python

from scipy.io import loadmat
import numpy as np

import matplotlib
matplotlib.use('agg')
import pdb
import matplotlib.pyplot as plt


def plot_abund(abundance_dict_time , sym_list,file_name,sim_time):
  #pdb.set_trace()
  plot_name = file_name.split('.')[0]+"_mass_fraction.png"
  sym_abund = {}
  thres_abund = 1e-2
  all_legends = []
  all_handles = []
  for sym in abundance_dict_time:
    ab_nuc = abundance_dict_time[sym]
    sym_abund[sym] = []
    mark = False
    for indx, abund_val in enumerate(ab_nuc):
      #pdb.set_trace()
      if abund_val > thres_abund:
        mark = True
      sym_abund[sym].append(float(abund_val))
    # plot
    #if sym == 'fe53':
    #  pdb.set_trace()
    #handle, = plt.plot(range(len(abundance_dict_time['C12'])) , sym_abund[sym], label=sym)
    handle, = plt.semilogx(sim_time , sym_abund[sym], label=sym)
    if mark == True:
      all_handles.append(handle)
      all_legends.append(sym)

  plt.xlabel('Time step')
  plt.ylabel('Mass fraction')
  #pdb.set_trace()
  #plt.legend(all_handles,all_legends,bbox_to_anchor=(1.04,1), ncol=3)
  plt.legend(all_handles,all_legends, bbox_to_anchor=(0,1.02,1,0.2), loc="lower left", mode="expand", borderaxespad=0, ncol=3)
  #plt.legend(all_handles,all_legends, bbox_to_anchor=(1.04,0), loc="lower left", mode="expand", borderaxespad=0, ncol=3)
  plt.savefig(plot_name,bbox_inches="tight")
  plt.clf()

def main():
  #print('This is Main')
<<<<<<< Updated upstream
  file_dir = './'
=======
  file_dir = '../run_SN150_2/'
>>>>>>> Stashed changes
  file_name = 'tso1_150_rho1e9_T5e9_.mat'
  filepath = file_dir + file_name
  ele_filename = 'Z_file.csv'
  x = loadmat(filepath)
  data = x['data']
  sim_time = x['sim_time']
  pdb.set_trace()
  nb_timesteps = data.shape[0] - 2
  nb_nuclides = data.shape[1]
  zz = data[0,:]
  aa = data[1,:]
  
  #pdb.set_trace()

  file_obj = open(ele_filename,"r")
  Z_sym_dic = {}
  Z_sym_dic[0] = 'n'
  Z_sym_dic[1] = 'p'
  for line in file_obj:
    Z = int(line.split(',')[0])
    sym = line.split(',')[1].split('\n')[0]
    Z_sym_dic[Z] = sym
    #print(line)

  abund_dic_time = {}
  sym_list = []
  for indx, Z in enumerate(zz):
    Z = int(Z)
    A = int(aa[indx])
    sym = Z_sym_dic[Z]
    if sym == 'p' or sym == 'n':
      nuclide = sym
    else:
      nuclide = sym + str(A)
    
    ab_ndarr = mass_frac_time = data[2:,indx]
    abund_dic_time[nuclide] = ab_ndarr
    sym_list.append(nuclide)
    print(nuclide.lower() +" "+ str(data[-1,indx]))
  pdb.set_trace()
  plot_abund(abund_dic_time , sym_list , file_name,sim_time)

if __name__ == '__main__':
  main()
