FUNCTION vis_calibrate_crosspol_phase,vis_ptr,flag_ptr,obs,cal
n_pol = obs.n_pol
IF n_pol LT 4 THEN RETURN, cal

icomp = Complex(0,1)
n_freq=cal.n_freq
n_tile=cal.n_tile
n_time=cal.n_time
n_baselines=obs.nbaselines
  
;Use the xx flags (yy should be identical at this point)
flag_use = 0>Reform(*flag_ptr[0],n_freq,n_baselines,n_time)<1

;average the visibilities in time
pseudo_U = Reform(*vis_ptr[3] + *vis_ptr[2],n_freq,n_baselines,n_time)
pseudo_U = Total(Temporary(pseudo_U)*flag_use,3)
pseudo_V = Reform(*vis_ptr[3] - icomp*(*vis_ptr[2]),n_freq,n_baselines,n_time)
pseudo_V = Total(Temporary(pseudo_V)*flag_use,3)
weight = Total(flag_use,3)
i_use = where(weight,n_use)
pseudo_U = Reform(pseudo_U[i_use],1,n_use)
pseudo_U_mat = [pseudo_U, Reform(fltarr(n_use) +1.0, 1,n_use)]
pseudo_V = Reform(pseudo_V[i_use],1,n_use)

;fit for leakage of Stokes U into V. We'll assume for now that that is due to an unfit phase between x and y
U_V_leakage = LA_Least_Squares(pseudo_U_mat,pseudo_V)
leakage_scale = Real_part(U_V_leakage[0])
leakage_offset = U_V_leakage[1]
scale_factor = 1./Sqrt(2.0)
phase_offset = Asin(leakage_scale) * scale_factor
cal.cross_phase = phase_offset
*(cal.gain[0]) *= Exp(icomp * phase_offset / 2.0)
*(cal.gain[1]) *= Exp(-icomp * phase_offset / 2.0)

;;average the visibilities in time
;pseudo_U = Reform(*vis_ptr[3] + *vis_ptr[2],n_freq,n_baselines,n_time)
;pseudo_U = Total(Temporary(pseudo_U)*flag_use,3)
;pseudo_V = Reform(*vis_ptr[3] - icomp*(*vis_ptr[2]),n_freq,n_baselines,n_time)
;pseudo_V = Total(Temporary(pseudo_V)*flag_use,3)
;weight = Total(Temporary(flag_use),3)
;
;gain_x = *(cal.gain[0])
;gain_y = *(cal.gain[1])
;;gain_arr=Complexarr(n_freq,n_tile)+1.
;phase_offset_arr = fltarr(n_freq)
;FOR freq_i=0,n_freq-1 DO BEGIN
;    i_use = where(weight[freq_i,*],n_use)
;    IF n_use EQ 0 THEN CONTINUE
;    pseudo_U_single = Reform(pseudo_U[freq_i,i_use],1,n_use)
;    pseudo_U_mat = [pseudo_U_single, Reform(fltarr(n_use) +1.0, 1,n_use)]
;    pseudo_V_single = Reform(pseudo_V[freq_i,i_use],1,n_use)
;    
;    ;fit for leakage of Stokes U into V. We'll assume for now that that is due to an unfit phase between x and y
;    U_V_leakage = LA_Least_Squares(pseudo_U_mat,pseudo_V_single)
;    leakage_scale = Real_part(U_V_leakage[0])
;    leakage_offset = U_V_leakage[1]
;    phase_offset = Asin(leakage_scale) / 2.0
;    phase_offset_arr[freq_i] = phase_offset
;    
;    ;Rotate x and y calibration gain solutions by half the calculated correction
;    ;Note that this should completely cancel out for xx and yy
;    gain_x[freq_i,*] *= Exp(icomp * phase_offset / 2.0)
;    gain_y[freq_i,*] *= Exp(-icomp * phase_offset / 2.0)
;ENDFOR
;*(cal.gain[0]) = gain_x
;*(cal.gain[1]) = gain_y

print,"Phase fit between X and Y antenna polarizations:", phase_offset
RETURN,cal
END


