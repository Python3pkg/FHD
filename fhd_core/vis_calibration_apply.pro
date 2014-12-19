FUNCTION vis_calibration_apply,vis_ptr,cal,preserve_original=preserve_original,pol_i=pol_i,invert_gain=invert_gain

n_pol_ant=cal.n_pol
n_pol_vis=N_Elements(vis_ptr)
n_freq=cal.n_freq
n_tile=cal.n_tile
n_time=cal.n_time
bin_offset=cal.bin_offset
tile_A_i=cal.tile_A-1 ;tile numbering starts at 1
tile_B_i=cal.tile_B-1 ;tile numbering starts at 1
n_baselines=Long(N_Elements(tile_A_i))

gain_pol_arr1=[0,1,0,1]
gain_pol_arr2=[0,1,1,0]

gain_ptr=cal.gain ;Ptrarr(n_pol_ant) to n_freq x n_tile complex arrays

inds_A=Rebin(Lindgen(n_freq),n_freq,n_baselines,/sample)+Rebin(transpose(tile_A_i)*n_freq,n_freq,n_baselines)
inds_B=Rebin(Lindgen(n_freq),n_freq,n_baselines,/sample)+Rebin(transpose(tile_B_i)*n_freq,n_freq,n_baselines)

IF N_Elements(pol_i) EQ 0 THEN BEGIN
    IF Keyword_Set(preserve_original) THEN vis_cal_ptr=Pointer_copy(vis_ptr) $
        ELSE vis_cal_ptr=vis_ptr
    print,N_ELEMENTS(gain_ptr)
    print,n_pol_vis
    FOR pol_i=0,n_pol_vis-1 DO BEGIN
        gain_arr1=*gain_ptr[gain_pol_arr1[pol_i]]
        gain_arr2=*gain_ptr[gain_pol_arr2[pol_i]]
;        IF Keyword_Set(invert_gain) THEN BEGIN
;            gain_arr1=weight_invert(Conj(gain_arr1))
;            gain_arr2=weight_invert(Conj(gain_arr2))
;        ENDIF
        vis_gain=gain_arr1[inds_A]*Conj(gain_arr2[inds_B])
        *vis_cal_ptr[pol_i]*=Weight_invert(vis_gain)
    ENDFOR
    RETURN,vis_cal_ptr
ENDIF ELSE BEGIN
    ;return a complex array, not a pointer, and don't overwrite if selecting one pol
    vis_cal=*vis_ptr[pol_i] 
    
    gain_arr1=*gain_ptr[gain_pol_arr1[pol_i]]
    gain_arr2=*gain_ptr[gain_pol_arr2[pol_i]]
;    IF Keyword_Set(invert_gain) THEN BEGIN
;        gain_arr1=weight_invert(Conj(gain_arr1))
;        gain_arr2=weight_invert(Conj(gain_arr2))
;    ENDIF
    vis_gain=gain_arr1[inds_A]*Conj(gain_arr2[inds_B])
    vis_cal*=Weight_invert(vis_gain)
    RETURN,vis_cal
ENDELSE

END
