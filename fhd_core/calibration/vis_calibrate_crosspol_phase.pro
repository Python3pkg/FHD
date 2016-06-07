FUNCTION vis_calibrate_crosspol_phase,vis_ptr,vis_weight_ptr,obs,cal,preserve_visibilities=preserve_visibilities,_Extra=extra

n_pol = obs.n_pol
IF n_pol LT 4 THEN RETURN, cal

icomp = Complex(0,1)
n_freq=cal.n_freq
n_tile=cal.n_tile
n_time=cal.n_time
tile_A_i=cal.tile_A-1
tile_B_i=cal.tile_B-1
freq_arr=cal.freq
bin_offset=cal.bin_offset
n_baselines=obs.nbaselines
  

tile_A_i = tile_A_i[0:n_baselines-1]
tile_B_i = tile_B_i[0:n_baselines-1]
;Use the xx flags (yy should be identical at this point)
weights_use = 0>Reform(*vis_weight_ptr[0],n_freq,n_baselines,n_time)<1
;average the visibilities in time
pseudo_U = Reform(*vis_ptr[3] + *vis_ptr[2],n_freq,n_baselines,n_time)
pseudo_U = Total(Temporary(pseudo_U)*weights_use,3)
pseudo_V = Reform(*vis_ptr[3] - icomp*(*vis_ptr[2]),n_freq,n_baselines,n_time)
pseudo_V = Total(Temporary(pseudo_V)*weights_use,3)
weight = Total(Temporary(weights_use),3)

i_use = where(weight,n_use)
pseudo_U = Reform(pseudo_U[i_use],1,n_use)
pseudo_U_mat = [pseudo_U, Reform(fltarr(n_use) +1.0, 1,n_use)]
pseudo_V = Reform(pseudo_V[i_use],1,n_use)

;fit for leakage of Stokes U into V. We'll assume for now that that is due to an unfit phase between x and y
U_V_leakage = LA_Least_Squares(pseudo_U_mat,pseudo_V)
leakage_scale = Real_part(U_V_leakage[0])
leakage_offset = U_V_leakage[1]
phase_offset = Asin(leakage_scale) / 2.0
cal.cross_phase = phase_offset
;gain_correction = Exp(icomp * phase_offset)

;Rotate x and y calibration gain solutions by half the calculated correction
;Note that this should completely cancel out for xx and yy
*(cal.gain[0]) *= Exp(icomp * phase_offset / 2.0)
*(cal.gain[1]) *= Exp(-icomp * phase_offset / 2.0)

print,"Phase fit between X and Y antenna polarizations:", phase_offset
RETURN,cal
END


