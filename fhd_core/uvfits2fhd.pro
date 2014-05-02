
;+
; :Description:
;    uvfits2fhd is the main program for working with uvfits data. 
;    It will read the uvfits file, grid the data, generate the holographic mapping functions, 
;    and run Fast Holographic Deconvolution
;
;
;
; :Keywords:
;    data_directory - working directory
;    
;    filename - uvfits filename, omitting the .uvfits extension. 
;       If the data is already calibrated, it should end with _cal.uvfits instead of just .uvfits
;    
;    beam_recalculate - if set, generates a new beam model
;    
;    mapfn_recalculate - if not set to 0, will generate Holographic Mapping Functions for each polarization
;    
;    dimension - desired dimension in pixels of the final images
;    
;    kbinsize - pixel size in wavelengths of the uv image. 
;    
;    n_pol - 1: use xx only, 2: use xx and xy, 4: use xx, yy, xy, and yx (Default: as many as are available)
;    
;    flag_visibilities - set to look for anomalous visibility data and update flags 
;    
;    Extra - pass any non-default parameters to fast_holographic_deconvolution through this parameter 
;
; :Author: isullivan 2012
;-
PRO uvfits2fhd,file_path_vis,export_images=export_images,cleanup=cleanup,recalculate_all=recalculate_all,$
    beam_recalculate=beam_recalculate,mapfn_recalculate=mapfn_recalculate,grid_recalculate=grid_recalculate,$
    n_pol=n_pol,flag_visibilities=flag_visibilities,silent=silent,GPU_enable=GPU_enable,deconvolve=deconvolve,transfer_mapfn=transfer_mapfn,$
    healpix_recalculate=healpix_recalculate,tile_flag_list=tile_flag_list,$
    file_path_fhd=file_path_fhd,force_data=force_data,force_no_data=force_no_data,freq_start=freq_start,freq_end=freq_end,$
    calibrate_visibilities=calibrate_visibilities,transfer_calibration=transfer_calibration,error=error,$
    calibration_catalog_file_path=calibration_catalog_file_path,$
    calibration_image_subtract=calibration_image_subtract,calibration_visibilities_subtract=calibration_visibilities_subtract,$
    weights_grid=weights_grid,save_visibilities=save_visibilities,return_cal_visibilities=return_cal_visibilities,$
    return_decon_visibilities=return_decon_visibilities,snapshot_healpix_export=snapshot_healpix_export,cmd_args=cmd_args,_Extra=extra

;Compile idl with a specific option, and treat out-of-range subscripts as an error. Math exceptions not reported. Free up memory
;via garbage collection.
compile_opt idl2,strictarrsubs   
except=!except
!except=0
error=0
heap_gc
t0=Systime(1)

;Set recalculation defaults.
IF N_Elements(recalculate_all) EQ 0 THEN recalculate_all=1
IF N_Elements(calibrate_visibilities) EQ 0 THEN calibrate_visibilities=0
IF N_Elements(beam_recalculate) EQ 0 THEN beam_recalculate=recalculate_all
IF N_Elements(mapfn_recalculate) EQ 0 THEN mapfn_recalculate=recalculate_all
IF N_Elements(grid_recalculate) EQ 0 THEN grid_recalculate=recalculate_all
IF N_Elements(healpix_recalculate) EQ 0 THEN healpix_recalculate=0
IF N_Elements(flag_visibilities) EQ 0 THEN flag_visibilities=0
IF N_Elements(transfer_mapfn) EQ 0 THEN transfer_mapfn=0
IF N_Elements(save_visibilities) EQ 0 THEN save_visibilities=1

;If the mapping function will be deleted later, then it won't be saved to disk.
IF Keyword_Set(cleanup) THEN IF cleanup GT 0 THEN no_save=1

;;;;;;;;;Potentially old code, deletable?
;IF N_Elements(GPU_enable) EQ 0 THEN GPU_enable=0
;IF Keyword_Set(GPU_enable) THEN BEGIN
;    Defsysv,'GPU',exist=gpuvar_exist
;    IF gpuvar_exist eq 0 THEN GPUinit
;    IF !GPU.mode NE 1 THEN GPU_enable=0
;ENDIF

print,'Processing: ',file_path_vis
print,systime()
print,'Output file_path:',file_path_fhd
ext='.uvfits'

;Set filenames.
fhd_dir=file_dirname(file_path_fhd)
basename=file_basename(file_path_fhd)
header_filepath=file_path_fhd+'_header.sav'
flags_filepath=file_path_fhd+'_flags.sav'
;vis_filepath=file_path_fhd+'_vis.sav'     ;;;;Why is this commented out, deletable?
obs_filepath=file_path_fhd+'_obs.sav'
params_filepath=file_path_fhd+'_params.sav'
hdr_filepath=file_path_fhd+'_hdr.sav'
fhd_filepath=file_path_fhd+'_fhd.sav'
autocorr_filepath=file_path_fhd+'_autos.sav'
cal_filepath=file_path_fhd+'_cal.sav'
model_filepath=file_path_fhd+'_vis_cal.sav'

;Deconvolve if this is a new FHD run.
IF N_Elements(deconvolve) EQ 0 THEN IF file_test(fhd_filepath) EQ 0 THEN deconvolve=1

pol_names=['xx','yy','xy','yx','I','Q','U','V']

;If the uv save file doesn't exist, then force recalculation of the grid.
IF Keyword_Set(n_pol) THEN n_pol1=n_pol ELSE n_pol1=1
test_uv=1 & FOR pol_i=0,n_pol1-1 DO test_uv=file_test(file_path_fhd+'_uv_'+pol_names[pol_i]+'.sav')
IF test_uv EQ 0 THEN grid_recalculate=1

;If the map function doesn't exist, and if the transfer map function isn't set to the fhd file path, then
;force recalculation of the map function and the grid.
test_mapfn=1 & FOR pol_i=0,n_pol1-1 DO test_mapfn=file_test(file_path_fhd+'_mapfn_'+pol_names[pol_i]+'.sav')
IF Keyword_Set(transfer_mapfn) THEN BEGIN
    IF size(transfer_mapfn,/type) NE 7 THEN transfer_mapfn=basename
    IF basename NE transfer_mapfn THEN BEGIN
        mapfn_recalculate=0
        test_mapfn=1
    ENDIF
ENDIF
IF test_mapfn EQ 0 THEN IF Keyword_Set(deconvolve) THEN mapfn_recalculate=1
IF Keyword_Set(mapfn_recalculate) THEN grid_recalculate=1

;Data flag determines whether or not to calculate data files. Calculate if the data files are not already present.
;If there is no visibility save file, but the visibilites are to be saved, then calculate. Recalculate if keywords set.
data_flag= ~(file_test(flags_filepath) AND file_test(obs_filepath) AND file_test(params_filepath))
vis_file_list=file_search(file_path_fhd+'_vis*',count=vis_file_flag)
IF Keyword_Set(beam_recalculate) OR Keyword_Set(grid_recalculate) OR Keyword_Set(mapfn_recalculate) OR $
   (Keyword_Set(save_visibilities) AND (vis_file_flag EQ 0)) THEN data_flag=1

;If force keywords are set, override whether or not to calculate data files.
IF Keyword_Set(force_data) THEN data_flag=1
IF Keyword_Set(force_no_data) THEN data_flag=0


;***Calculating data files***

IF Keyword_Set(data_flag) THEN BEGIN
    ;Error if the file path specifed doesn't contain uvfits files.
    IF file_test(file_path_vis) EQ 0 THEN BEGIN
        print,"File: "+file_path_vis+" not found! Returning"
        error=1
        RETURN
    ENDIF
    
    ;Read uvfits into a structure. Parse out the u, v, w, baseline, and time array from the large data structure.
    ;Extract variables from header.Only keep polarizations specified using an operation that requires no extra space. 
    ;Free up memory.
    data_struct=mrdfits(file_path_vis,0,data_header0,/silent)
    hdr=vis_header_extract(data_header0, params = data_struct.params)    
    params=vis_param_extract(data_struct.params,hdr)
    data_array=Temporary(data_struct.array[*,0:n_pol-1,*])
    data_struct=0.
    

    ;***Determine the map projection, and set the uv plane. Create strictly defined obs structure.***
    obs=vis_struct_init_obs(file_path_vis,hdr,params,n_pol=n_pol,_Extra=extra)


    ;Fill variables from structure.
    pol_dim=hdr.pol_dim
    freq_dim=hdr.freq_dim
    real_index=hdr.real_index
    imaginary_index=hdr.imaginary_index
    flag_index=hdr.flag_index
    n_pol=obs.n_pol
    n_freq=obs.n_freq
    
    ;Create a pointer per polarization for the complex array of uvfits data and the flag information. Free memory.
    vis_arr=Ptrarr(n_pol,/allocate)
    flag_arr=Ptrarr(n_pol,/allocate)
    FOR pol_i=0,n_pol-1 DO BEGIN
        *vis_arr[pol_i]=Complex(reform(data_array[real_index,pol_i,*,*]),Reform(data_array[imaginary_index,pol_i,*,*]))
        *flag_arr[pol_i]=reform(data_array[flag_index,pol_i,*,*])
    ENDFOR
    data_array=0 
    flag_arr0=0      ;****not used? deletable?

    
    ;***Read in or construct a new beam model. Set up the psf structure. Create a pointer per polarization for the average beam image.***
    print,'Calculating beam model'
    psf=beam_setup(obs,file_path_fhd,restore_last=(Keyword_Set(beam_recalculate) ? 0:1),silent=silent,timing=t_beam,no_save=no_save,_Extra=extra)
    IF Keyword_Set(t_beam) THEN print,'Beam modeling time: ',t_beam
    beam=Ptrarr(n_pol,/allocate)
    FOR pol_i=0,n_pol-1 DO *beam[pol_i]=beam_image(psf,obs,pol_i=pol_i,/fast)>0.

    
    ;Calculate flags from basic approaches, like channels edges and missing data. Update the flag array?? Print status of obs structure.
    flag_arr=vis_flag_basic(flag_arr,obs,params,n_pol=n_pol,n_freq=n_freq,freq_start=freq_start,$
        freq_end=freq_end,tile_flag_list=tile_flag_list,_Extra=extra)
    vis_flag_update,flag_arr,obs,psf,params
    obs_status,obs
    
    ;Set the transfer calibration filepath and force visibility calibration if keyword set.
    IF Keyword_Set(transfer_calibration) THEN BEGIN
        calibrate_visibilities=1
        IF size(transfer_calibration,/type) LT 7 THEN transfer_calibration=cal_filepath
    ENDIF
    

    ;***Read in or generate a list of point sources above a threshold to calibrate. Creat cal structure***
    IF Keyword_Set(calibrate_visibilities) THEN BEGIN
        print,"Calibrating visibilities"
        IF ~Keyword_Set(transfer_calibration) AND ~Keyword_Set(calibration_source_list) THEN $
            calibration_source_list=generate_source_cal_list(obs,psf,catalog_path=calibration_catalog_file_path,_Extra=extra)
        cal=vis_struct_init_cal(obs,params,source_list=calibration_source_list,catalog_path=calibration_catalog_file_path,_Extra=extra)
        IF Keyword_Set(calibration_visibilities_subtract) THEN calibration_image_subtract=0
        IF Keyword_Set(calibration_image_subtract) THEN return_cal_visibilities=1
        
        ;***Generate model visibilities for calibration*** ??
        vis_arr=vis_calibrate(vis_arr,cal,obs,psf,params,flag_ptr=flag_arr,file_path_fhd=file_path_fhd,$
             transfer_calibration=transfer_calibration,timing=cal_timing,error=error,model_uv_arr=model_uv_arr,$
             return_cal_visibilities=return_cal_visibilities,vis_model_ptr=vis_model_ptr,$
             calibration_visibilities_subtract=calibration_visibilities_subtract,silent=silent,_Extra=extra)
    
    ;Save compressed cal structure and update the flagged visibilites.    
    IF ~Keyword_Set(silent) THEN print,String(format='("Calibration timing: ",A)',Strn(cal_timing))
        save,cal,filename=cal_filepath,/compress
        vis_flag_update,flag_arr,obs,psf,params
    ENDIF
    
    ;Create an array of null pointers if the array doesn't exist. If any of the pointer is null, then set keyword to show model visibilities not returned.
    IF N_Elements(vis_model_ptr) EQ 0 THEN vis_model_ptr=Ptrarr(n_pol)  
    IF min(Ptr_valid(vis_model_ptr)) EQ 0 THEN return_cal_visibilities=0

    ;Determine whether or not to use the flagged visibilities calculated above...
    IF Keyword_Set(transfer_mapfn) THEN BEGIN
        flag_arr1=flag_arr

	;If the transfer map function file path was set to the new run path, use the flagging calculated above.
        IF basename EQ transfer_mapfn THEN BEGIN
            IF Keyword_Set(flag_visibilities) THEN BEGIN
                print,'Flagging anomalous data'
                vis_flag,vis_arr,flag_arr,obs,params,_Extra=extra
            ENDIF            
        ENDIF ELSE restore,filepath(transfer_mapfn+'_flags.sav',root=fhd_dir)

	;...
        SAVE,flag_arr,filename=flags_filepath,/compress
        n0=N_Elements(*flag_arr[0])
        n1=N_Elements(*flag_arr1[0])
        IF n1 GT n0 THEN BEGIN				;;*****I don't get this, wouldn't n0=n1 all the time due to above?
            ;If more data, zero out additional
            nf0=(size(*flag_arr[0],/dimension))[0]
            nb0=(size(*flag_arr[0],/dimension))[1]
            FOR pol_i=0,n_pol-1 DO BEGIN
                *flag_arr1[pol_i]=fltarr(size(*flag_arr1[pol_i],/dimension))
                (*flag_arr1[pol_i])[0:nf0-1,0:nb0-1]*=*flag_arr[pol_i]
            ENDFOR
            flag_arr=flag_arr1
            SAVE,flag_arr,filename=flags_filepath,/compress
        ENDIF
        IF n0 GT n1 THEN BEGIN
            ;If less data, return with an error!
            error=1
            RETURN
        ENDIF

    ENDIF ELSE BEGIN

	;Flag the visibilities using what was calculated above, or save the flags for later routines
        IF Keyword_Set(flag_visibilities) THEN BEGIN
            print,'Flagging anomalous data'
            vis_flag,vis_arr,flag_arr,obs,params,_Extra=extra
            SAVE,flag_arr,filename=flags_filepath,/compress
        ENDIF ELSE SAVE,flag_arr,filename=flags_filepath,/compress

    ENDELSE

    ;Calculate the visibility noise
    vis_noise_calc,obs,vis_arr,flag_arr

    ;Update user
    IF ~Keyword_Set(silent) THEN BEGIN
        tile_use_i=where((*obs.baseline_info).tile_use,n_tile_use,ncomplement=n_tile_cut)
        freq_use_i=where((*obs.baseline_info).freq_use,n_freq_use,ncomplement=n_freq_cut)
        print,String(format='(A," frequency channels used and ",A," channels flagged")',$
            Strn(n_freq_use),Strn(n_freq_cut))
        print,String(format='(A," tiles used and ",A," tiles flagged")',$
            Strn(n_tile_use),Strn(n_tile_cut))
        IF Tag_exist(*obs.baseline_info,'time_use') THEN BEGIN
            time_use_i=where((*obs.baseline_info).time_use,n_time_use,ncomplement=n_time_cut)
            print,String(format='(A," time steps used and ",A," time steps flagged")',$
                Strn(n_time_use),Strn(n_time_cut))
        ENDIF
    ENDIF
    
    ;Save the obs and params structure, and create the setting text file.
    SAVE,obs,filename=obs_filepath,/compress
    SAVE,params,filename=params_filepath,/compress
    fhd_log_settings,file_path_fhd,obs=obs,psf=psf,cal=cal,cmd_args=cmd_args
    
    ;Error handling if all data is flagged.
    IF obs.n_vis EQ 0 THEN BEGIN
        print,"All data flagged! Returning."
        error=1
        RETURN
    ENDIF
    
    ;Document all the auto correlations and save them in an array.
    autocorr_i=where((*obs.baseline_info).tile_A EQ (*obs.baseline_info).tile_B,n_autocorr)
    auto_corr=Ptrarr(n_pol)
    IF n_autocorr GT 0 THEN FOR pol_i=0,n_pol-1 DO BEGIN
        auto_vals=(*vis_arr[pol_i])[*,autocorr_i]
        auto_corr[pol_i]=Ptr_new(auto_vals)
    ENDFOR
    SAVE,auto_corr,obs,filename=autocorr_filepath,/compress
    
    ;Export the visibilites if keyword set.
    IF Keyword_Set(save_visibilities) THEN BEGIN
        t_save0=Systime(1)
        vis_export,obs,vis_arr,flag_arr,file_path_fhd=file_path_fhd,/compress
        IF Keyword_Set(return_cal_visibilities) THEN vis_export,obs,vis_model_ptr,flag_arr,file_path_fhd=file_path_fhd,/compress,/model
        t_save=Systime(1)-t_save0
        IF ~Keyword_Set(silent) THEN print,'Visibility save time: ',t_save
    ENDIF
        
    ;Initialize arrays
    t_grid=fltarr(n_pol)
    t_mapfn_gen=fltarr(n_pol)
    

    ;***Grid the visibilities***
    IF Keyword_Set(grid_recalculate) THEN BEGIN
        print,'Gridding visibilities'

	;Create pointer arrays
        IF Keyword_Set(deconvolve) THEN map_fn_arr=Ptrarr(n_pol,/allocate)
        image_uv_arr=Ptrarr(n_pol,/allocate)
        weights_arr=Ptrarr(n_pol,/allocate)      
        IF Keyword_Set(return_cal_visibilities) THEN model_uv_holo=Ptrarr(n_pol,/allocate)

	;Apply uniform weights if none are set.
        IF N_Elements(weights_grid) EQ 0 THEN weights_grid=1


        FOR pol_i=0,n_pol-1 DO BEGIN

	    ;Set keywords.
            IF Keyword_Set(return_cal_visibilities) THEN model_return=return_cal_visibilities
            IF Keyword_Set(snapshot_healpix_export) THEN preserve_visibilities=1 ELSE preserve_visibilities=0

	    ;Grid the visibilities and return unsubtracted uv.
            dirty_UV=visibility_grid(vis_arr[pol_i],flag_arr[pol_i],obs,psf,params,file_path_fhd,$
                timing=t_grid0,polarization=pol_i,weights=weights_grid,silent=silent,$
                mapfn_recalculate=mapfn_recalculate,return_mapfn=return_mapfn,error=error,no_save=no_save,$
                model_return=model_return,model_ptr=vis_model_ptr[pol_i],preserve_visibilities=preserve_visibilities,_Extra=extra)

	    ;Error handling
            IF Keyword_Set(error) THEN RETURN

            t_grid[pol_i]=t_grid0     ;***What's this for?

	    ;Save the weights and unsubtracted uv
            SAVE,dirty_UV,weights_grid,filename=file_path_fhd+'_uv_'+pol_names[pol_i]+'.sav',/compress

	    ;Return the map function if forced to recaulculate during deconvolution **?
            IF Keyword_Set(deconvolve) THEN IF mapfn_recalculate THEN *map_fn_arr[pol_i]=Temporary(return_mapfn)
            *image_uv_arr[pol_i]=Temporary(dirty_UV)

	    ;Save models if calibration visibilities are to be returned.
            IF Keyword_Set(return_cal_visibilities) THEN BEGIN
                model_uv=model_return
                SAVE,model_uv,weights_grid,filename=file_path_fhd+'_uv_model_'+pol_names[pol_i]+'.sav',/compress
                *model_uv_holo[pol_i]=Temporary(model_return)
                model_return=1
            ENDIF

	    ;Save the weights to an array and reset the weights for the next polarization in the loop.
            IF N_Elements(weights_grid) GT 0 THEN BEGIN
                *weights_arr[pol_i]=Temporary(weights_grid)
                weights_grid=1
            ENDIF

        ENDFOR

        IF ~Keyword_Set(silent) THEN print,'Gridding time:',t_grid
    ENDIF ELSE BEGIN
        print,'Visibilities not re-gridded'
    ENDELSE
    IF ~Keyword_Set(snapshot_healpix_export) THEN Ptr_free,vis_arr,flag_arr
ENDIF


IF N_Elements(cal) EQ 0 THEN IF file_test(cal_filepath) THEN cal=getvar_savefile(cal_filepath,'cal')
IF N_Elements(obs) EQ 0 THEN IF file_test(obs_filepath) THEN obs=getvar_savefile(obs_filepath,'obs')


;***Deconvolve point sources using fast holographic deconvolution.***
IF Keyword_Set(deconvolve) THEN BEGIN
    print,'Deconvolving point sources'

    fhd_wrap,obs,psf,params,fhd,cal,file_path_fhd=file_path_fhd,silent=silent,calibration_image_subtract=calibration_image_subtract,$
        transfer_mapfn=transfer_mapfn,map_fn_arr=map_fn_arr,image_uv_arr=image_uv_arr,weights_arr=weights_arr,$
        vis_model_ptr=vis_model_ptr,return_decon_visibilities=return_decon_visibilities,model_uv_arr=model_uv_arr,flag_arr=flag_arr,_Extra=extra

    ;Export models, flags, and the obs structure 
    IF Keyword_Set(return_decon_visibilities) AND Keyword_Set(save_visibilities) THEN vis_export,obs,vis_model_ptr,flag_arr,file_path_fhd=file_path_fhd,/compress,/model
ENDIF ELSE BEGIN
    print,'Gridded visibilities not deconvolved'
ENDELSE

;Generate fits data files and images.
IF Keyword_Set(export_images) THEN BEGIN
    IF file_test(file_path_fhd+'_fhd.sav') THEN BEGIN
        fhd_output,obs,fhd,cal,file_path_fhd=file_path_fhd,map_fn_arr=map_fn_arr,silent=silent,transfer_mapfn=transfer_mapfn,$
            image_uv_arr=image_uv_arr,weights_arr=weights_arr,beam_arr=beam,_Extra=extra 
    ENDIF ELSE BEGIN
        IF obs.residual GT 0 THEN BEGIN
            IF N_Elements(cal) EQ 0 THEN IF file_test(file_path_fhd+'_cal.sav') THEN RESTORE,file_path_fhd+'_cal.sav' 
            IF N_Elements(cal) GT 0 THEN source_array=cal.source_list
        ENDIF
        fhd_quickview,obs,psf,cal,image_uv_arr=image_uv_arr,weights_arr=weights_arr,source_array=source_array,$
            model_uv_holo=model_uv_holo,file_path_fhd=file_path_fhd,silent=silent,_Extra=extra
    ENDELSE
ENDIF

;optionally export frequency-splt Healpix cubes
IF Keyword_Set(snapshot_healpix_export) THEN healpix_snapshot_cube_generate,obs,psf,params,vis_arr,$
    vis_model_ptr=vis_model_ptr,file_path_fhd=file_path_fhd,flag_arr=flag_arr,_Extra=extra

undefine_fhd,map_fn_arr,cal,obs,fhd,image_uv_arr,weights_arr,model_uv_arr,vis_arr,flag_arr,vis_model_ptr

;;generate images showing the uv contributions of each tile. Very helpful for debugging!
;print,'Calculating individual tile uv coverage'
;mwa_tile_locate,obs=obs,params=params,psf=psf
timing=Systime(1)-t0
IF ~Keyword_Set(silent) THEN print,'Full pipeline time (minutes): ',Strn(Round(timing/60.))
print,''
!except=except
END
