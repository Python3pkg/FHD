FUNCTION hera_beam_setup_gain,obs,antenna,file_path_fhd=file_path_fhd,$
    za_arr=za_arr,az_arr=az_arr,psf_image_dim=psf_image_dim,Jdate_use=Jdate_use

n_ant_pol=Max(antenna.n_pol)
nfreq_bin=Max(antenna.nfreq_bin)
IF N_Elements(file_path_fhd) EQ 0 THEN file_path_fhd=''
n_tile=obs.n_tile
beam_model_version=Max(antenna.model_version)
xvals_interp=za_arr*Sin(az_arr*!DtoR)/obs.degpix+obs.dimension/2.
yvals_interp=za_arr*Cos(az_arr*!DtoR)/obs.degpix+obs.elements/2.
freq_center=antenna[0].freq ;all need to be identical, so just use the first
speed_light=299792458. ;speed of light, in meters/second
icomp=Complex(0,1)

pol_name=['X','Y']
hera_jones_filepath=filepath('HERA_Jones.sav',root=rootdir('FHD'),sub='instrument_config')
;calculate group identifications (used to set pointers to identical models)
FOR pol_i=0,n_ant_pol-1 DO BEGIN
    gi=0
    n_ungrouped=n_tile
    ungrouped_i=where(antenna.group_id[pol_i] EQ -1,n_ungrouped)
    WHILE n_ungrouped GT 0 DO BEGIN
        ref_i=ungrouped_i[0]
        antenna[ref_i].group_id[pol_i]=gi
        FOR ug_i=1L,n_ungrouped-1 DO IF Total(*antenna[ungrouped_i[ug_i]].gain[pol_i] - *antenna[ref_i].gain[pol_i]) EQ 0 THEN antenna[ungrouped_i[ug_i]].group_id[pol_i]=gi 
        ungrouped_i=where(antenna.group_id[pol_i] EQ -1,n_ungrouped)
        gi+=1
    ENDWHILE
ENDFOR

;build the instrumental pol Jones matrix
;CASE beam_model_version OF
;    2: BEGIN
        horizon_test=where(abs(za_arr) GE 90.,n_horizon_test,complement=pix_use,ncomplement=n_pix)
        horizon_mask=fltarr(psf_image_dim,psf_image_dim)+1
        IF n_horizon_test GT 0 THEN horizon_mask[horizon_test]=0  
        Jones_matrix=Ptrarr(n_ant_pol,n_ant_pol,nfreq_bin)        
        
        nside=getvar_savefile(hera_jones_filepath,'nside')
        n_hpx= 12L * nside^2
        ;Healpix ordering is 'RING'
        hera_frequency_array=getvar_savefile(hera_jones_filepath,'frequencies_mhz')
        nfreq = size(hera_frequency_array, /n_ele)
        hera_jones_in=Ptrarr(8,n_hpx,nfreq)
        hera_jones_in=getvar_savefile(hera_jones_filepath,'jones_hpx_map',/pointer_return)
        
        hera_beam=Ptrarr(2)
        
        hpx_inds=Lindgen(n_hpx)
        pix2vec_ring,nside,hpx_inds,pix_coords
        vec2ang,pix_coords,pix_za,pix_az ;returns RADIANS
        
        comp_map = [[0,0,1,1],[0,1,0,1]] ; maps linear index to 2x2 array components. For use in indexing final jones matrix
        FOR cp=0,3 DO BEGIN
            i_re = cp ;index for the real component
            i_im = cp + 4 ; index for the imaginary component
            
            ii = (comp_map[cp,*])[0]
            jj = (comp_map[cp,*])[1]
            
            hera_jones_interp=Fltarr(n_hpx,nfreq_bin)
            
            FOR hpx_i=0L,n_hpx-1 DO hera_jones_interp_re[hpx_i]=Interpol((*hera_jones_in)[i_re,hpx_i,*], hera_frequency_array, freq_center)
            FOR hpx_i=0l,n_hpx-1 DO hera_jones_interp_im[hpx_i]=Interpol((*hera_jones_in)[i_im,hpx_i,*], hera_frequency_array, freq_center_im)
            
            hera_jones_interp_arr_re=Ptrarr(nfreq_bin)
            hera_jones_interp_arr_im=Ptrarr(nfreq_bin)
            
            FOR freq_i=0,nfreq_bin-1 DO hera_jones_interp_arr_re[freq_i]=Ptr_new(hera_jones_interp_re[*,freq_i])
            FOR freq_i=0,nfreq_bin-1 DO hera_jones_interp_arr_im[freq_i]=Ptr_new(hera_jones_interp_im[*,freq_i])
            
            hera_jones_grid_arr_re=healpix_interpolate(hera_jones_interp_arr_re,obs,nside=nside,Jdate_use=Jdate_use,coord_sys='equatorial')
            hera_jones_grid_arr_im=healpix_interpolate(hera_jones_interp_arr_im,obs,nside=nside,Jdate_use=Jdate_use,coord_sys='equatorial')
            
            ;FOR freq_i=0,nfreq_bin-1 DO Jones_matrix[pol_i,pol_i,freq_i]=Ptr_new(Interpolate(*hera_beam_grid_arr[freq_i],xvals_interp,yvals_interp)*horizon_mask)
            for freq_i=0,nfreq_bin-1 do Jones_matrix[ii,jj,freq_i] = $
              Ptr_new(Complex(Interpolate(*hera_jones_grid_arr_re[freq_i],xvals_interp,yvals_interp)*horizon_mask, $
              Interpolate(*hera_jones_grid_arr_im[freq_i],xvals_interp,yvals_interp)*horizon_mask))
              
        ENDFOR
    
;    END
;    ELSE: BEGIN      
;        print,"Using default beam model"
;        antenna_height=antenna[0].height
;        wavelength=speed_light/freq_center
;        Jones_matrix=antenna.jones
;        FOR freq_i=0,nfreq_bin-1 DO BEGIN
;            groundplane=2.*Sin(Cos(za_arr*!DtoR)*(2.*!Pi*(antenna_height)/wavelength[freq_i])) ;should technically have zc_arr, but until that is nonzero this is the same and faster
;            groundplane0=2.*Sin(Cos(0.*!DtoR)*2.*!Pi*antenna_height/wavelength[freq_i]) ;normalization factor
;            groundplane/=groundplane0
;            Jones_matrix[0,0,freq_i]=Ptr_new(Cos(za_arr*!DtoR)*Sin(az_arr*!DtoR)*groundplane)
;            Jones_matrix[1,0,freq_i]=Ptr_new(Cos(az_arr*!DtoR)*groundplane)
;            Jones_matrix[0,1,freq_i]=Ptr_new(Cos(za_arr*!DtoR)*Cos(az_arr*!DtoR)*groundplane)
;            Jones_matrix[1,1,freq_i]=Ptr_new(-Sin(az_arr*!DtoR)*groundplane)
;;            Jones_matrix[0,0,freq_i]=Ptr_new(Cos(za_arr*!DtoR)*Cos(az_arr*!DtoR)*groundplane)
;;            Jones_matrix[1,0,freq_i]=Ptr_new(Sin(az_arr*!DtoR)*groundplane)
;;            Jones_matrix[0,1,freq_i]=Ptr_new(Cos(za_arr*!DtoR)*Sin(az_arr*!DtoR)*groundplane)
;;            Jones_matrix[1,1,freq_i]=Ptr_new(-Cos(az_arr*!DtoR)*groundplane)
;        ENDFOR
;    ENDELSE
;ENDCASE
antenna.jones=Jones_matrix


RETURN,antenna
END