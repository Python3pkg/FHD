PRO VLA_read
except=!except
!except=0 

data_directory=filepath('',root='VLA_DATA',subdir=[''])
filename_list=file_search(rootdir('mwa')+data_directory,'*_cal.uvfits',count=n_files)

filename_list=Strmid(filename_list,Strlen(rootdir('mwa')+data_directory))
FOR fi=0,n_files-1 DO filename_list[fi]=Strmid(filename_list[fi],0,Strpos(filename_list[fi],'.'))

version=0
alignment_file_header=['filename','degpix','obsra',' obsdec','zenra',' zendec','obsx','','obsy','zenx','zeny','obs_rotation','dx','dy','theta','scale']
textfast,alignment_file_header,filename='alignment'+'v'+strn(version),data_dir=data_directory,/write
FOR fi=0,n_files-1 DO BEGIN
IF fi NE 0 THEN CONTINUE
    filename=filename_list[fi]
    UPNAME=StrUpCase(filename)
    pcal=strpos(UPNAME,'_CAL')
    filename_use=StrMid(filename,0,pcal)
    beam_recalculate=1
    mapfn=1
    flag=1
    grid=1
    noise_calibrate=0
    fluxfix=0
    align=0
    GPU_enable=0
    VLA_uvfits2fhd,data_directory=data_directory,filename=filename,n_pol=2,version=version,$
        independent_fit=0,/reject_pol_sources,beam_recalculate=beam_recalculate,$
        mapfn_recalculate=mapfn,flag=flag,grid=grid,GPU_enable=GPU_enable,$
        silent=0,noise_calibrate=noise_calibrate,/no_output,instrument='VLA'
    fhd_output,filename=filename,data_directory=data_directory,version=version,$
        noise_calibrate=noise_calibrate,fluxfix=fluxfix,align=align;,/restore
ENDFOR
!except=except
END