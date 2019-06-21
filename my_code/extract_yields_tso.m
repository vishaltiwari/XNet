%% Author : Vishal Tiwari 28th May 2019
%%
function[data] = extract_yields_tso(tso_filename)
  % call the 
  [zz, aa, xmf, time, temperature, density, timestep, edot, flx_end, flx] = read_ts_file(tso_filename);

  format long;
  timestep_count = size(time,2);
  total_nuclides = size(zz,1);
  % Each col contains information for a specific nuclide
  % First row contains Z.
  % Second row: Mass Number A.
  % Third to end, contains the mass fraction over each time step.
  % eg: data(3) : Initial mass fraction.
  % eg: data(timestep_count) : Final mass fraction.
  data = [zz' ; aa' ; xmf(:,:)'];
  size(data)
  sim_time = time'
  params = strcat(strcat(strcat('_temp_',num2str(temperature(1))),'_den_'),num2str(density(1)));
  plot_name = strcat(strcat(tso_filename , params),'_plt.png');
  
%   for indx = 1:1:total_nuclides
%     Z = data(1,indx);
%     A = data(2,indx);
%     nuclide_data = data(3:size(data,1),indx);
%     % plot this abundance
%     x_arr = 1:1:timestep_count;
%     hold on;
%     plot(x_arr , nuclide_data);
%   end
  %% Extract the sym from zz and aa
  %% Save the plot
  %saveas(gcf,plot_name)
  mat_filename = strcat(tso_filename,'_.mat');
  save(mat_filename,'data','sim_time');
end
