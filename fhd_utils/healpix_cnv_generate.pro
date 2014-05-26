FUNCTION healpix_cnv_generate,obs,file_path_fhd=file_path_fhd,nside=nside,mask=mask,hpx_radius=hpx_radius,$
    restore_last=restore_last,silent=silent,pointer_return=pointer_return,no_save=no_save,restrict_hpx_inds=restrict_hpx_inds,_Extra=extra

IF Keyword_Set(restore_last) AND (file_test(file_path_fhd+'_hpxcnv'+'.sav') EQ 0) THEN BEGIN 
    IF ~Keyword_Set(silent) THEN print,file_path_fhd+'_hpxcnv'+'.sav' +' Not found. Recalculating.' 
    restore_last=0
ENDIF
IF Keyword_Set(restore_last) THEN BEGIN
    IF ~Keyword_Set(silent) THEN print,'Saved Healpix grid map restored'
    restore,file_path_fhd+'_hpxcnv'+'.sav'
    nside=hpx_cnv.nside
    RETURN,hpx_cnv
ENDIF ELSE IF N_Elements(obs) EQ 0 THEN restore,file_path_fhd+'_obs.sav'

t00=Systime(1)
astr=obs.astr
dimension=obs.dimension
elements=obs.elements
IF N_Elements(hpx_radius) EQ 0 THEN radius=obs.degpix*(dimension>elements)/4. ELSE radius=hpx_radius
;all angles in DEGREES
;uses RING index scheme
IF ~Keyword_Set(nside) THEN BEGIN
    pix_sky=4.*!Pi*!RaDeg^2./Product(Abs(astr.cdelt))
    Nside=2.^(Ceil(ALOG(Sqrt(pix_sky/12.))/ALOG(2))) ;=1024. for 0.1119 degrees/pixel
;    nside*=2.
ENDIF
npix=nside2npix(nside)

;check if a string, if it is assume it is a filepath to a save file with the desired indices 
; (will NOT be over-written with the indices)
IF Keyword_Set(restrict_hpx_inds) AND (size(restrict_hpx_inds,/type) NE 7) THEN restrict_hpx_inds=observation_healpix_inds_select(obs)
IF size(restrict_hpx_inds,/type) EQ 7 THEN BEGIN 
    IF file_test(restrict_hpx_inds) THEN restrict_hpx_inds=getvar_savefile(restrict_hpx_inds,'hpx_inds') ELSE BEGIN
        file_path_use=filepath(restrict_hpx_inds,root=Rootdir('fhd'),subdir='Observations')
        IF file_test(file_path_use) THEN hpx_inds=getvar_savefile(file_path_use,'hpx_inds') $
            ELSE restrict_hpx_inds+="-- FILE NOT FOUND"
    ENDELSE
ENDIF

IF N_Elements(hpx_inds) GT 1 THEN BEGIN
    pix2vec_ring,nside,hpx_inds,pix_coords
    vec2ang,pix_coords,pix_dec,pix_ra,/astro
    ad2xy,pix_ra,pix_dec,astr,xv_hpx,yv_hpx
ENDIF ELSE BEGIN
    ang2vec,obs.obsdec,obs.obsra,cen_coords,/astro
    Query_disc,nside,cen_coords,radius,hpx_inds0,ninds,/deg
    pix2vec_ring,nside,hpx_inds0,pix_coords
    vec2ang,pix_coords,pix_dec,pix_ra,/astro
    ad2xy,pix_ra,pix_dec,astr,xv_hpx,yv_hpx
    pix_coords=0
    pix_ra=0
    pix_dec=0
    
    ;NOTE: slightly more restrictive boundary here ('LT' and 'GT' instead of 'LE' and 'GE') 
    pix_i_use=where((xv_hpx GT 0) AND (xv_hpx LT dimension-1) AND (yv_hpx GT 0) AND (yv_hpx LT elements-1),n_hpx_use)
    xv_hpx=xv_hpx[pix_i_use]
    yv_hpx=yv_hpx[pix_i_use]
    IF Keyword_Set(mask) THEN BEGIN
        hpx_mask00=mask[Floor(xv_hpx),Floor(yv_hpx)]
        hpx_mask01=mask[Floor(xv_hpx),Ceil(yv_hpx)]
        hpx_mask10=mask[Ceil(xv_hpx),Floor(yv_hpx)]
        hpx_mask11=mask[Ceil(xv_hpx),Ceil(yv_hpx)]
        hpx_mask=Temporary(hpx_mask00)*Temporary(hpx_mask01)*Temporary(hpx_mask10)*Temporary(hpx_mask11)
        pix_i_use2=where(Temporary(hpx_mask),n_hpx_use)
        xv_hpx=xv_hpx[pix_i_use2]
        yv_hpx=yv_hpx[pix_i_use2]
        pix_i_use=pix_i_use[pix_i_use2]
    ENDIF 
    hpx_inds=hpx_inds0[pix_i_use]
ENDELSE

x_frac=1.-(xv_hpx-Floor(xv_hpx))
y_frac=1.-(yv_hpx-Floor(yv_hpx))
;image_inds=Long64(Floor(xv_hpx)+dimension*Floor(yv_hpx))
;corner_inds=Long64([0,1,dimension,dimension+1])

min_bin=Min(Floor(xv_hpx)+dimension*Floor(yv_hpx))>0L
max_bin=Max(Ceil(xv_hpx)+dimension*Ceil(yv_hpx))<(dimension*elements-1L)
h00=histogram(Floor(xv_hpx)+dimension*Floor(yv_hpx),min=min_bin,max=max_bin,/binsize,reverse_ind=ri00)
h01=histogram(Floor(xv_hpx)+dimension*Ceil(yv_hpx),min=min_bin,max=max_bin,/binsize,reverse_ind=ri01)
h10=histogram(Ceil(xv_hpx)+dimension*Floor(yv_hpx),min=min_bin,max=max_bin,/binsize,reverse_ind=ri10)
h11=histogram(Ceil(xv_hpx)+dimension*Ceil(yv_hpx),min=min_bin,max=max_bin,/binsize,reverse_ind=ri11)
htot=h00+h01+h10+h11
inds=where(htot,n_img_use)

n_arr=htot[inds]

i_use=inds+min_bin
sa=Ptrarr(n_img_use,/allocate)
ija=Ptrarr(n_img_use,/allocate)

FOR i=0L,n_img_use-1L DO BEGIN
    ind0=inds[i]
    sa0=fltarr(n_arr[i])
    ija0=Lonarr(n_arr[i])
    bin_i=Total([0L,h00[ind0],h01[ind0],h10[ind0],h11[ind0]],/cumulative)
    IF h00[ind0] GT 0 THEN BEGIN
        bi=0
        inds1=ri00[ri00[ind0]:ri00[ind0+1]-1]
        sa0[bin_i[bi]:bin_i[bi+1]-1]=x_frac[inds1]*y_frac[inds1]
        ija0[bin_i[bi]:bin_i[bi+1]-1]=inds1
    ENDIF
    IF h01[ind0] GT 0 THEN BEGIN
        bi=1
        inds1=ri01[ri01[ind0]:ri01[ind0+1]-1]
        sa0[bin_i[bi]:bin_i[bi+1]-1]=x_frac[inds1]*(1.-y_frac[inds1])
        ija0[bin_i[bi]:bin_i[bi+1]-1]=inds1
    ENDIF
    IF h10[ind0] GT 0 THEN BEGIN
        bi=2
        inds1=ri10[ri10[ind0]:ri10[ind0+1]-1]
        sa0[bin_i[bi]:bin_i[bi+1]-1]=(1.-x_frac[inds1])*y_frac[inds1]
        ija0[bin_i[bi]:bin_i[bi+1]-1]=inds1
    ENDIF
    IF h11[ind0] GT 0 THEN BEGIN
        bi=3
        inds1=ri11[ri11[ind0]:ri11[ind0+1]-1]
        sa0[bin_i[bi]:bin_i[bi+1]-1]=(1.-x_frac[inds1])*(1.-y_frac[inds1])
        ija0[bin_i[bi]:bin_i[bi+1]-1]=inds1
    ENDIF
    *sa[i]=sa0
    *ija[i]=ija0
        
ENDFOR

hpx_cnv={nside:nside,ija:ija,sa:sa,i_use:i_use,inds:hpx_inds}
IF tag_exist(obs,'healpix') THEN BEGIN
    IF N_Elements(restrict_hpx_inds) NE 1 THEN ind_list="UNSPECIFIED" ELSE ind_list=restrict_hpx_inds
    n_hpx=N_Elements(hpx_inds)
    IF Keyword_Set(mask) THEN BEGIN
        mask_test=healpix_cnv_apply(mask,hpx_cnv)
        mask_test_i0=where(mask_test EQ 0,n_zero_hpx)
    ENDIF ELSE n_zero_hpx=-1
    obs.healpix.nside=Long(nside)
    obs.healpix.ind_list=String(ind_list)
    obs.healpix.n_pix=Long(n_hpx)
    obs.healpix.n_zero=Long(n_zero_hpx)
ENDIF

IF ~Keyword_Set(no_save) THEN save,hpx_cnv,filename=file_path_fhd+'_hpxcnv'+'.sav',/compress
IF Keyword_Set(pointer_return) THEN RETURN,Ptr_new(hpx_cnv) ELSE RETURN,hpx_cnv
END
