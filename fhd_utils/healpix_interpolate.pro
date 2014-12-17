FUNCTION healpix_interpolate,healpix_map,obs,nside=nside,hpx_inds=hpx_inds,from_kelvin=from_kelvin

n_hpx=nside2npix(nside)
IF N_Elements(hpx_inds) EQ 0 THEN hpx_inds=Lindgen(n_hpx)
astr=obs.astr
dimension=obs.dimension
elements=obs.elements
xy2ad,meshgrid(dimension,elements,1),meshgrid(dimension,elements,2),astr,ra_arr,dec_arr
radec_i=where(Finite(ra_arr))

IF size(healpix_map,/type) EQ 10 THEN BEGIN ;check if pointer type, and if so allow it to be a pointer array
    ptr_flag=1
    n_map=N_Elements(healpix_map)
    IF n_map GT 1 THEN BEGIN
        map_interp=Ptrarr(n_map)
        FOR i=0,n_map-1 DO map_interp[i]=Ptr_new(Fltarr(dimension,elements))
    ENDIF ELSE map_interp=Ptr_new(Fltarr(dimension,elements))
ENDIF ELSE BEGIN
    ptr_flag=0
    n_map=1
    map_interp=Fltarr(dimension,elements)
ENDELSE

pix2vec_ring,nside,hpx_inds,pix_coords
vec2ang,pix_coords,pix_dec,pix_ra,/astro
ad2xy,pix_ra,pix_dec,astr,xv_hpx,yv_hpx

hpx_i_use=where((xv_hpx GT 0) AND (xv_hpx LT (dimension-1)) AND (yv_hpx GT 0) AND (yv_hpx LT (elements-1)),n_hpx_use) 
IF n_hpx_use EQ 0 THEN BEGIN
    print,"Error: Map has no valid Healpix indices"
    RETURN,map_interp
ENDIF
xv_hpx=xv_hpx[hpx_i_use]
yv_hpx=yv_hpx[hpx_i_use]

image_mask=Fltarr(dimension,elements)
image_mask[Min(Floor(xv_hpx)):Max(Ceil(xv_hpx)),Min(Floor(yv_hpx)):Max(Ceil(yv_hpx))]=1

x_frac=1.-(xv_hpx-Floor(xv_hpx))
y_frac=1.-(yv_hpx-Floor(yv_hpx))
IF Keyword_Set(from_kelvin) THEN pixel_area_cnv=convert_kelvin_jansky(1.,nside=nside,freq=obs.freq_center) $
    ELSE pixel_area_cnv=((obs.degpix*!DtoR)^2.)/(4.*!Pi/n_hpx) ; (steradian/new pixel)/(steradian/old pixel)
pixel_area_cnv=1.

weights_img=fltarr(dimension,elements)
weights_img[Floor(xv_hpx),Floor(yv_hpx)]+=x_frac*y_frac
weights_img[Floor(xv_hpx),Ceil(yv_hpx)]+=x_frac*(1-y_frac)
weights_img[Ceil(xv_hpx),Floor(yv_hpx)]+=(1-x_frac)*y_frac
weights_img[Ceil(xv_hpx),Ceil(yv_hpx)]+=(1-x_frac)*(1-y_frac)
FOR map_i=0,n_map-1 DO BEGIN
    model_img=fltarr(dimension,elements)
    IF Ptr_flag THEN hpx_vals=(*healpix_map[map_i])[hpx_i_use] ELSE hpx_vals=healpix_map[hpx_i_use] 
    hpx_vals*=pixel_area_cnv ;convert 
    
    model_img[Floor(xv_hpx),Floor(yv_hpx)]+=x_frac*y_frac*hpx_vals
    model_img[Floor(xv_hpx),Ceil(yv_hpx)]+=x_frac*(1-y_frac)*hpx_vals
    model_img[Ceil(xv_hpx),Floor(yv_hpx)]+=(1-x_frac)*y_frac*hpx_vals
    model_img[Ceil(xv_hpx),Ceil(yv_hpx)]+=(1-x_frac)*(1-y_frac)*hpx_vals
    model_img*=weight_invert(weights_img)
    
    mask=fltarr(dimension,elements)
    mask[radec_i]=1
    interp_i=where((model_img EQ 0) AND (mask GT 0),n_interp)
    IF n_interp GT 0 THEN BEGIN
        fraction_int=n_interp/Total(mask)
        min_valid=4.
        min_width=Ceil(2.*Sqrt(min_valid/(!Pi*fraction_int)))>3.
        model_int=model_img
        model_int[interp_i]=!Values.F_NAN
        model_filtered=Median(model_int,min_width,/even)
        i_nan=where(Finite(model_filtered,/nan),n_nan)
        iter=0
        WHILE n_nan GT 0 DO BEGIN
            IF iter GT 5 THEN BREAK
            nan_x=i_nan mod dimension
            nan_y=Floor(i_nan/dimension)
            width_use=Ceil(min_width*(1.+iter)/2.)
            FOR i=0L,n_nan-1 DO model_filtered[i_nan[i]]=Median(model_filtered[(nan_x[i]-width_use)>0:(nan_x[i]+width_use)<(dimension-1),(nan_y[i]-width_use)>0:(nan_y[i]+width_use)<(elements-1)],/even)
            i_nan=where(Finite(model_filtered,/nan),n_nan)
            iter+=1
        ENDWHILE
        IF n_nan GT 0 THEN model_filtered[i_nan]=0.
        model_img[interp_i]=model_filtered[interp_i]
    ENDIF
    
    IF Ptr_flag THEN *map_interp[map_i]=model_img*image_mask ELSE map_interp=model_img*image_mask
ENDFOR

RETURN,map_interp
END